import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project.dart';
import '../services/project_service.dart';
import '../services/logger_service.dart';
import 'auth_provider.dart';
import 'timer_provider.dart';

// Project service provider
final projectServiceProvider = Provider<ProjectService>((ref) {
  return ProjectService();
});

// Projects state provider
final projectsProvider = StateNotifierProvider<ProjectsNotifier, AsyncValue<List<Project>>>((ref) {
  return ProjectsNotifier(ref);
});

class ProjectsNotifier extends StateNotifier<AsyncValue<List<Project>>> {
  final Ref _ref;
  late final ProjectService _projectService;
  late final LoggerService _logger;

  ProjectsNotifier(this._ref) : super(const AsyncValue.loading()) {
    _projectService = _ref.read(projectServiceProvider);
    _logger = _ref.read(loggerServiceProvider);
    loadProjects();
  }

  // Load projects
  Future<void> loadProjects() async {
    try {
      state = const AsyncValue.loading();
      final projects = await _projectService.fetchProjects();
      state = AsyncValue.data(projects);
      _logger.info('Loaded ${projects.length} projects');
    } catch (e, stackTrace) {
      _logger.error('Failed to load projects', e, stackTrace);
      state = AsyncValue.error(e, stackTrace);
    }
  }

  // Refresh projects (full reload from API)
  Future<void> refreshProjects() async {
    await loadProjects();
  }

  // Refresh project times from local time entries (lightweight, no API call)
  void refreshProjectTimes() {
    state = state.whenData((projects) {
      // Recalculate total time for each project from local storage
      return projects.map((project) {
        return _projectService.refreshProjectTime(project);
      }).toList();
    });
  }

  // Get project by ID
  Project? getProject(String id) {
    return state.whenOrNull(
      data: (projects) => projects.firstWhere(
        (p) => p.id == id,
        orElse: () => throw Exception('Project not found'),
      ),
    );
  }

  // Update project
  Future<void> updateProject(Project project) async {
    try {
      await _projectService.updateProject(project);

      state = state.whenData((projects) {
        final index = projects.indexWhere((p) => p.id == project.id);
        if (index != -1) {
          final updatedProjects = List<Project>.from(projects);
          updatedProjects[index] = project;
          return updatedProjects;
        }
        return projects;
      });

      _logger.info('Project updated: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to update project', e, stackTrace);
      rethrow;
    }
  }

  // Create project (for future use)
  Future<void> createProject({
    required String name,
    String? description,
    String? client,
    DateTime? deadline,
  }) async {
    try {
      final project = await _projectService.createProject(
        name: name,
        description: description,
        client: client,
        deadline: deadline,
      );

      state = state.whenData((projects) {
        return [...projects, project];
      });

      _logger.info('Project created: $name');
    } catch (e, stackTrace) {
      _logger.error('Failed to create project', e, stackTrace);
      rethrow;
    }
  }

  // Delete project (for future use)
  Future<void> deleteProject(String id) async {
    try {
      await _projectService.deleteProject(id);

      state = state.whenData((projects) {
        return projects.where((p) => p.id != id).toList();
      });

      _logger.info('Project deleted: $id');
    } catch (e, stackTrace) {
      _logger.error('Failed to delete project', e, stackTrace);
      rethrow;
    }
  }

  // Reset all project times (clears all time entries)
  Future<void> resetAllProjectTimes() async {
    try {
      _logger.info('Resetting all project times...');

      // Clear all time entries from storage
      await _projectService.resetAllProjectTimes();

      // Reload projects to reflect zero times
      await loadProjects();

      _logger.info('All project times reset successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to reset all project times', e, stackTrace);
      rethrow;
    }
  }
}

// Selected project provider
final selectedProjectProvider = StateProvider<Project?>((ref) => null);

// Active projects provider (filters only active projects)
final activeProjectsProvider = Provider<List<Project>>((ref) {
  final projectsAsync = ref.watch(projectsProvider);

  return projectsAsync.whenOrNull(
    data: (projects) => projects.where((p) => p.status == 'active').toList(),
  ) ?? [];
});

// Active project time provider - shows only the current active project's elapsed time
final activeProjectTimeProvider = Provider<Duration>((ref) {
  final activeSession = ref.watch(currentTimerProvider);
  if (activeSession != null && activeSession.isRunning) {
    return activeSession.elapsedDuration;
  }
  return Duration.zero;
});

// Session total time provider - combines current active session + all completed entries today
final sessionTotalTimeProvider = Provider<Duration>((ref) {
  final activeSession = ref.watch(currentTimerProvider);
  final completedDurations = ref.watch(completedProjectDurationsProvider);

  Duration total = Duration.zero;

  // Add current active session elapsed time
  if (activeSession != null && activeSession.isRunning) {
    total += activeSession.elapsedDuration;
  }

  // Add all completed project durations from today
  for (final duration in completedDurations.values) {
    total += duration;
  }

  return total;
});
