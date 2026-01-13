import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/report_task.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import 'auth_provider.dart';

// ============================================================================
// PROJECT TASKS KEY (for family provider with projectId + date)
// ============================================================================

/// Key for project tasks provider - combines projectId and date
class ProjectTasksKey {
  final String projectId;
  final String date; // Format: YYYY-MM-DD

  const ProjectTasksKey({required this.projectId, required this.date});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProjectTasksKey &&
        other.projectId == projectId &&
        other.date == date;
  }

  @override
  int get hashCode => projectId.hashCode ^ date.hashCode;

  @override
  String toString() => 'ProjectTasksKey(projectId: $projectId, date: $date)';
}

// ============================================================================
// PROJECT TASKS STATE
// ============================================================================

/// Base class for project tasks states
sealed class ProjectTasksState {
  const ProjectTasksState();
}

/// Initial state before tasks are loaded
class ProjectTasksInitial extends ProjectTasksState {
  const ProjectTasksInitial();
}

/// Loading state while fetching tasks
class ProjectTasksLoading extends ProjectTasksState {
  const ProjectTasksLoading();
}

/// Successfully loaded tasks for a project
class ProjectTasksLoaded extends ProjectTasksState {
  final List<ReportTask> tasks;

  const ProjectTasksLoaded(this.tasks);

  bool get hasTasks => tasks.isNotEmpty;
  int get taskCount => tasks.length;
}

/// Error state when fetching tasks fails
class ProjectTasksError extends ProjectTasksState {
  final String message;

  const ProjectTasksError(this.message);
}

// ============================================================================
// PROJECT TASKS NOTIFIER
// ============================================================================

class ProjectTasksNotifier extends StateNotifier<ProjectTasksState> {
  final Ref _ref;
  final ProjectTasksKey key;
  final _api = ApiService();
  late final LoggerService _logger;

  ProjectTasksNotifier(this._ref, this.key)
      : super(const ProjectTasksInitial()) {
    _logger = _ref.read(loggerServiceProvider);
  }

  bool _isLoading = false;

  /// Load tasks for this project and date
  Future<void> loadTasks() async {
    // Prevent multiple simultaneous loads
    if (_isLoading) {
      _logger.info('Already loading tasks for $key, skipping');
      return;
    }

    // Don't reload if already loaded
    if (state is ProjectTasksLoaded) {
      _logger.info('Tasks already loaded for $key, skipping');
      return;
    }

    _isLoading = true;
    _logger.info('Loading tasks for $key');
    state = const ProjectTasksLoading();

    try {
      final rawTasks = await _api.getProjectTasks(key.projectId, date: key.date);
      final tasks = rawTasks.map((e) => ReportTask.fromJson(e)).toList();

      _logger.info('Loaded ${tasks.length} tasks for $key');
      state = ProjectTasksLoaded(tasks);
    } catch (e, stackTrace) {
      _logger.error('Failed to load tasks for $key', e, stackTrace);
      state = ProjectTasksError(e.toString());
    } finally {
      _isLoading = false;
    }
  }

  /// Add a task to the local state (after API success)
  void addTask(ReportTask task) {
    final currentState = state;
    if (currentState is ProjectTasksLoaded) {
      state = ProjectTasksLoaded([...currentState.tasks, task]);
    } else {
      state = ProjectTasksLoaded([task]);
    }
  }

  /// Remove a task from local state
  void removeTask(String taskId) {
    final currentState = state;
    if (currentState is ProjectTasksLoaded) {
      state = ProjectTasksLoaded(
        currentState.tasks.where((t) => t.id != taskId).toList(),
      );
    }
  }

  /// Update a task in local state
  void updateTask(ReportTask updatedTask) {
    final currentState = state;
    if (currentState is ProjectTasksLoaded) {
      state = ProjectTasksLoaded(
        currentState.tasks.map((t) => t.id == updatedTask.id ? updatedTask : t).toList(),
      );
    }
  }

  /// Refresh tasks from API (forces reload even if already loaded)
  Future<void> refresh() async {
    // Prevent multiple simultaneous loads
    if (_isLoading) {
      _logger.info('Already loading tasks for $key, skipping refresh');
      return;
    }

    _isLoading = true;
    _logger.info('Refreshing tasks for $key');
    state = const ProjectTasksLoading();

    try {
      final rawTasks = await _api.getProjectTasks(key.projectId, date: key.date);
      final tasks = rawTasks.map((e) => ReportTask.fromJson(e)).toList();

      _logger.info('Refreshed ${tasks.length} tasks for $key');
      state = ProjectTasksLoaded(tasks);
    } catch (e, stackTrace) {
      _logger.error('Failed to refresh tasks for $key', e, stackTrace);
      state = ProjectTasksError(e.toString());
    } finally {
      _isLoading = false;
    }
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

/// Family provider for project tasks - each project+date combo gets its own notifier
final projectTasksProvider = StateNotifierProvider.family<ProjectTasksNotifier,
    ProjectTasksState, ProjectTasksKey>((ref, key) {
  return ProjectTasksNotifier(ref, key);
});

/// Helper provider to check if a project has tasks
final projectHasTasksProvider = Provider.family<bool, ProjectTasksKey>((ref, key) {
  final state = ref.watch(projectTasksProvider(key));
  if (state is ProjectTasksLoaded) {
    return state.hasTasks;
  }
  return false;
});

/// Helper provider to get task count for a project
final projectTaskCountProvider = Provider.family<int, ProjectTasksKey>((ref, key) {
  final state = ref.watch(projectTasksProvider(key));
  if (state is ProjectTasksLoaded) {
    return state.taskCount;
  }
  return 0;
});

/// Helper provider to get tasks list for a project
final projectTasksListProvider =
    Provider.family<List<ReportTask>, ProjectTasksKey>((ref, key) {
  final state = ref.watch(projectTasksProvider(key));
  if (state is ProjectTasksLoaded) {
    return state.tasks;
  }
  return [];
});

/// Helper provider to check if tasks are loading for a project
final isProjectTasksLoadingProvider =
    Provider.family<bool, ProjectTasksKey>((ref, key) {
  final state = ref.watch(projectTasksProvider(key));
  return state is ProjectTasksLoading;
});
