import 'dart:convert';
import 'package:http/http.dart' as http;
import 'logger_service.dart';
import 'storage_service.dart';

/// Service for making API calls to the backend
class ApiService {
  static final ApiService _instance =
      ApiService._internal();
  factory ApiService() => _instance;

  final _logger = LoggerService();
  final _storage = StorageService();

  // New API Configuration
  static const String baseUrl =
      'https://intercompany-superindulgently-lesha.ngrok-free.dev/api/v1';

  // Old API Configuration (commented out)
  // static const String baseUrl =
  //     'https://testreport.ssarchitects.ae/api/v1';
  // static const String authToken =
  //     'Bearer e985666576fc298350682a2f2f1a8093d022d740aa96f0a9b72785a134cc2c95';

  ApiService._internal();

  /// Get common headers for all API requests (using user's auth token)
  Map<String, String> get _headers {
    final user = _storage.getCurrentUser();
    final token = user?.token;
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /*
  // Old static headers (commented out)
  Map<String, String> get _headers => {
    'Authorization': authToken,
    'Content-Type': 'application/json',
  };
  */

  /// Fetch information from the API (projects, departments, employees, settings)
  ///
  /// [filter] - Optional filter: 'projects', 'departments', 'settings', or 'employees'
  /// If no filter is provided, returns all information
  Future<Map<String, dynamic>> getInfo({
    String? filter,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/get_info.php');
      final uriWithParams = filter != null
          ? uri.replace(queryParameters: {'filter': filter})
          : uri;

      _logger.info(
        'Fetching info from API${filter != null ? " (filter: $filter)" : ""}...',
      );

      final response = await http.get(
        uriWithParams,
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data =
            json.decode(response.body)
                as Map<String, dynamic>;
        _logger.info('Successfully fetched data from API');
        return data;
      } else {
        _logger.error(
          'API request failed with status ${response.statusCode}',
          null,
          null,
        );
        throw Exception(
          'Failed to fetch data: ${response.statusCode}',
        );
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Error fetching data from API',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Fetch projects from the new API endpoint
  Future<List<Map<String, dynamic>>> getProjects({
    String? district,
    String? type,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      _logger.info('Fetching projects from new API...');

      // Build query parameters
      final queryParams = <String, String>{};
      if (district != null) queryParams['district'] = district;
      if (type != null) queryParams['type'] = type;
      if (sortBy != null) queryParams['sortBy'] = sortBy;
      if (sortOrder != null) queryParams['sortOrder'] = sortOrder;

      final uri = Uri.parse('$baseUrl/projects').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final response = await http.get(uri, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        if (data['success'] == true && data.containsKey('projects') && data['projects'] is List) {
          _logger.info('Successfully fetched ${(data['projects'] as List).length} projects from API');
          return (data['projects'] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
        } else {
          _logger.warning('Unexpected API response format for projects');
          return [];
        }
      } else if (response.statusCode == 401) {
        _logger.error('Unauthorized - user may need to re-login', null, null);
        throw Exception('Unauthorized - please login again');
      } else {
        _logger.error('API request failed with status ${response.statusCode}', null, null);
        throw Exception('Failed to fetch projects: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching projects from API', e, stackTrace);
      rethrow;
    }
  }

  /*
  // Old getProjects method (commented out)
  Future<List<Map<String, dynamic>>> getProjectsOld() async {
    try {
      final data = await getInfo(filter: 'projects');

      // Extract projects array from response
      if (data.containsKey('projects') &&
          data['projects'] is List) {
        return (data['projects'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
      } else {
        _logger.warning(
          'Unexpected API response format for projects',
        );
        return [];
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Error fetching projects from API',
        e,
        stackTrace,
      );
      rethrow;
    }
  }
  */

  /// Fetch only departments from the API
  Future<List<Map<String, dynamic>>>
  getDepartments() async {
    try {
      final data = await getInfo(filter: 'departments');

      if (data.containsKey('departments') &&
          data['departments'] is List) {
        return (data['departments'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
      } else {
        _logger.warning(
          'Unexpected API response format for departments',
        );
        return [];
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Error fetching departments from API',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Fetch only employees from the API
  Future<List<Map<String, dynamic>>> getEmployees() async {
    try {
      final data = await getInfo(filter: 'employees');

      if (data.containsKey('employees') &&
          data['employees'] is List) {
        return (data['employees'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
      } else {
        _logger.warning(
          'Unexpected API response format for employees',
        );
        return [];
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Error fetching employees from API',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Fetch only settings from the API
  Future<Map<String, dynamic>> getSettings() async {
    try {
      final data = await getInfo(filter: 'settings');

      if (data.containsKey('settings') &&
          data['settings'] is Map) {
        return Map<String, dynamic>.from(data['settings']);
      } else if (!data.containsKey('settings')) {
        return data;
      } else {
        _logger.warning(
          'Unexpected API response format for settings',
        );
        return {};
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Error fetching settings from API',
        e,
        stackTrace,
      );
      rethrow;
    }
  }
}
