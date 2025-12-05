import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/time_entry.dart';
import '../models/project.dart';
import '../services/timer_service.dart';
import '../services/logger_service.dart';
import 'auth_provider.dart';
import 'project_provider.dart';
import 'task_provider.dart';

// Timer service provider
final timerServiceProvider = Provider<TimerService>((ref) {
  return TimerService();
});

// Current timer state provider
final currentTimerProvider = StateNotifierProvider<CurrentTimerNotifier, TimeEntry?>((ref) {
  return CurrentTimerNotifier(ref);
});

class CurrentTimerNotifier extends StateNotifier<TimeEntry?> {
  final Ref _ref;
  late final TimerService _timerService;
  late final LoggerService _logger;
  StreamSubscription<Duration>? _timerSubscription;
  DateTime? _taskStartTime; // Track when current task started

  // Expose task start time for calculating task-specific duration
  DateTime? get taskStartTime => _taskStartTime;

  CurrentTimerNotifier(this._ref) : super(null) {
    _timerService = _ref.read(timerServiceProvider);
    _logger = _ref.read(loggerServiceProvider);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _timerService.initialize();
      state = _timerService.currentEntry;

      // Listen to timer stream
      _timerSubscription = _timerService.timerStream.listen((_) {
        // Update state to trigger UI rebuild
        if (_timerService.currentEntry != null) {
          final entry = _timerService.currentEntry!;
          // IMPORTANT: Create a new object to trigger Riverpod state change
          // The same object reference won't trigger rebuilds even if actualDuration changes
          state = entry.copyWith();

          // Refresh project times to show real-time updates in project list
          _ref.read(projectsProvider.notifier).refreshProjectTimes();
        }
      });

      _logger.info('Timer provider initialized');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize timer provider', e, stackTrace);
    }
  }

  // Start timer for project
  Future<void> startTimer(Project project) async {
    try {
      final entry = await _timerService.startTimer(project);
      state = entry;
      _ref.read(activeTaskIdProvider.notifier).state = null; // Clear active task when starting project directly

      // Update selected project
      _ref.read(selectedProjectProvider.notifier).state = project;

      _logger.info('Timer started for: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to start timer', e, stackTrace);
      rethrow;
    }
  }

  // Save current task's elapsed time before switching (public for submission form)
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

  // Start timer for project with specific task active
  Future<void> startTimerWithTask(Project project, String taskId) async {
    try {
      // If already running for this project, just switch task
      if (state != null && state!.projectId == project.id && state!.isRunning) {
        // Save current task duration before switching
        await saveCurrentTaskDuration();

        _ref.read(activeTaskIdProvider.notifier).state = taskId;
        _taskStartTime = DateTime.now(); // Start tracking new task
        _logger.info('Switched to task: $taskId in project: ${project.name}');
        return;
      }

      // Save current task duration before switching projects
      await saveCurrentTaskDuration();

      // Otherwise start/switch the project timer
      if (state != null && state!.isRunning) {
        await switchProject(project);
      } else {
        final entry = await _timerService.startTimer(project);
        state = entry;
        _ref.read(selectedProjectProvider.notifier).state = project;
      }

      _ref.read(activeTaskIdProvider.notifier).state = taskId;
      _taskStartTime = DateTime.now(); // Start tracking new task
      _logger.info('Timer started for task: $taskId in project: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to start timer with task', e, stackTrace);
      rethrow;
    }
  }

  // Stop timer
  Future<void> stopTimer() async {
    try {
      // Save current task duration before stopping
      await saveCurrentTaskDuration();

      await _timerService.stopTimer();
      state = null;
      _ref.read(activeTaskIdProvider.notifier).state = null; // Clear active task when stopping

      // Refresh projects to update total time
      await _ref.read(projectsProvider.notifier).refreshProjects();

      _logger.info('Timer stopped');
    } catch (e, stackTrace) {
      _logger.error('Failed to stop timer', e, stackTrace);
      rethrow;
    }
  }

  // Switch project
  Future<void> switchProject(Project project) async {
    try {
      // Save current task duration before switching projects
      await saveCurrentTaskDuration();

      final entry = await _timerService.switchProject(project);
      state = entry;
      _ref.read(activeTaskIdProvider.notifier).state = null; // Clear active task when switching projects

      // Update selected project
      _ref.read(selectedProjectProvider.notifier).state = project;

      // Refresh projects to update total time
      await _ref.read(projectsProvider.notifier).refreshProjects();

      _logger.info('Switched to project: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to switch project', e, stackTrace);
      rethrow;
    }
  }

  // Check if timer is running
  bool get isRunning => state != null && state!.isRunning;

  // Get current duration
  Duration get currentDuration {
    if (state == null) return Duration.zero;
    return state!.actualDuration;
  }

  @override
  void dispose() {
    _timerSubscription?.cancel();
    super.dispose();
  }
}

// Timer running state provider
final isTimerRunningProvider = Provider<bool>((ref) {
  final timer = ref.watch(currentTimerProvider);
  return timer != null && timer.isRunning;
});

// Current timer duration provider (project-level)
final currentTimerDurationProvider = Provider<Duration>((ref) {
  final timer = ref.watch(currentTimerProvider);
  if (timer == null) return Duration.zero;
  return timer.actualDuration;
});

// Current task duration provider (task-specific elapsed time)
final currentTaskDurationProvider = Provider<Duration>((ref) {
  final timer = ref.watch(currentTimerProvider);
  if (timer == null || !timer.isRunning) return Duration.zero;

  final notifier = ref.read(currentTimerProvider.notifier);
  final taskStartTime = notifier.taskStartTime;
  if (taskStartTime == null) return Duration.zero;

  return DateTime.now().difference(taskStartTime);
});

// All time entries provider
final allTimeEntriesProvider = Provider<List<TimeEntry>>((ref) {
  final timerService = ref.watch(timerServiceProvider);
  return timerService.getAllTimeEntries();
});

// Project time entries provider (for specific project)
final projectTimeEntriesProvider = Provider.family<List<TimeEntry>, String>((ref, projectId) {
  final timerService = ref.watch(timerServiceProvider);
  return timerService.getProjectTimeEntries(projectId);
});

// Active task ID provider - separate state for proper reactivity
final activeTaskIdProvider = StateProvider<String?>((ref) => null);
