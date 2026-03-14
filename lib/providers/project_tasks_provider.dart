import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/report_task.dart';
import '../services/graphql_api_service.dart';
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
// SHARED DAILY REPORT CACHE
// ============================================================================

/// Cached daily report data - loaded ONCE per date, shared across all projects.
/// This prevents the N+1 problem where each project card triggers a separate API call.
/// Supports multiple dates concurrently (dashboard uses today, pending tasks use past dates).
class DailyReportCache {
  static final DailyReportCache _instance = DailyReportCache._internal();
  factory DailyReportCache() => _instance;
  DailyReportCache._internal();

  final _api = GraphqlApiService();
  final _logger = LoggerService();

  /// Cache: date -> { projectId -> tasks }
  final Map<String, Map<String, List<ReportTask>>> _cache = {};

  /// In-flight loading futures per date (prevents duplicate requests)
  final Map<String, Future<Map<String, List<ReportTask>>>> _loadingFutures = {};

  /// Load the daily report for a date (only fetches once per date)
  Future<Map<String, List<ReportTask>>> getTasksByProject(String date) async {
    // Return cached data if available
    if (_cache.containsKey(date)) {
      return _cache[date]!;
    }

    // If already loading this date, wait for the same future
    if (_loadingFutures.containsKey(date)) {
      return _loadingFutures[date]!;
    }

    // Start loading and store the future so concurrent requests share it
    final future = _loadReport(date);
    _loadingFutures[date] = future;

    try {
      final result = await future;
      return result;
    } finally {
      _loadingFutures.remove(date);
    }
  }

  Future<Map<String, List<ReportTask>>> _loadReport(String date) async {
    try {
      _logger.info('Loading daily report for date: $date (shared cache)');
      final dateObj = DateTime.parse(date);
      final dailyReport = await _api.getDailyReportByDate(dateObj);

      final tasksByProject = <String, List<ReportTask>>{};

      if (dailyReport != null) {
        final items = dailyReport['items'] as List<dynamic>? ?? [];
        for (final item in items) {
          final itemMap = item as Map<String, dynamic>;
          final projectId = itemMap['projectId']?.toString();
          if (projectId == null || projectId.isEmpty) continue;

          final itemTasks = itemMap['tasks'] as List<dynamic>? ?? [];
          final tasks = <ReportTask>[];
          for (final taskJson in itemTasks) {
            try {
              tasks.add(ReportTask.fromJson(taskJson as Map<String, dynamic>));
            } catch (e) {
              _logger.warning('Failed to parse task: $e');
            }
          }
          tasksByProject[projectId] = tasks;
        }
        _logger.info('Daily report cached for $date: ${tasksByProject.length} projects with tasks');
      } else {
        _logger.info('Daily report for $date returned null (no report for this date)');
      }

      _cache[date] = tasksByProject;
      return tasksByProject;
    } catch (e, stackTrace) {
      _logger.error('Failed to load daily report for $date', e, stackTrace);
      final empty = <String, List<ReportTask>>{};
      _cache[date] = empty;
      return empty;
    }
  }

  /// Invalidate cache for a specific date
  void invalidateDate(String date) {
    _cache.remove(date);
  }

  /// Invalidate all cached data (call after adding/removing/updating tasks)
  void invalidate() {
    _cache.clear();
  }
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
  final _cache = DailyReportCache();
  late final LoggerService _logger;

  ProjectTasksNotifier(this._ref, this.key)
      : super(const ProjectTasksInitial()) {
    _logger = _ref.read(loggerServiceProvider);
  }

  bool _isLoading = false;

  /// Load tasks for this project and date from the shared cache
  Future<void> loadTasks() async {
    if (_isLoading) return;

    // Don't reload if already loaded
    if (state is ProjectTasksLoaded) return;

    _isLoading = true;
    state = const ProjectTasksLoading();

    try {
      final tasksByProject = await _cache.getTasksByProject(key.date);
      final tasks = tasksByProject[key.projectId] ?? [];

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
    _cache.invalidateDate(key.date);
    final currentState = state;
    if (currentState is ProjectTasksLoaded) {
      state = ProjectTasksLoaded([...currentState.tasks, task]);
    } else {
      state = ProjectTasksLoaded([task]);
    }
  }

  /// Remove a task from local state
  void removeTask(String taskId) {
    _cache.invalidateDate(key.date);
    final currentState = state;
    if (currentState is ProjectTasksLoaded) {
      state = ProjectTasksLoaded(
        currentState.tasks.where((t) => t.id != taskId).toList(),
      );
    }
  }

  /// Update a task in local state
  void updateTask(ReportTask updatedTask) {
    _cache.invalidateDate(key.date);
    final currentState = state;
    if (currentState is ProjectTasksLoaded) {
      state = ProjectTasksLoaded(
        currentState.tasks.map((t) => t.id == updatedTask.id ? updatedTask : t).toList(),
      );
    }
  }

  /// Refresh tasks from API (forces reload even if already loaded)
  Future<void> refresh() async {
    if (_isLoading) return;

    _isLoading = true;
    _cache.invalidateDate(key.date);
    state = const ProjectTasksLoading();

    try {
      final tasksByProject = await _cache.getTasksByProject(key.date);
      final tasks = tasksByProject[key.projectId] ?? [];

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
