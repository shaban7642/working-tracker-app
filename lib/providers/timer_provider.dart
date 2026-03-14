import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/attendance_event.dart';
import '../models/time_entry_event.dart';
import '../models/project.dart';
import '../services/graphql_api_service.dart';
import '../services/logger_service.dart';
import '../services/subscription_service.dart';
import 'auth_provider.dart';
import 'attendance_provider.dart';
import 'project_provider.dart';
import 'task_provider.dart';

/// Represents the current active session from the server
class ActiveSession {
  final String id;
  final String projectId;
  final String projectName;
  final DateTime startedAt; // Always stored in local time
  final bool isRunning;

  ActiveSession({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.startedAt,
    this.isRunning = true,
  });

  /// Calculate elapsed duration from server's startedAt time
  Duration get elapsedDuration {
    if (!isRunning) return Duration.zero;
    final now = DateTime.now();
    final elapsed = now.difference(startedAt);
    // Ensure we never return negative duration
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  ActiveSession copyWith({
    String? id,
    String? projectId,
    String? projectName,
    DateTime? startedAt,
    bool? isRunning,
  }) {
    return ActiveSession(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      startedAt: startedAt ?? this.startedAt,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  @override
  String toString() {
    return 'ActiveSession(id: $id, projectId: $projectId, projectName: $projectName, startedAt: $startedAt, isRunning: $isRunning, elapsed: ${elapsedDuration.inSeconds}s)';
  }
}

// Current timer state provider - uses ActiveSession from server
final currentTimerProvider = StateNotifierProvider<CurrentTimerNotifier, ActiveSession?>((ref) {
  return CurrentTimerNotifier(ref);
});

// Completed project durations provider - tracks time for projects worked on today (already ended)
final completedProjectDurationsProvider = StateProvider<Map<String, Duration>>((ref) => {});

class CurrentTimerNotifier extends StateNotifier<ActiveSession?> {
  final Ref _ref;
  late final LoggerService _logger;
  final _api = GraphqlApiService();
  final _socketService = SubscriptionService();
  StreamSubscription<TimeEntryEvent>? _socketSubscription;
  StreamSubscription<AttendanceEvent>? _attendanceSubscription;
  Timer? _uiRefreshTimer;
  DateTime? _taskStartTime;
  bool _isSwitchingProject = false; // Flag to prevent race condition during project switch

  DateTime? get taskStartTime => _taskStartTime;

  CurrentTimerNotifier(this._ref) : super(null) {
    _logger = _ref.read(loggerServiceProvider);
    _logger.info('Timer provider initialized (server-based)');
  }

  /// Start UI refresh timer to update elapsed time display every second
  void _startUiRefreshTimer() {
    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state != null && state!.isRunning) {
        // Create a new state object to trigger UI rebuild
        state = state!.copyWith();
      }
    });
  }

  /// Stop UI refresh timer
  void _stopUiRefreshTimer() {
    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = null;
  }

  /// Check for open entry from API and sync state
  /// Also fetches today's completed entries and starts listening to socket events
  /// This is the SOURCE OF TRUTH - socket events only update this state
  Future<void> checkAndSyncOpenEntry() async {
    try {
      _logger.info('Checking for open entry from server...');

      // Stop any existing UI refresh timer first
      _stopUiRefreshTimer();

      // Fetch open entry and today's completed entries in parallel
      final results = await Future.wait([
        _api.getOpenEntry(),
        _api.getTodayTimeEntries(),
      ]);

      final openEntry = results[0] as Map<String, dynamic>?;
      final todayEntries = results[1] as List<Map<String, dynamic>>;

      _logger.info('API Response - openEntry: $openEntry');
      _logger.info('API Response - todayEntries count: ${todayEntries.length}');

      // Process ALL completed entries (with endTime) for completedProjectDurations
      // This includes entries from earlier today, regardless of whether there's an open entry
      final Map<String, Duration> completedDurations = {};
      for (final entry in todayEntries) {
        // Only count completed entries (have endTime)
        if (entry['endTime'] != null) {
          final projectField = entry['project'];
          String? projectId;
          if (projectField is Map) {
            projectId = projectField['id']?.toString();
          } else {
            projectId = entry['projectId']?.toString() ?? projectField?.toString();
          }

          if (projectId != null) {
            // Try to get duration from the entry, or calculate it from timestamps
            Duration duration = Duration.zero;

            // First try to get duration from the API field (handle both int and double)
            final durationField = entry['duration'];
            if (durationField != null && durationField is num && durationField > 0) {
              duration = Duration(seconds: durationField.toInt());
              _logger.info('Got duration from API field: ${durationField}s');
            }

            // If no duration field, calculate from timestamps
            if (duration == Duration.zero) {
              final startTimeField = entry['startTime'];
              final endTimeField = entry['endTime'];
              DateTime? startTime;
              DateTime? endTime;

              if (startTimeField is String) {
                startTime = DateTime.tryParse(startTimeField)?.toLocal();
              } else if (startTimeField is DateTime) {
                startTime = startTimeField.toLocal();
              }

              if (endTimeField is String) {
                endTime = DateTime.tryParse(endTimeField)?.toLocal();
              } else if (endTimeField is DateTime) {
                endTime = endTimeField.toLocal();
              }

              if (startTime != null && endTime != null) {
                duration = endTime.difference(startTime);
                if (duration.isNegative) duration = Duration.zero;
                _logger.info('Calculated duration from timestamps: ${duration.inSeconds}s (start: $startTime, end: $endTime)');
              } else {
                _logger.warning('Could not calculate duration - startTime: $startTime, endTime: $endTime');
              }
            }

            if (duration.inSeconds > 0) {
              completedDurations[projectId] = (completedDurations[projectId] ?? Duration.zero) + duration;
              _logger.info('Added completed duration: $projectId -> ${duration.inSeconds}s (total: ${completedDurations[projectId]!.inSeconds}s)');
            }
          }
        }
      }

      // Update the completed durations provider (all closed entries from today)
      _ref.read(completedProjectDurationsProvider.notifier).state = completedDurations;
      _logger.info('Loaded ${completedDurations.length} completed project durations for today');

      // Check if there's NO open entry - clear timer state but keep durations
      if (openEntry == null) {
        // Don't clear state if we're in the middle of switching projects
        // (race condition: socket event fires between endTime and startTime)
        if (_isSwitchingProject) {
          _logger.info('No open entry but switching project in progress - skipping state clear');
          await _startSocketEventListener();
          return;
        }
        _logger.info('No open entry on server - clearing timer state (keeping completed durations)');
        state = null;
        _ref.read(selectedProjectProvider.notifier).state = null;
        await _startSocketEventListener();
        return;
      }

      // Process the open entry to set active session
      {
        _logger.info('Open entry found: $openEntry');

        // Check if entry is stale (from a previous day with no active session)
        // This handles orphaned entries where the backend closed the session
        // but failed to close the time entry (e.g. midnight boundary race condition)
        final startTimeStr = openEntry['startTime'] as String?;
        if (startTimeStr != null && todayEntries.isEmpty) {
          final parsedStart = DateTime.tryParse(startTimeStr)?.toLocal();
          if (parsedStart != null) {
            final now = DateTime.now();
            final isFromToday = parsedStart.year == now.year &&
                parsedStart.month == now.month &&
                parsedStart.day == now.day;
            if (!isFromToday) {
              _logger.warning(
                  'Stale open entry detected from ${parsedStart.toIso8601String()} '
                  '(${now.difference(parsedStart).inHours}h ago), ignoring');
              state = null;
              _ref.read(selectedProjectProvider.notifier).state = null;
              await _startSocketEventListener();
              return;
            }
          }
        }

        // Extract project info from API response (GraphQL format)
        String? projectId;
        String projectName = '';
        final projectField = openEntry['project'];
        if (projectField is Map) {
          projectId = projectField['id']?.toString();
          projectName = projectField['name']?.toString() ?? '';
          _logger.info('Extracted from project map: id=$projectId, name=$projectName');
        } else {
          projectId = openEntry['projectId']?.toString() ?? projectField?.toString();
          _logger.info('Extracted project as string: id=$projectId');
        }

        // Extract startTime - convert to local time (GraphQL uses startTime, not startedAt)
        DateTime? startedAt;
        final startTimeField = openEntry['startTime'] ?? openEntry['startedAt'];
        if (startTimeField is String) {
          final parsed = DateTime.tryParse(startTimeField);
          // Server returns UTC, convert to local
          startedAt = parsed?.toLocal();
        } else if (startTimeField is DateTime) {
          startedAt = startTimeField.toLocal();
        }

        // Extract entry ID (GraphQL uses 'id', old API uses '_id')
        final entryId = openEntry['id']?.toString() ?? openEntry['_id']?.toString() ?? '';

        _logger.info('Parsed open entry: projectId=$projectId, projectName=$projectName, startedAt=$startedAt (raw: $startTimeField)');
        _logger.info('Current time: ${DateTime.now()}, elapsed would be: ${startedAt != null ? DateTime.now().difference(startedAt).inSeconds : 0}s');

        if (projectId != null && startedAt != null) {
          // Get projects list
          final projects = _ref.read(projectsProvider).valueOrNull ?? [];
          _logger.info('Available projects count: ${projects.length}');

          // Find the matching project
          Project? matchedProject;
          for (final p in projects) {
            if (p.id == projectId) {
              matchedProject = p;
              break;
            }
          }

          // Use project name from API if available, otherwise from matched project
          if (projectName.isEmpty && matchedProject != null) {
            projectName = matchedProject.name;
          }
          if (projectName.isEmpty) {
            projectName = 'Unknown Project';
          }

          _logger.info('Final project name: $projectName, matched project: ${matchedProject?.name}');

          // If project not found in loaded list, create one from API data
          // This handles the race condition where not all project pages are loaded yet
          if (matchedProject == null) {
            final projectField = openEntry['project'];
            matchedProject = Project(
              id: projectId,
              name: projectName,
              createdAt: DateTime.now(),
              projectImage: projectField is Map
                  ? (projectField['imageThumbnailUrl'] as String? ??
                      projectField['imageUrl'] as String? ??
                      projectField['projectImage'] as String?)
                  : null,
            );
            _logger.info('Created fallback Project from API data: ${matchedProject.name}');

            // Inject the active project into the projects list so it appears in the UI
            final currentProjects = _ref.read(projectsProvider).valueOrNull ?? [];
            if (!currentProjects.any((p) => p.id == projectId)) {
              _ref.read(projectsProvider.notifier).injectProject(matchedProject);
              _logger.info('Injected active project into projects list');
            }
          }

          // Check entry status — only show as running if ACTIVE
          final entryStatus = openEntry['status']?.toString().toUpperCase() ?? 'ACTIVE';
          final isActive = entryStatus == 'ACTIVE';

          // Set the active session from server data
          final newSession = ActiveSession(
            id: entryId,
            projectId: projectId,
            projectName: projectName,
            startedAt: startedAt,
            isRunning: isActive,
          );

          _logger.info('Created ActiveSession: $newSession');
          _logger.info('Elapsed duration: ${newSession.elapsedDuration.inSeconds}s');

          state = newSession;

          // Update selected project provider with the matched project
          _ref.read(selectedProjectProvider.notifier).state = matchedProject;
          _logger.info('Set selectedProjectProvider to: ${matchedProject.name}');

          // Start UI refresh timer
          _startUiRefreshTimer();

          _logger.info('STATE AFTER SYNC: state=$state, elapsed=${state?.elapsedDuration.inSeconds}s');
        } else {
          _logger.warning('Could not parse open entry - missing projectId or startedAt');
          state = null;
          _ref.read(selectedProjectProvider.notifier).state = null;
        }
      }

      // Reload attendance to keep it in sync with timer state
      // Use loadAttendanceStatus() which returns periods data for live time display
      await _ref.read(attendanceProvider.notifier).loadAttendanceStatus();

      // Start listening to socket events for real-time updates
      await _startSocketEventListener();
    } catch (e, stackTrace) {
      _logger.error('Failed to sync open entry', e, stackTrace);
    }
  }

  /// Start listening to socket events for real-time updates
  Future<void> _startSocketEventListener() async {
    _socketSubscription?.cancel();
    _logger.info('Starting socket event listener...');

    // Ensure socket is connected before listening
    if (!_socketService.isConnected) {
      _logger.info('Socket not connected, attempting to connect...');
      try {
        await _socketService.connect();
        _logger.info('Socket connected successfully');
      } catch (e) {
        _logger.error('Failed to connect socket', e, null);
        // Continue anyway - socket may connect later via reconnection
      }
    }

    _socketSubscription = _socketService.eventStream.listen(
      (event) {
        _logger.info('Socket event received: ${event.type} for ${event.projectName}');
        _handleSocketEvent(event);
      },
      onError: (error) {
        _logger.error('Socket event stream error', error, null);
      },
    );

    // Listen to attendance checkout events to stop timer
    _attendanceSubscription?.cancel();
    _attendanceSubscription = _socketService.attendanceEventStream.listen(
      (event) {
        if (event.type == AttendanceEventType.checkedOut && !event.isActive) {
          _logger.info('Attendance checkout detected, stopping timer if running');
          _handleCheckoutEvent();
        }
      },
      onError: (error) {
        _logger.error('Attendance event stream error', error, null);
      },
    );
  }

  /// Handle checkout event - stop timer without calling API (server already stopped it)
  Future<void> _handleCheckoutEvent() async {
    if (state != null) {
      _logger.info('Stopping timer due to checkout event');
      await saveCurrentTaskDuration();
      _stopUiRefreshTimer();
      state = null;
      _ref.read(activeTaskIdProvider.notifier).state = null;
      _ref.read(selectedProjectProvider.notifier).state = null;
      _logger.info('Timer stopped due to checkout');
    }
  }

  /// Handle incoming socket events
  /// Instead of manually manipulating state, we re-sync from API
  /// This ensures consistent behavior between app startup and socket events
  Future<void> _handleSocketEvent(TimeEntryEvent event) async {
    try {
      _logger.info('Socket event received: ${event.type} for project: ${event.projectName}');

      // Re-sync state from API - this handles all the logic for:
      // - Checking if there's an open entry
      // - Calculating all durations for today
      // - Setting the active session state
      // - Clearing everything if no open entry
      await checkAndSyncOpenEntry();

      // Also sync tasks from API for today
      await _ref.read(tasksProvider.notifier).syncTasksFromApi(DateTime.now());

      // Also refresh attendance status to keep check-in/check-out times updated
      await _ref.read(attendanceProvider.notifier).loadAttendanceStatus();

      _logger.info('State re-synced after socket event');
    } catch (e, stackTrace) {
      _logger.error('Failed to handle socket event', e, stackTrace);
    }
  }

  void stopSocketEventListener() {
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _attendanceSubscription?.cancel();
    _attendanceSubscription = null;
  }

  // Start timer for project (calls API)
  Future<void> startTimer(Project project) async {
    try {
      // Validate that user is checked in from mobile app
      final attendance = _ref.read(currentAttendanceProvider);
      final isCheckedIn = attendance?.isCurrentlyCheckedIn ?? false;
      if (!isCheckedIn) {
        throw Exception('Please check in from mobile app first');
      }

      // If already running for another project, end it first
      if (state != null && state!.isRunning && state!.projectId != project.id) {
        await _api.endActiveTimeEntry(state!.id);
      }

      // Start time on server (set project on active time entry)
      final startSuccess = await _api.startTimeOnProject(project.id);
      if (!startSuccess) {
        throw Exception('Failed to start time on server');
      }

      // Set local state with current time (will be corrected by socket event)
      state = ActiveSession(
        id: 'pending',
        projectId: project.id,
        projectName: project.name,
        startedAt: DateTime.now(),
        isRunning: true,
      );

      _ref.read(activeTaskIdProvider.notifier).state = null;
      _ref.read(selectedProjectProvider.notifier).state = project;
      _startUiRefreshTimer();

      _logger.info('Timer started for: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to start timer', e, stackTrace);
      rethrow;
    }
  }

  // Save current task's elapsed time before switching
  Future<void> saveCurrentTaskDuration() async {
    final activeTaskId = _ref.read(activeTaskIdProvider);
    if (activeTaskId != null && _taskStartTime != null) {
      final elapsed = DateTime.now().difference(_taskStartTime!);
      if (elapsed.inSeconds > 0) {
        await _ref.read(tasksProvider.notifier).addDuration(activeTaskId, elapsed);
      }
      _taskStartTime = null;
    }
  }

  // Start timer with specific task
  Future<void> startTimerWithTask(Project project, String taskId) async {
    try {
      // If already running for this project, just switch task
      if (state != null && state!.projectId == project.id && state!.isRunning) {
        await saveCurrentTaskDuration();
        _ref.read(activeTaskIdProvider.notifier).state = taskId;
        _taskStartTime = DateTime.now();
        _logger.info('Switched to task: $taskId');
        return;
      }

      // Validate that user is checked in from mobile app
      final attendance = _ref.read(currentAttendanceProvider);
      final isCheckedIn = attendance?.isCurrentlyCheckedIn ?? false;
      if (!isCheckedIn) {
        throw Exception('Please check in from mobile app first');
      }

      await saveCurrentTaskDuration();

      // Start or switch project
      if (state != null && state!.isRunning) {
        await switchProject(project);
      } else {
        final startSuccess = await _api.startTimeOnProject(project.id);
        if (!startSuccess) {
          throw Exception('Failed to start time on server');
        }

        state = ActiveSession(
          id: 'pending',
          projectId: project.id,
          projectName: project.name,
          startedAt: DateTime.now(),
          isRunning: true,
        );
        _ref.read(selectedProjectProvider.notifier).state = project;
        _startUiRefreshTimer();
      }

      _ref.read(activeTaskIdProvider.notifier).state = taskId;
      _taskStartTime = DateTime.now();
      _logger.info('Timer started with task: $taskId');
    } catch (e, stackTrace) {
      _logger.error('Failed to start timer with task', e, stackTrace);
      rethrow;
    }
  }

  // Stop timer (calls API)
  Future<void> stopTimer() async {
    try {
      await saveCurrentTaskDuration();

      if (state != null && state!.projectId.isNotEmpty) {
        final endSuccess = await _api.endActiveTimeEntry(state!.id);
        if (!endSuccess) {
          throw Exception('Failed to end time on server');
        }
      }

      _stopUiRefreshTimer();
      state = null;
      _ref.read(activeTaskIdProvider.notifier).state = null;
      _ref.read(selectedProjectProvider.notifier).state = null;

      await _ref.read(projectsProvider.notifier).refreshProjects();

      _logger.info('Timer stopped');
    } catch (e, stackTrace) {
      _logger.error('Failed to stop timer', e, stackTrace);
      rethrow;
    }
  }

  // Pause timer (calls API)
  Future<void> pauseTimer() async {
    if (state == null || !state!.isRunning) return;

    try {
      await saveCurrentTaskDuration();

      final result = await _api.pauseTimeEntry(state!.id);
      if (result == null) {
        throw Exception('Failed to pause time entry on server');
      }

      _stopUiRefreshTimer();
      state = state!.copyWith(isRunning: false);

      _logger.info('Timer paused for: ${state!.projectName}');
    } catch (e, stackTrace) {
      _logger.error('Failed to pause timer', e, stackTrace);
      rethrow;
    }
  }

  // Resume timer (calls API - backend creates a new entry)
  Future<void> resumeTimer() async {
    if (state == null || state!.isRunning) return;

    try {
      final result = await _api.resumeTimeEntry(state!.id);
      if (result == null) {
        throw Exception('Failed to resume time entry on server');
      }

      // Backend creates a new entry on resume, so re-sync to get the new ID
      await checkAndSyncOpenEntry();

      _logger.info('Timer resumed for: ${state?.projectName}');
    } catch (e, stackTrace) {
      _logger.error('Failed to resume timer', e, stackTrace);
      rethrow;
    }
  }

  // Switch project
  Future<void> switchProject(Project project) async {
    // Set flag to prevent race condition with socket events
    _isSwitchingProject = true;
    try {
      // Validate that user is checked in from mobile app
      final attendance = _ref.read(currentAttendanceProvider);
      final isCheckedIn = attendance?.isCurrentlyCheckedIn ?? false;
      if (!isCheckedIn) {
        _isSwitchingProject = false;
        throw Exception('Please check in from mobile app first');
      }

      await saveCurrentTaskDuration();

      // End current project
      if (state != null && state!.projectId.isNotEmpty) {
        final endSuccess = await _api.endActiveTimeEntry(state!.id);
        if (!endSuccess) {
          _isSwitchingProject = false;
          throw Exception('Failed to end previous time entry. Please check your connection and try again.');
        }
      }

      // Start new project (set project on active time entry)
      final startSuccess = await _api.startTimeOnProject(project.id);
      if (!startSuccess) {
        _isSwitchingProject = false;
        throw Exception('Failed to start time on server');
      }

      state = ActiveSession(
        id: 'pending',
        projectId: project.id,
        projectName: project.name,
        startedAt: DateTime.now(),
        isRunning: true,
      );

      _ref.read(activeTaskIdProvider.notifier).state = null;
      _ref.read(selectedProjectProvider.notifier).state = project;

      // Refresh today's time entries from API to get accurate completed durations
      final todayEntries = await _api.getTodayTimeEntries();
      final Map<String, Duration> completedDurations = {};
      for (final entry in todayEntries) {
        if (entry['endTime'] != null) {
          final projectField = entry['project'];
          String? projectId;
          if (projectField is Map) {
            projectId = projectField['id']?.toString();
          } else {
            projectId = entry['projectId']?.toString() ?? projectField?.toString();
          }
          if (projectId != null) {
            // Try to get duration from the entry, or calculate it from timestamps
            Duration duration = Duration.zero;

            // First try to get duration from the API field (handle both int and double)
            final durationField = entry['duration'];
            if (durationField != null && durationField is num && durationField > 0) {
              duration = Duration(seconds: durationField.toInt());
            }

            // If no duration field, calculate from timestamps
            if (duration == Duration.zero) {
              final startTimeField = entry['startTime'];
              final endTimeField = entry['endTime'];
              DateTime? startTime;
              DateTime? endTime;

              if (startTimeField is String) {
                startTime = DateTime.tryParse(startTimeField)?.toLocal();
              } else if (startTimeField is DateTime) {
                startTime = startTimeField.toLocal();
              }

              if (endTimeField is String) {
                endTime = DateTime.tryParse(endTimeField)?.toLocal();
              } else if (endTimeField is DateTime) {
                endTime = endTimeField.toLocal();
              }

              if (startTime != null && endTime != null) {
                duration = endTime.difference(startTime);
                if (duration.isNegative) duration = Duration.zero;
              }
            }

            if (duration.inSeconds > 0) {
              completedDurations[projectId] = (completedDurations[projectId] ?? Duration.zero) + duration;
            }
          }
        }
      }
      _ref.read(completedProjectDurationsProvider.notifier).state = completedDurations;
      _logger.info('Refreshed completed durations after switch: ${completedDurations.length} projects');

      await _ref.read(projectsProvider.notifier).refreshProjects();

      _logger.info('Switched to project: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to switch project', e, stackTrace);
      rethrow;
    } finally {
      // Always clear the flag when done
      _isSwitchingProject = false;
    }
  }

  bool get isRunning => state != null && state!.isRunning;

  Duration get currentDuration {
    if (state == null) return Duration.zero;
    return state!.elapsedDuration;
  }

  @override
  void dispose() {
    _stopUiRefreshTimer();
    _socketSubscription?.cancel();
    _attendanceSubscription?.cancel();
    super.dispose();
  }
}

// Timer running state provider
final isTimerRunningProvider = Provider<bool>((ref) {
  final timer = ref.watch(currentTimerProvider);
  return timer != null && timer.isRunning;
});

// Timer paused state provider
final isTimerPausedProvider = Provider<bool>((ref) {
  final timer = ref.watch(currentTimerProvider);
  return timer != null && !timer.isRunning;
});

// Current timer duration provider
final currentTimerDurationProvider = Provider<Duration>((ref) {
  final timer = ref.watch(currentTimerProvider);
  if (timer == null) return Duration.zero;
  return timer.elapsedDuration;
});

// Current task duration provider
final currentTaskDurationProvider = Provider<Duration>((ref) {
  final timer = ref.watch(currentTimerProvider);
  if (timer == null || !timer.isRunning) return Duration.zero;

  final notifier = ref.read(currentTimerProvider.notifier);
  final taskStartTime = notifier.taskStartTime;
  if (taskStartTime == null) return Duration.zero;

  return DateTime.now().difference(taskStartTime);
});

// Active task ID provider
final activeTaskIdProvider = StateProvider<String?>((ref) => null);

// Legacy providers - kept for backward compatibility but return empty data
// TODO: Remove these once all screens are migrated to use API data
final allTimeEntriesProvider = Provider<List<dynamic>>((ref) => []);
final projectTimeEntriesProvider = Provider.family<List<dynamic>, String>((ref, projectId) => []);
