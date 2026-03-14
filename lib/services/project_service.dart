import '../models/project.dart';
import '../core/constants/app_constants.dart';
import 'storage_service.dart';
import 'logger_service.dart';
import 'graphql_api_service.dart';

/// Result of a paginated project fetch
class ProjectFetchResult {
  final List<Project> projects;
  final bool hasNextPage;
  final int currentPage;
  final int totalPages;
  final int total;

  const ProjectFetchResult({
    required this.projects,
    this.hasNextPage = false,
    this.currentPage = 1,
    this.totalPages = 1,
    this.total = 0,
  });
}

class ProjectService {
  static final ProjectService _instance = ProjectService._internal();
  factory ProjectService() => _instance;

  final _storage = StorageService();
  final _logger = LoggerService();
  final _api = GraphqlApiService();

  ProjectService._internal();

  /// Fetch projects from GraphQL API (legacy - returns flat list)
  Future<List<Project>> fetchProjects() async {
    final result = await fetchProjectsPaginated(page: 1, pageSize: 50);
    return result.projects;
  }

  /// Fetch projects with pagination support
  Future<ProjectFetchResult> fetchProjectsPaginated({
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      _logger.info('Fetching projects page $page (pageSize: $pageSize)...');

      final result = await _api.getProjectsPaginated(
        page: page,
        pageSize: pageSize,
      );

      final projects = result.items.map((json) {
        try {
          final project = Project.fromGraphql(json);
          return _enrichProjectWithLocalTime(project);
        } catch (e) {
          _logger.warning('Failed to parse project: $e');
          return null;
        }
      }).whereType<Project>().toList();

      if (projects.isEmpty && page == 1) {
        _logger.warning('No projects received from API, using cached/mock data');

        final existingProjects = _storage.getAllProjects();
        if (existingProjects.isNotEmpty) {
          _logger.info('Loaded ${existingProjects.length} projects from storage');
          return ProjectFetchResult(
            projects: existingProjects.map((p) => _enrichProjectWithLocalTime(p)).toList(),
          );
        }

        return ProjectFetchResult(projects: _createMockProjects());
      }

      // On first page, clear old cache and save
      if (page == 1) {
        await _storage.clearProjects();
      }
      await _storage.saveProjects(projects);
      _logger.info('Loaded ${projects.length} projects (page $page/${result.totalPages})');

      return ProjectFetchResult(
        projects: projects,
        hasNextPage: result.hasNextPage,
        currentPage: result.page,
        totalPages: result.totalPages,
        total: result.total,
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch projects from API', e, stackTrace);

      if (page == 1) {
        final existingProjects = _storage.getAllProjects();
        if (existingProjects.isNotEmpty) {
          _logger.info('Using ${existingProjects.length} cached projects');
          return ProjectFetchResult(
            projects: existingProjects.map((p) => _enrichProjectWithLocalTime(p)).toList(),
          );
        }
        return ProjectFetchResult(projects: _createMockProjects());
      }

      return const ProjectFetchResult(projects: []);
    }
  }

  Project? getProject(String id) {
    try {
      return _storage.getProject(id);
    } catch (e, stackTrace) {
      _logger.error('Failed to get project', e, stackTrace);
      return null;
    }
  }

  Future<void> updateProject(Project project) async {
    try {
      await _storage.saveProject(project);
      _logger.info('Project updated: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to update project', e, stackTrace);
      rethrow;
    }
  }

  Future<void> updateProjectTime(String projectId, Duration additionalTime) async {
    try {
      final project = _storage.getProject(projectId);
      if (project == null) {
        throw Exception('Project not found: $projectId');
      }

      final updatedProject = project.copyWith(
        totalTime: project.totalTime + additionalTime,
      );

      await _storage.saveProject(updatedProject);
      _logger.debug('Updated time for project: ${project.name}');
    } catch (e, stackTrace) {
      _logger.error('Failed to update project time', e, stackTrace);
      rethrow;
    }
  }

  Future<Project> createProject({
    required String name,
    String? description,
    String? client,
    DateTime? deadline,
  }) async {
    try {
      final project = Project(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        description: description,
        client: client,
        createdAt: DateTime.now(),
        deadline: deadline,
        status: 'active',
      );

      await _storage.saveProject(project);
      _logger.info('Project created: $name');
      return project;
    } catch (e, stackTrace) {
      _logger.error('Failed to create project', e, stackTrace);
      rethrow;
    }
  }

  Future<void> deleteProject(String id) async {
    try {
      await _storage.deleteProject(id);
      _logger.info('Project deleted: $id');
    } catch (e, stackTrace) {
      _logger.error('Failed to delete project', e, stackTrace);
      rethrow;
    }
  }

  Future<void> syncProjects() async {
    try {
      _logger.info('Syncing projects with API...');
      await fetchProjects();
      _logger.info('Projects synced successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to sync projects', e, stackTrace);
      rethrow;
    }
  }

  Project refreshProjectTime(Project project) {
    return _enrichProjectWithLocalTime(project);
  }

  Future<void> resetAllProjectTimes() async {
    try {
      _logger.info('Resetting all project times...');
      await _storage.clearAllTimeEntries();
      _logger.info('All project times reset successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to reset project times', e, stackTrace);
      rethrow;
    }
  }

  Project _enrichProjectWithLocalTime(Project project) {
    try {
      final timeEntries = _storage.getTimeEntriesByProject(project.id);

      Duration totalTime = Duration.zero;
      DateTime? mostRecentStart;

      for (final entry in timeEntries) {
        totalTime += entry.actualDuration;
        if (mostRecentStart == null || entry.startTime.isAfter(mostRecentStart)) {
          mostRecentStart = entry.startTime;
        }
      }

      return project.copyWith(
        totalTime: totalTime,
        lastActiveAt: project.lastActiveAt ?? mostRecentStart,
      );
    } catch (e) {
      _logger.warning('Failed to calculate total time for project ${project.name}: $e');
      return project;
    }
  }

  List<Project> _createMockProjects() {
    return AppConstants.mockProjects.asMap().entries.map((entry) {
      return Project(
        id: 'project_${entry.key + 1}',
        name: entry.value,
        description: 'Description for ${entry.value}',
        client: 'Client ${entry.key + 1}',
        createdAt: DateTime.now().subtract(Duration(days: entry.key * 7)),
        deadline: DateTime.now().add(Duration(days: 30 + entry.key * 10)),
        status: 'active',
      );
    }).toList();
  }
}
