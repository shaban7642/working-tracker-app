import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/attendance_event.dart';
import '../models/task_event.dart';
import '../models/time_entry_event.dart';
import '../services/subscription_service.dart';
import '../services/graphql_auth_service.dart';
import '../services/logger_service.dart';
import 'pending_tasks_provider.dart';
import 'project_tasks_provider.dart';

// Subscription service provider (singleton) - replaces socketServiceProvider
final socketServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService();
});

// Socket connection state provider
final socketConnectedProvider = StateProvider<bool>((ref) {
  return SubscriptionService().isConnected;
});

// Stream provider for time entry events
final timeEntryEventStreamProvider = StreamProvider<TimeEntryEvent>((ref) {
  final service = ref.watch(socketServiceProvider);
  return service.eventStream;
});

// Stream provider for attendance events
final attendanceEventStreamProvider = StreamProvider<AttendanceEvent>((ref) {
  final service = ref.watch(socketServiceProvider);
  return service.attendanceEventStream;
});

// Stream provider for task events
final taskEventStreamProvider = StreamProvider<TaskEvent>((ref) {
  final service = ref.watch(socketServiceProvider);
  return service.taskEventStream;
});

// Provider to initialize and manage subscription connection
final socketInitializerProvider = Provider<SocketInitializer>((ref) {
  return SocketInitializer(ref);
});

class SocketInitializer {
  final Ref _ref;
  final _logger = LoggerService();
  StreamSubscription<TimeEntryEvent>? _eventSubscription;
  TokenRefreshHandler? _tokenRefreshHandler;
  TaskEventHandler? _taskEventHandler;

  SocketInitializer(this._ref);

  /// Initialize subscriptions and start listening for events
  Future<void> initialize() async {
    final service = _ref.read(socketServiceProvider);

    try {
      await service.connect();
      _ref.read(socketConnectedProvider.notifier).state = true;

      // Initialize token refresh handler
      _tokenRefreshHandler = _ref.read(tokenRefreshHandlerProvider);
      _tokenRefreshHandler?.initialize();

      // Initialize task event handler
      _taskEventHandler = _ref.read(taskEventHandlerProvider);
      _taskEventHandler?.initialize();

      // Subscribe to events and update connection state
      _eventSubscription = service.eventStream.listen(
        (event) {
          _logger.info('Subscription event received: $event');
        },
        onError: (error) {
          _logger.error('Subscription event stream error', error, null);
        },
      );

      _logger.info('Socket initializer ready (using GraphQL subscriptions)');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize subscriptions', e, stackTrace);
      _ref.read(socketConnectedProvider.notifier).state = false;
    }
  }

  /// Disconnect and cleanup
  void dispose() {
    _eventSubscription?.cancel();
    _tokenRefreshHandler?.dispose();
    _taskEventHandler?.dispose();
    _ref.read(socketServiceProvider).disconnect();
    _ref.read(socketConnectedProvider.notifier).state = false;
    _logger.info('Socket initializer disposed');
  }
}

// Token refresh handler provider
final tokenRefreshHandlerProvider = Provider<TokenRefreshHandler>((ref) {
  return TokenRefreshHandler(ref);
});

/// Handles token refresh when subscriptions receive token errors
class TokenRefreshHandler {
  final Ref _ref;
  final _logger = LoggerService();
  final _authService = GraphqlAuthService();

  StreamSubscription<String>? _tokenErrorSubscription;

  TokenRefreshHandler(this._ref);

  /// Start listening for token errors
  void initialize() {
    final service = _ref.read(socketServiceProvider);

    _tokenErrorSubscription = service.tokenErrorStream.listen(
      (error) async {
        _logger.warning('Token error received from subscription: $error');
        await _handleTokenError();
      },
    );

    _logger.info('Token refresh handler initialized');
  }

  /// Handle token error by attempting refresh
  Future<void> _handleTokenError() async {
    _logger.info('Attempting token refresh due to subscription error...');

    final success = await _authService.refreshAccessToken();

    if (success) {
      await _reconnectSubscriptions();
    } else {
      _logger.warning('Token refresh failed, forcing logout');
      await _authService.forceLogout();
    }
  }

  /// Reconnect subscriptions with new token
  Future<void> _reconnectSubscriptions() async {
    try {
      final service = _ref.read(socketServiceProvider);
      await service.reconnect();
      _ref.read(socketConnectedProvider.notifier).state = true;
      _logger.info('Subscriptions reconnected with new token');
    } catch (e, stackTrace) {
      _logger.error('Failed to reconnect subscriptions', e, stackTrace);
    }
  }

  /// Dispose resources
  void dispose() {
    _tokenErrorSubscription?.cancel();
    _logger.info('Token refresh handler disposed');
  }
}

// Task event handler provider
final taskEventHandlerProvider = Provider<TaskEventHandler>((ref) {
  return TaskEventHandler(ref);
});

/// Handles real-time task events and updates relevant providers
class TaskEventHandler {
  final Ref _ref;
  final _logger = LoggerService();
  StreamSubscription<TaskEvent>? _taskEventSubscription;

  TaskEventHandler(this._ref);

  /// Start listening for task events
  void initialize() {
    final service = _ref.read(socketServiceProvider);

    _taskEventSubscription = service.taskEventStream.listen(
      (event) {
        _logger.info('Task event received: ${event.type} for task ${event.id}');
        _handleTaskEvent(event);
      },
      onError: (error) {
        _logger.error('Task event stream error', error, null);
      },
    );

    _logger.info('Task event handler initialized');
  }

  /// Handle incoming task events
  void _handleTaskEvent(TaskEvent event) {
    final localDate = event.effectiveDate.toLocal();
    final dateStr = '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';

    final key = ProjectTasksKey(
      projectId: event.projectId,
      date: dateStr,
    );

    _logger.info('Task event key: projectId=${event.projectId}, date=$dateStr');

    switch (event.type) {
      case TaskEventType.created:
        _handleTaskCreated(event, key);
        break;
      case TaskEventType.updated:
        _handleTaskUpdated(event, key);
        break;
      case TaskEventType.deleted:
        _handleTaskDeleted(event, key);
        break;
    }
  }

  void _handleTaskCreated(TaskEvent event, ProjectTasksKey key) {
    _logger.info('Handling task:created for task: ${event.id}, project: ${event.projectId}');

    final pendingState = _ref.read(pendingTasksProvider);
    if (pendingState is PendingTasksLoaded) {
      final pendingEntry = pendingState.entries
          .where((e) => e.projectId == event.projectId)
          .firstOrNull;

      if (pendingEntry != null) {
        final pendingKey = ProjectTasksKey(
          projectId: event.projectId,
          date: pendingEntry.dateForApi,
        );

        final notifier = _ref.read(projectTasksProvider(pendingKey).notifier);
        final task = event.toReportTask().copyWith(reportDate: pendingEntry.date);

        final state = _ref.read(projectTasksProvider(pendingKey));
        if (state is ProjectTasksLoaded) {
          if (!state.tasks.any((t) => t.id == event.id)) {
            notifier.addTask(task);
            _logger.info('Added task ${event.id} to $pendingKey (from pending entry)');
          }
        } else {
          // Provider not loaded yet — add the task directly
          notifier.addTask(task);
          _logger.info('Added task ${event.id} to $pendingKey (provider was not loaded)');
        }

        // Mark the pending entry as completed since it now has a task
        _ref.read(pendingTasksProvider.notifier).markEntryCompleted(pendingEntry.id);
        _logger.info('Marked pending entry ${pendingEntry.id} as completed via subscription');
        return;
      }
    }

    // Fallback to event date
    final notifier = _ref.read(projectTasksProvider(key).notifier);
    final task = event.toReportTask();
    notifier.addTask(task);
    _logger.info('Added task ${event.id} to $key (fallback)');
  }

  void _handleTaskUpdated(TaskEvent event, ProjectTasksKey key) {
    // Try the event's own date key first
    final state = _ref.read(projectTasksProvider(key));
    if (state is ProjectTasksLoaded) {
      final hasTask = state.tasks.any((t) => t.id == event.id);
      if (hasTask) {
        final notifier = _ref.read(projectTasksProvider(key).notifier);
        notifier.updateTask(event.toReportTask());
        _logger.info('Updated task ${event.id} in $key');
        return;
      }
    }

    // Check pending entries for a matching project
    final pendingState = _ref.read(pendingTasksProvider);
    if (pendingState is PendingTasksLoaded) {
      for (final entry in pendingState.entries.where((e) => e.projectId == event.projectId)) {
        final pendingKey = ProjectTasksKey(projectId: event.projectId, date: entry.dateForApi);
        final pState = _ref.read(projectTasksProvider(pendingKey));
        if (pState is ProjectTasksLoaded && pState.tasks.any((t) => t.id == event.id)) {
          _ref.read(projectTasksProvider(pendingKey).notifier)
              .updateTask(event.toReportTask().copyWith(reportDate: entry.date));
          _logger.info('Updated task ${event.id} in $pendingKey');
          return;
        }
      }
    }

    // Provider not loaded — force refresh so updated task is fetched
    _ref.read(projectTasksProvider(key).notifier).refresh();
    _logger.info('Refreshing $key to fetch updated task ${event.id}');
  }

  void _handleTaskDeleted(TaskEvent event, ProjectTasksKey key) {
    _logger.info('Handling task:deleted for task: ${event.id}');

    // Try the event's own date key first
    final state = _ref.read(projectTasksProvider(key));
    if (state is ProjectTasksLoaded && state.tasks.any((t) => t.id == event.id)) {
      _ref.read(projectTasksProvider(key).notifier).removeTask(event.id);
      _logger.info('Removed task ${event.id} from $key');
      // Check if this was the last task — unmark the pending entry
      _checkAndUnmarkPendingEntry(event.projectId, key);
      return;
    }

    // Check pending entries for a matching project
    final pendingState = _ref.read(pendingTasksProvider);
    if (pendingState is PendingTasksLoaded) {
      for (final entry in pendingState.entries.where((e) => e.projectId == event.projectId)) {
        final pendingKey = ProjectTasksKey(projectId: event.projectId, date: entry.dateForApi);
        final pState = _ref.read(projectTasksProvider(pendingKey));
        if (pState is ProjectTasksLoaded && pState.tasks.any((t) => t.id == event.id)) {
          _ref.read(projectTasksProvider(pendingKey).notifier).removeTask(event.id);
          _logger.info('Removed task ${event.id} from $pendingKey');
          // Check if this was the last task — unmark the pending entry
          _checkAndUnmarkPendingEntry(event.projectId, pendingKey);
          return;
        }
      }
    }
  }

  /// After removing a task, check if the entry has no tasks left and unmark it
  void _checkAndUnmarkPendingEntry(String projectId, ProjectTasksKey key) {
    final updatedState = _ref.read(projectTasksProvider(key));
    if (updatedState is ProjectTasksLoaded && updatedState.tasks.isEmpty) {
      final pendingState = _ref.read(pendingTasksProvider);
      if (pendingState is PendingTasksLoaded) {
        final pendingEntry = pendingState.entries
            .where((e) => e.projectId == projectId)
            .firstOrNull;
        if (pendingEntry != null) {
          _ref.read(pendingTasksProvider.notifier).unmarkEntryCompleted(pendingEntry.id);
          _logger.info('Unmarked pending entry ${pendingEntry.id} — no tasks remaining');
        }
      }
    }
  }

  /// Dispose resources
  void dispose() {
    _taskEventSubscription?.cancel();
    _logger.info('Task event handler disposed');
  }
}
