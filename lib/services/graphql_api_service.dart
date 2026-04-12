import 'dart:convert';
import 'dart:io';
import '../graphql/graphql_client.dart';
import '../graphql/queries/attendance_queries.dart';
import '../graphql/queries/time_entry_queries.dart';
import '../graphql/queries/task_queries.dart';
import '../graphql/queries/project_queries.dart';
import '../graphql/queries/notification_queries.dart';
import '../graphql/queries/storage_queries.dart';
import 'logger_service.dart';
import 'graphql_auth_service.dart';

/// Exception thrown when token refresh fails and user must be logged out
class TokenExpiredException implements Exception {
  final String message;
  TokenExpiredException([this.message = 'Session expired. Please login again.']);

  @override
  String toString() => message;
}

/// GraphQL API service - replaces the REST ApiService
class GraphqlApiService {
  static final GraphqlApiService _instance = GraphqlApiService._internal();
  factory GraphqlApiService() => _instance;

  final _logger = LoggerService();
  final _graphql = GraphQLClientService();
  final _authService = GraphqlAuthService();

  GraphqlApiService._internal();

  /// Execute a query with automatic token refresh on auth errors
  Future<Map<String, dynamic>?> _queryWithRetry(
    String query, {
    Map<String, dynamic>? variables,
    bool retryOnAuth = true,
  }) async {
    try {
      final result = await _graphql.query(query, variables: variables);

      if (result.hasException) {
        if (retryOnAuth && _graphql.isAuthError(result.exception)) {
          final refreshed = await _authService.refreshAccessToken();
          if (refreshed) {
            final retryResult = await _graphql.query(query, variables: variables);
            if (retryResult.hasException) {
              throw retryResult.exception!;
            }
            return retryResult.data;
          } else {
            await _authService.forceLogout();
            throw TokenExpiredException();
          }
        }
        throw result.exception!;
      }

      return result.data;
    } on AuthenticationException {
      if (retryOnAuth) {
        final refreshed = await _authService.refreshAccessToken();
        if (refreshed) {
          return _queryWithRetry(query, variables: variables, retryOnAuth: false);
        }
      }
      await _authService.forceLogout();
      throw TokenExpiredException();
    }
  }

  /// Execute a mutation with automatic token refresh on auth errors
  Future<Map<String, dynamic>?> _mutateWithRetry(
    String mutation, {
    Map<String, dynamic>? variables,
    bool retryOnAuth = true,
  }) async {
    try {
      final result = await _graphql.mutate(mutation, variables: variables);

      if (result.hasException) {
        if (retryOnAuth && _graphql.isAuthError(result.exception)) {
          final refreshed = await _authService.refreshAccessToken();
          if (refreshed) {
            final retryResult = await _graphql.mutate(mutation, variables: variables);
            if (retryResult.hasException) {
              throw retryResult.exception!;
            }
            return retryResult.data;
          } else {
            await _authService.forceLogout();
            throw TokenExpiredException();
          }
        }
        throw result.exception!;
      }

      return result.data;
    } on AuthenticationException {
      if (retryOnAuth) {
        final refreshed = await _authService.refreshAccessToken();
        if (refreshed) {
          return _mutateWithRetry(mutation, variables: variables, retryOnAuth: false);
        }
      }
      await _authService.forceLogout();
      throw TokenExpiredException();
    }
  }

  // ============================================================================
  // PROJECTS
  // ============================================================================

  /// Get all projects with optional filtering
  Future<List<Map<String, dynamic>>> getProjects({
    Map<String, dynamic>? filter,
    int? page,
    int? pageSize,
  }) async {
    final result = await getProjectsPaginated(
      filter: filter,
      page: page,
      pageSize: pageSize,
    );
    return result.items;
  }

  /// Fetch projects with full pagination metadata
  Future<PaginatedResult<Map<String, dynamic>>> getProjectsPaginated({
    Map<String, dynamic>? filter,
    int? page,
    int? pageSize,
  }) async {
    try {
      _logger.info('Fetching projects via GraphQL (page: $page, pageSize: $pageSize)...');

      final variables = <String, dynamic>{};
      if (filter != null) variables['filter'] = filter;
      if (page != null || pageSize != null) {
        variables['pagination'] = {
          if (page != null) 'page': page,
          if (pageSize != null) 'pageSize': pageSize,
        };
      }

      final data = await _queryWithRetry(
        ProjectQueries.getProjects,
        variables: variables.isNotEmpty ? variables : null,
      );

      if (data == null) return PaginatedResult.empty();

      final projectsData = data['Project_Project_GetProjects'];
      if (projectsData == null) return PaginatedResult.empty();

      final items = (projectsData['items'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      _logger.info('Fetched ${items.length} projects (page ${projectsData['page']}/${projectsData['totalPages']})');

      return PaginatedResult(
        items: items,
        page: projectsData['page'] as int? ?? 1,
        pageSize: projectsData['pageSize'] as int? ?? items.length,
        total: projectsData['total'] as int? ?? items.length,
        totalPages: projectsData['totalPages'] as int? ?? 1,
        hasNextPage: projectsData['hasNextPage'] as bool? ?? false,
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch projects', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return PaginatedResult.empty();
    }
  }

  // ============================================================================
  // ATTENDANCE / CURRENT STATUS
  // ============================================================================

  /// Get current attendance status (replaces getOpenEntry, getMyAttendance, getAttendanceStatus)
  Future<Map<String, dynamic>?> getMyCurrentStatus() async {
    try {
      _logger.info('Fetching current attendance status...');

      final data = await _queryWithRetry(AttendanceQueries.getMyCurrentStatus);
      if (data == null) return null;

      return data['Attendance_Attendance_GetMyCurrentStatus'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch current status', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Get open time entry (extracted from current status)
  Future<Map<String, dynamic>?> getOpenEntry() async {
    final status = await getMyCurrentStatus();
    if (status == null) return null;
    return status['activeTimeEntry'] as Map<String, dynamic>?;
  }

  /// Get my attendance for today (extracted from current status)
  Future<Map<String, dynamic>?> getMyAttendance() async {
    final status = await getMyCurrentStatus();
    if (status == null) return null;
    return status['todayAttendance'] as Map<String, dynamic>?;
  }

  /// Get attendance status (extracted from current status)
  Future<Map<String, dynamic>?> getAttendanceStatus() async {
    final status = await getMyCurrentStatus();
    if (status == null) return null;

    return {
      'isActive': status['hasCheckedInToday'] ?? false,
      'totalSeconds': ((status['totalWorkedMinutesToday'] as num?) ?? 0) * 60,
      'currentSession': status['currentSession'],
      'todaySessions': status['todaySessions'],
    };
  }

  /// Get today's time entries (from sessions in current status)
  Future<List<Map<String, dynamic>>> getTodayTimeEntries() async {
    try {
      final status = await getMyCurrentStatus();
      if (status == null) return [];

      final sessions = status['todaySessions'] as List<dynamic>? ?? [];
      final entries = <Map<String, dynamic>>[];

      for (final session in sessions) {
        final sessionEntries = (session as Map<String, dynamic>)['timeEntries'] as List<dynamic>? ?? [];
        for (final entry in sessionEntries) {
          entries.add(entry as Map<String, dynamic>);
        }
      }

      return entries;
    } catch (e, stackTrace) {
      _logger.error('Failed to get today time entries', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return [];
    }
  }

  // ============================================================================
  // CHECK-IN / CHECK-OUT
  // ============================================================================

  /// Check in (replaces recordBiometric for check-in)
  Future<Map<String, dynamic>?> checkIn({
    double? latitude,
    double? longitude,
  }) async {
    try {
      _logger.info('Checking in...');

      final data = await _mutateWithRetry(
        AttendanceQueries.checkIn,
        variables: {
          'input': {
            if (latitude != null) 'latitude': latitude,
            if (longitude != null) 'longitude': longitude,
          },
        },
      );

      if (data == null) return null;

      final result = data['Attendance_Session_CheckIn'] as Map<String, dynamic>?;
      if (result != null && result['success'] == true) {
        _logger.info('Check-in successful');
      }
      return result;
    } catch (e, stackTrace) {
      _logger.error('Check-in failed', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Check out (replaces recordBiometric for check-out)
  Future<Map<String, dynamic>?> checkOut({
    double? latitude,
    double? longitude,
  }) async {
    try {
      _logger.info('Checking out...');

      final data = await _mutateWithRetry(
        AttendanceQueries.checkOut,
        variables: {
          'input': {
            if (latitude != null) 'latitude': latitude,
            if (longitude != null) 'longitude': longitude,
          },
        },
      );

      if (data == null) return null;

      final result = data['Attendance_Session_CheckOut'] as Map<String, dynamic>?;
      if (result != null && result['success'] == true) {
        _logger.info('Check-out successful');
      }
      return result;
    } catch (e, stackTrace) {
      _logger.error('Check-out failed', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  // ============================================================================
  // TIMER COMPATIBILITY METHODS (bridge old REST API patterns to GraphQL)
  // ============================================================================

  /// Start time on a project - sets the active time entry's project or resumes
  /// Replaces old `startTime(projectId)` REST call
  Future<bool> startTimeOnProject(String projectId) async {
    try {
      _logger.info('Starting time on project: $projectId');

      // Get the active time entry
      final openEntry = await getOpenEntry();
      if (openEntry != null) {
        final currentProjectId = openEntry['projectId'] as String?;
        if (currentProjectId != null && currentProjectId != projectId) {
          // SWITCH: currently on a different project
          final result = await _callSetProjectMutation(
            currentProjectId: currentProjectId,
            selectedProjectId: projectId,
          );
          return result != null;
        } else if (currentProjectId == projectId) {
          // Already on this project
          return true;
        } else {
          // Entry exists but no project set — just set the project
          final result = await _callSetProjectMutation(
            selectedProjectId: projectId,
          );
          return result != null;
        }
      }

      // No active entry — start a new one (creates entry on the server)
      _logger.info('No active time entry, creating new one for project: $projectId');
      final result = await _callSetProjectMutation(
        selectedProjectId: projectId,
      );
      return result != null;
    } catch (e, stackTrace) {
      _logger.error('Failed to start time on project', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return false;
    }
  }

  /// End/pause the active time entry
  /// Replaces old `endTime(projectId)` REST call
  Future<bool> endActiveTimeEntry([String? timeEntryId]) async {
    try {
      String? entryId = timeEntryId;

      if (entryId == null || entryId == 'pending') {
        // Find the active entry
        final openEntry = await getOpenEntry();
        if (openEntry == null) {
          _logger.info('No active time entry to end');
          return true; // Already ended
        }
        entryId = openEntry['id'] as String;
      }

      _logger.info('Ending time entry: $entryId');
      final result = await pauseTimeEntry(entryId);
      return result != null;
    } catch (e, stackTrace) {
      _logger.error('Failed to end active time entry', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return false;
    }
  }

  // ============================================================================
  // TIME ENTRIES
  // ============================================================================

  /// Update a time entry
  Future<Map<String, dynamic>?> updateTimeEntry(
    String timeEntryId, {
    String? description,
    String? projectId,
    String? startTime,
    String? endTime,
  }) async {
    try {
      _logger.info('Updating time entry: $timeEntryId');

      final input = <String, dynamic>{};
      if (description != null) input['description'] = description;
      if (projectId != null) input['projectId'] = projectId;
      if (startTime != null) input['startTime'] = startTime;
      if (endTime != null) input['endTime'] = endTime;

      final data = await _mutateWithRetry(
        TimeEntryQueries.updateTimeEntry,
        variables: {
          'input': input,
          'timeEntryId': timeEntryId,
        },
      );

      if (data == null) return null;
      return data['Attendance_TimeEntry_Update'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to update time entry', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Pause a time entry (replaces endTime)
  Future<Map<String, dynamic>?> pauseTimeEntry(String timeEntryId) async {
    try {
      _logger.info('Pausing time entry: $timeEntryId');

      final data = await _mutateWithRetry(
        TimeEntryQueries.pauseTimeEntry,
        variables: {'timeEntryId': timeEntryId},
      );

      if (data == null) return null;
      return data['Attendance_TimeEntry_Pause'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to pause time entry', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Resume a time entry (replaces startTime)
  Future<Map<String, dynamic>?> resumeTimeEntry(String timeEntryId) async {
    try {
      _logger.info('Resuming time entry: $timeEntryId');

      final data = await _mutateWithRetry(
        TimeEntryQueries.resumeTimeEntry,
        variables: {'timeEntryId': timeEntryId},
      );

      if (data == null) return null;
      return data['Attendance_TimeEntry_Resume'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to resume time entry', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Internal helper to call the SetProject mutation with correct field names
  Future<Map<String, dynamic>?> _callSetProjectMutation({
    String? currentProjectId,
    String? selectedProjectId,
    String? description,
  }) async {
    try {
      final input = <String, dynamic>{};
      if (currentProjectId != null) input['currentProjectId'] = currentProjectId;
      if (selectedProjectId != null) input['selectedProjectId'] = selectedProjectId;
      if (description != null) input['description'] = description;

      final data = await _mutateWithRetry(
        TimeEntryQueries.setProject,
        variables: {'input': input},
      );

      if (data == null) return null;
      return data['Attendance_TimeEntry_SetProject'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to call SetProject mutation', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Set project for a time entry
  Future<Map<String, dynamic>?> setTimeEntryProject(
    String timeEntryId,
    String projectId,
  ) async {
    try {
      _logger.info('Setting project for time entry: $timeEntryId -> $projectId');

      final data = await _mutateWithRetry(
        TimeEntryQueries.setProject,
        variables: {
          'input': {
            'selectedProjectId': projectId,
          },
        },
      );

      if (data == null) return null;
      return data['Attendance_TimeEntry_SetProject'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to set project for time entry', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Delete a time entry
  Future<bool> deleteTimeEntry(String timeEntryId) async {
    try {
      _logger.info('Deleting time entry: $timeEntryId');

      final data = await _mutateWithRetry(
        TimeEntryQueries.deleteTimeEntry,
        variables: {'timeEntryId': timeEntryId},
      );

      return data != null;
    } catch (e, stackTrace) {
      _logger.error('Failed to delete time entry', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return false;
    }
  }

  /// Get pending time entries
  Future<List<Map<String, dynamic>>> getPendingTimeEntries() async {
    try {
      _logger.info('Fetching pending time entries...');

      final data = await _queryWithRetry(
        TimeEntryQueries.getMyPendingEntries,
        variables: {
          'pagination': {'pageSize': 100},
        },
      );

      if (data == null) return [];

      final pendingData = data['Attendance_TimeEntry_GetMyPendingEntries'];
      if (pendingData == null) return [];

      final entries = pendingData['entries'] as List<dynamic>? ?? [];
      _logger.info('Fetched ${entries.length} pending time entries');
      return entries.cast<Map<String, dynamic>>();
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch pending time entries', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return [];
    }
  }

  /// Mark time entry as task submitted (update taskSubmissionStatus)
  Future<bool> markTimeEntryTaskSubmitted(String timeEntryId) async {
    try {
      final data = await _mutateWithRetry(
        TimeEntryQueries.updateTimeEntry,
        variables: {
          'input': {'taskSubmissionStatus': 'SUBMITTED'},
          'timeEntryId': timeEntryId,
        },
      );
      return data != null;
    } catch (e, stackTrace) {
      _logger.error('Failed to mark time entry submitted', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return false;
    }
  }

  /// Mark multiple time entries as submitted
  Future<bool> markMultipleTimeEntriesSubmitted(List<String> entryIds) async {
    try {
      for (final id in entryIds) {
        await markTimeEntryTaskSubmitted(id);
      }
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to mark multiple entries submitted', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return false;
    }
  }

  // ============================================================================
  // TASKS
  // ============================================================================

  /// Create a task for a time entry
  Future<Map<String, dynamic>?> createTask({
    required String timeEntryId,
    required String title,
    String? description,
    List<Map<String, dynamic>>? images,
  }) async {
    try {
      _logger.info('Creating task for time entry: $timeEntryId');

      final input = <String, dynamic>{
        'timeEntryId': timeEntryId,
        'title': title,
        if (description != null) 'description': description,
        if (images != null && images.isNotEmpty) 'images': images,
      };

      final data = await _mutateWithRetry(
        TaskQueries.createTask,
        variables: {'input': input},
      );

      if (data == null) return null;
      return data['Attendance_Task_Create'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to create task', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Upload a file to storage and return the URL and metadata
  Future<Map<String, dynamic>?> uploadFileToStorage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      final filename = file.path.split('/').last;
      final extension = filename.split('.').last.toLowerCase();
      final contentType = _getContentType(extension);

      final uploadData = await _mutateWithRetry(
        StorageQueries.uploadImageWithThumbnail,
        variables: {
          'input': {
            'base64': base64String,
            'filename': filename,
            'contentType': contentType,
            'folder': 'ATTENDANCE',
          },
        },
      );

      if (uploadData == null) return null;

      final result = uploadData['Storage_UploadImageWithThumbnail'] as Map<String, dynamic>;
      final urlField = result['url'];
      final thumbField = result['thumbnailUrl'];
      return {
        'imageUrl': (urlField is Map) ? urlField['url'] as String : urlField as String,
        'thumbnailUrl': (thumbField is Map) ? thumbField['url'] as String? : thumbField as String?,
        'mimeType': contentType,
        'fileSize': bytes.length,
      };
    } catch (e, stackTrace) {
      _logger.error('Failed to upload file to storage', e, stackTrace);
      return null;
    }
  }

  /// Update a task
  Future<Map<String, dynamic>?> updateTask(
    String taskId, {
    String? title,
    String? description,
  }) async {
    try {
      _logger.info('Updating task: $taskId');

      final input = <String, dynamic>{};
      if (title != null) input['title'] = title;
      if (description != null) input['description'] = description;

      final data = await _mutateWithRetry(
        TaskQueries.updateTask,
        variables: {
          'input': input,
          'taskId': taskId,
        },
      );

      if (data == null) return null;
      return data['Attendance_Task_Update'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to update task', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Delete a task
  Future<bool> deleteTask(String taskId) async {
    try {
      _logger.info('Deleting task: $taskId');

      final data = await _mutateWithRetry(
        TaskQueries.deleteTask,
        variables: {'taskId': taskId},
      );

      return data != null;
    } catch (e, stackTrace) {
      _logger.error('Failed to delete task', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return false;
    }
  }

  /// Get tasks by time entry
  Future<List<Map<String, dynamic>>> getTasksByTimeEntry(String timeEntryId) async {
    try {
      final data = await _queryWithRetry(
        TaskQueries.getByTimeEntry,
        variables: {'timeEntryId': timeEntryId},
      );

      if (data == null) return [];
      final tasks = data['Attendance_Task_GetByTimeEntry'] as List<dynamic>? ?? [];
      return tasks.cast<Map<String, dynamic>>();
    } catch (e, stackTrace) {
      _logger.error('Failed to get tasks by time entry', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return [];
    }
  }

  // ============================================================================
  // TASK IMAGES
  // ============================================================================

  /// Get images for a task by task ID
  Future<List<Map<String, dynamic>>> getTaskImages(String taskId) async {
    try {
      final data = await _queryWithRetry(
        TaskQueries.getTaskImages,
        variables: {'taskId': taskId},
      );

      if (data == null) return [];
      final images = data['Attendance_TaskImage_GetByTask'] as List<dynamic>? ?? [];
      return images.cast<Map<String, dynamic>>();
    } catch (e, stackTrace) {
      _logger.error('Failed to get task images', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return [];
    }
  }

  /// Upload an image and add it to a task
  Future<Map<String, dynamic>?> addTaskImage({
    required String taskId,
    required File imageFile,
    String? caption,
  }) async {
    try {
      _logger.info('Uploading image for task: $taskId');

      // Read file and encode as base64
      final bytes = await imageFile.readAsBytes();
      final base64String = base64Encode(bytes);
      final filename = imageFile.path.split('/').last;
      final extension = filename.split('.').last.toLowerCase();
      final contentType = _getContentType(extension);

      // Step 1: Upload image via storage mutation
      final uploadData = await _mutateWithRetry(
        StorageQueries.uploadImageWithThumbnail,
        variables: {
          'input': {
            'base64': base64String,
            'filename': filename,
            'contentType': contentType,
            'folder': 'ATTENDANCE',
          },
        },
      );

      if (uploadData == null) {
        throw Exception('Image upload failed');
      }

      final uploadResult = uploadData['Storage_UploadImageWithThumbnail'] as Map<String, dynamic>;
      final urlField = uploadResult['url'];
      final thumbField = uploadResult['thumbnailUrl'];
      final imageUrl = (urlField is Map) ? urlField['url'] as String : urlField as String;
      final thumbnailUrl = (thumbField is Map) ? thumbField['url'] as String? : thumbField as String?;

      // Step 2: Add image to task
      final addData = await _mutateWithRetry(
        TaskQueries.addTaskImage,
        variables: {
          'input': {
            'taskId': taskId,
            'imageUrl': imageUrl,
            if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
            if (caption != null) 'caption': caption,
            'mimeType': contentType,
            'fileSize': bytes.length,
          },
        },
      );

      if (addData == null) return null;
      return addData['Attendance_TaskImage_Add'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to add task image', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Remove an image from a task
  Future<bool> removeTaskImage(String imageId) async {
    try {
      _logger.info('Removing task image: $imageId');

      final data = await _mutateWithRetry(
        TaskQueries.removeTaskImage,
        variables: {'imageId': imageId},
      );

      return data != null;
    } catch (e, stackTrace) {
      _logger.error('Failed to remove task image', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return false;
    }
  }

  String _getContentType(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  // ============================================================================
  // DAILY REPORTS
  // ============================================================================

  /// Get my daily report for a specific date
  Future<Map<String, dynamic>?> getDailyReportByDate(DateTime date) async {
    try {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      _logger.info('Fetching daily report for: $dateStr');

      final data = await _queryWithRetry(
        AttendanceQueries.getMyDailyReport,
        variables: {'date': dateStr},
      );

      if (data == null) return null;
      return data['Attendance_Report_GetMyDailyReport'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch daily report', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Get daily report for a specific employee and date
  Future<Map<String, dynamic>?> getDailyReport(DateTime date, String employeeId) async {
    try {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final data = await _queryWithRetry(
        AttendanceQueries.getDailyReport,
        variables: {
          'date': dateStr,
          'employeeId': employeeId,
        },
      );

      if (data == null) return null;
      return data['Attendance_Report_GetDailyReport'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch daily report', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Get my time report for a month (single query for all days).
  /// Returns the full time report with days, summary, and project hours.
  Future<Map<String, dynamic>?> getMyTimeReport({String? month}) async {
    try {
      final monthStr = month ?? '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
      _logger.info('Fetching time report for month: $monthStr');

      final data = await _queryWithRetry(
        AttendanceQueries.getMyTimeReport,
        variables: {'month': monthStr},
      );

      if (data == null) return null;
      return data['Attendance_Report_GetMyTimeReport'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch time report', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }

  /// Get my daily reports for a date range using GetMyTimeReport (1 query per month).
  /// Returns a map with 'reports' list and 'meta' info.
  Future<Map<String, dynamic>> getMyDailyReports({
    DateTime? from,
    DateTime? to,
  }) async {
    final endDate = to ?? DateTime.now();
    final startDate = from ?? DateTime(endDate.year, endDate.month - 2, 1);

    // Collect unique months needed
    final months = <String>{};
    var current = DateTime(startDate.year, startDate.month);
    final endMonth = DateTime(endDate.year, endDate.month);
    while (!current.isAfter(endMonth)) {
      months.add('${current.year}-${current.month.toString().padLeft(2, '0')}');
      current = DateTime(current.year, current.month + 1);
    }

    _logger.info('Fetching time reports for ${months.length} month(s): $months');

    // Fetch months sequentially to avoid rate limiting (ThrottlerException: 429)
    final results = <Map<String, dynamic>?>[];
    for (final m in months) {
      results.add(await getMyTimeReport(month: m));
    }

    // Flatten days from all months, filter by date range, sort newest first
    final startDay = DateTime(startDate.year, startDate.month, startDate.day);
    final endDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    final allDays = <Map<String, dynamic>>[];
    for (final result in results) {
      if (result == null) continue;
      final report = result['report'];
      if (report == null) continue;

      // Handle both single report object and list of reports
      final reportData = report is List ? (report.isNotEmpty ? report[0] : null) : report;
      if (reportData == null) continue;

      final days = (reportData['days'] as List<dynamic>?) ?? [];
      for (final day in days) {
        final dayMap = day as Map<String, dynamic>;
        final dateStr = dayMap['date'] as String?;
        if (dateStr == null) continue;

        final dayDate = DateTime.tryParse(dateStr);
        if (dayDate == null) continue;
        if (dayDate.isBefore(startDay) || dayDate.isAfter(endDay)) continue;

        // Transform to report-like format for the screen
        allDays.add({
          '_id': dateStr,
          'date': dateStr,
          'reportDate': dateStr,
          'dayName': dayMap['dayName'],
          'checkIn': dayMap['checkIn'],
          'checkOut': dayMap['checkOut'],
          'totalTime': dayMap['totalTime'],
          'totalHours': _parseTimeToHours(dayMap['totalTime'] as String?),
          'expectedHours': dayMap['expectedHours'],
          'overtime': dayMap['overtime'],
          'lessWorkingTime': dayMap['lessWorkingTime'],
          'isWeekend': dayMap['isWeekend'] ?? false,
          'isHoliday': dayMap['isHoliday'] ?? false,
          'isLeave': dayMap['isLeave'] ?? false,
          'leaveType': dayMap['leaveType'],
          'notes': dayMap['notes'],
          // Tasks are loaded on-demand when user expands a report
          'tasks': <Map<String, dynamic>>[],
          'taskCount': 0,
        });
      }
    }

    // Sort newest first
    allDays.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

    return {
      'reports': allDays,
      'meta': {
        'total': allDays.length,
        'from': startDate.toIso8601String(),
        'to': endDate.toIso8601String(),
      },
    };
  }

  /// Parse "HH:MM" time string to decimal hours
  double _parseTimeToHours(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 0.0;
    final parts = timeStr.split(':');
    if (parts.length != 2) return 0.0;
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    return hours + minutes / 60.0;
  }

  // ============================================================================
  // NOTIFICATIONS
  // ============================================================================

  /// Get notifications
  Future<List<Map<String, dynamic>>> getNotifications({int limit = 50}) async {
    try {
      _logger.info('Fetching notifications...');

      final data = await _queryWithRetry(
        NotificationQueries.getNotifications,
        variables: {
          'pagination': {'pageSize': limit},
          'orderBy': {'field': 'CREATED_AT', 'direction': 'DESC'},
        },
      );

      if (data == null) return [];

      final notifData = data['Notification_GetNotifications'];
      if (notifData == null) return [];

      final items = notifData['items'] as List<dynamic>? ?? [];
      _logger.info('Fetched ${items.length} notifications');
      return items.cast<Map<String, dynamic>>();
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch notifications', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return [];
    }
  }

  /// Get unread notification count
  Future<int> getUnreadNotificationCount() async {
    try {
      final data = await _queryWithRetry(NotificationQueries.getUnreadCount);
      if (data == null) return 0;

      final countData = data['Notification_GetUnreadCount'];
      return (countData?['count'] as num?)?.toInt() ?? 0;
    } catch (e, stackTrace) {
      _logger.error('Failed to get unread count', e, stackTrace);
      return 0;
    }
  }

  /// Mark a notification as read
  Future<bool> markNotificationAsRead(String id) async {
    try {
      final data = await _mutateWithRetry(
        NotificationQueries.markAsRead,
        variables: {'id': id},
      );
      return data != null;
    } catch (e, stackTrace) {
      _logger.error('Failed to mark notification as read', e, stackTrace);
      return false;
    }
  }

  /// Mark all notifications as read
  Future<bool> markAllNotificationsAsRead() async {
    try {
      final data = await _mutateWithRetry(NotificationQueries.markAllAsRead);
      return data != null;
    } catch (e, stackTrace) {
      _logger.error('Failed to mark all notifications as read', e, stackTrace);
      return false;
    }
  }

  // ============================================================================
  // FILE UPLOAD
  // ============================================================================

  /// Upload a file (generic)
  Future<Map<String, dynamic>?> uploadFile({
    required File file,
    String folder = 'GENERAL',
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      final filename = file.path.split('/').last;
      final extension = filename.split('.').last.toLowerCase();
      final contentType = _getContentType(extension);

      final data = await _mutateWithRetry(
        StorageQueries.uploadFile,
        variables: {
          'input': {
            'base64': base64String,
            'filename': filename,
            'contentType': contentType,
            'folder': folder,
          },
        },
      );

      if (data == null) return null;
      return data['Storage_UploadFile'] as Map<String, dynamic>?;
    } catch (e, stackTrace) {
      _logger.error('Failed to upload file', e, stackTrace);
      if (e is TokenExpiredException) rethrow;
      return null;
    }
  }
}

/// Generic paginated result wrapper
class PaginatedResult<T> {
  final List<T> items;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final bool hasNextPage;

  const PaginatedResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    required this.hasNextPage,
  });

  factory PaginatedResult.empty() => PaginatedResult(
    items: [],
    page: 1,
    pageSize: 0,
    total: 0,
    totalPages: 0,
    hasNextPage: false,
  );
}
