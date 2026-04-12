import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import '../graphql/graphql_client.dart';
import '../graphql/queries/auth_queries.dart';
import '../models/user.dart';
import 'storage_service.dart';
import 'logger_service.dart';

class GraphqlAuthService {
  static final GraphqlAuthService _instance = GraphqlAuthService._internal();
  factory GraphqlAuthService() => _instance;

  final _storage = StorageService();
  final _logger = LoggerService();
  final _graphql = GraphQLClientService();

  // Stream controller for force logout events
  final _forceLogoutController = StreamController<void>.broadcast();

  /// Stream that emits when a force logout occurs (token expired)
  Stream<void> get forceLogoutStream => _forceLogoutController.stream;

  // Token refresh coordination
  bool _isRefreshing = false;
  Completer<bool>? _refreshCompleter;

  // Stream controller for token refresh events
  final _tokenRefreshedController = StreamController<void>.broadcast();

  /// Stream that emits when token has been successfully refreshed
  Stream<void> get tokenRefreshedStream => _tokenRefreshedController.stream;

  /// Check if a refresh is currently in progress
  bool get isRefreshing => _isRefreshing;

  GraphqlAuthService._internal();

  // ============================================================================
  // SSO LOGIN FLOW
  // ============================================================================

  /// Step 1: Initiate SSO login - opens browser and waits for callback
  /// Returns the User object on success
  Future<User> loginWithSSO() async {
    try {
      _logger.info('Initiating SSO login...');

      // Find an available port for the callback server
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      final redirectUri = 'http://127.0.0.1:$port/callback';

      _logger.info('SSO callback server started on port $port');

      // Step 1: Call InitiateSsoLogin to get authUrl
      final result = await _graphql.mutate(
        AuthQueries.initiateSsoLogin,
        variables: {
          'input': {
            'redirectUri': redirectUri,
          },
        },
      );

      if (result.hasException || result.data == null) {
        await server.close();
        final errorMsg = result.exception?.graphqlErrors.firstOrNull?.message ??
            'Failed to initiate SSO login';
        throw Exception(errorMsg);
      }

      final ssoData = result.data!['Auth_Sso_InitiateSsoLogin'];
      final authUrl = ssoData['authUrl'] as String;
      final ssoState = ssoData['state'] as String;

      _logger.info('SSO auth URL received, opening browser...');

      // Open the auth URL in the system browser
      final uri = Uri.parse(authUrl);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await server.close();
        throw Exception('Could not open browser for SSO login');
      }

      // Step 2: Wait for the callback
      final completer = Completer<Map<String, String>>();

      // Set a timeout for the callback
      final timeout = Timer(const Duration(minutes: 5), () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('SSO login timed out'));
        }
      });

      server.listen((request) async {
        if (request.uri.path == '/callback') {
          final queryParams = request.uri.queryParameters;

          // Send a success page to the browser
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write('''
              <html><body style="font-family: sans-serif; text-align: center; padding-top: 100px;">
                <h2>Login Successful!</h2>
                <p>You can close this window and return to the app.</p>
                <script>window.close();</script>
              </body></html>
            ''');
          await request.response.close();

          if (!completer.isCompleted) {
            completer.complete(queryParams);
          }
        } else {
          request.response
            ..statusCode = 404
            ..write('Not found');
          await request.response.close();
        }
      });

      try {
        final callbackParams = await completer.future;
        timeout.cancel();
        await server.close();

        final code = callbackParams['code'];
        final returnedState = callbackParams['state'];

        if (code == null) {
          final error = callbackParams['error'] ?? 'No authorization code received';
          throw Exception('SSO login failed: $error');
        }

        // Step 3: Verify SSO callback
        return await _verifySsoCallback(code, returnedState ?? ssoState);
      } catch (e) {
        timeout.cancel();
        await server.close();
        rethrow;
      }
    } catch (e, stackTrace) {
      _logger.error('SSO login failed', e, stackTrace);
      rethrow;
    }
  }

  /// Step 3: Verify SSO callback and get tokens
  Future<User> _verifySsoCallback(String code, String state) async {
    _logger.info('Verifying SSO callback...');

    final result = await _graphql.mutate(
      AuthQueries.verifySsoCallback,
      variables: {
        'input': {
          'code': code,
          'state': state,
        },
      },
    );

    if (result.hasException || result.data == null) {
      final errorMsg = result.exception?.graphqlErrors.firstOrNull?.message ??
          'SSO verification failed';
      throw Exception(errorMsg);
    }

    final data = result.data!['Auth_Sso_VerifySsoCallback'];
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'SSO verification failed');
    }

    final tokens = data['tokens'];
    final accessToken = tokens['accessToken'] as String;
    final refreshToken = tokens['refreshToken'] as String;

    // Save tokens temporarily and update GraphQL client
    _graphql.updateToken(accessToken);

    // Fetch user profile
    final user = await _fetchAndSaveUser(accessToken, refreshToken);

    _logger.info('SSO login successful for: ${user.email}');
    return user;
  }

  // ============================================================================
  // DEV LOGIN (for development/testing)
  // ============================================================================

  /// Dev login with email or employee ID (single step, no browser needed)
  Future<User> devLogin(String employeeIdOrEmail) async {
    try {
      _logger.info('Dev login with: $employeeIdOrEmail');

      final result = await _graphql.mutate(
        AuthQueries.devLogin,
        variables: {
          'input': {
            'employeeIdOrEmail': employeeIdOrEmail,
          },
        },
      );

      if (result.hasException || result.data == null) {
        final errorMsg = result.exception?.graphqlErrors.firstOrNull?.message ??
            'Dev login failed';
        throw Exception(errorMsg);
      }

      final data = result.data!['Auth_DevAuth_DevLogin'];
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'Dev login failed');
      }

      final tokens = data['tokens'];
      final accessToken = tokens['accessToken'] as String;
      final refreshToken = tokens['refreshToken'] as String;

      // Update GraphQL client with new token
      _graphql.updateToken(accessToken);

      // Fetch user profile
      final user = await _fetchAndSaveUser(accessToken, refreshToken);

      _logger.info('Dev login successful for: ${user.email}');
      return user;
    } catch (e, stackTrace) {
      _logger.error('Dev login failed', e, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // OTP LOGIN FLOW
  // ============================================================================

  /// Request OTP - sends a 6-digit code to the user's email
  Future<void> requestOtp(String email) async {
    try {
      _logger.info('Requesting OTP for: $email');

      final result = await _graphql.mutate(
        AuthQueries.requestOtp,
        variables: {
          'input': {
            'email': email,
          },
        },
      );

      if (result.hasException || result.data == null) {
        final errorMsg = result.exception?.graphqlErrors.firstOrNull?.message ??
            'Failed to send verification code';
        throw Exception(errorMsg);
      }

      final data = result.data!['Auth_Otp_RequestOtp'];
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'Failed to send verification code');
      }

      _logger.info('OTP sent successfully to: $email');
    } catch (e, stackTrace) {
      _logger.error('Failed to request OTP', e, stackTrace);
      rethrow;
    }
  }

  /// Verify OTP - validates the code and returns User with tokens
  Future<User> verifyOtp(String email, String code) async {
    try {
      _logger.info('Verifying OTP for: $email');

      final result = await _graphql.mutate(
        AuthQueries.verifyOtp,
        variables: {
          'input': {
            'email': email,
            'code': code,
          },
        },
      );

      if (result.hasException || result.data == null) {
        final errorMsg = result.exception?.graphqlErrors.firstOrNull?.message ??
            'Verification failed';
        throw Exception(errorMsg);
      }

      final data = result.data!['Auth_Otp_VerifyOtp'];
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'Verification failed');
      }

      final tokens = data['tokens'];
      final accessToken = tokens['accessToken'] as String;
      final refreshToken = tokens['refreshToken'] as String;

      // Update GraphQL client with new token
      _graphql.updateToken(accessToken);

      // Fetch user profile
      final user = await _fetchAndSaveUser(accessToken, refreshToken);

      _logger.info('OTP verification successful for: ${user.email}');
      return user;
    } catch (e, stackTrace) {
      _logger.error('OTP verification failed', e, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // SHARED AUTH HELPERS
  // ============================================================================

  /// Fetch user profile and save to storage
  Future<User> _fetchAndSaveUser(String accessToken, String refreshToken) async {
    final profileResult = await _graphql.query(AuthQueries.getMyProfile);

    if (profileResult.hasException || profileResult.data == null) {
      // Create minimal user from tokens
      final user = User(
        id: 'unknown',
        email: 'unknown',
        name: 'Unknown',
        token: accessToken,
        refreshToken: refreshToken,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
      await _storage.saveUser(user);
      return user;
    }

    final profile = profileResult.data!['Employee_GetMyProfile'];
    final user = User.fromGraphqlProfile(profile, accessToken, refreshToken);
    await _storage.saveUser(user);
    return user;
  }

  // ============================================================================
  // TOKEN REFRESH
  // ============================================================================

  /// Refresh the access token using the refresh token
  /// Returns true on success. Coordinates to prevent concurrent refreshes.
  Future<bool> refreshAccessToken() async {
    // If already refreshing, wait for the current operation
    if (_isRefreshing && _refreshCompleter != null) {
      _logger.info('Token refresh already in progress, waiting...');
      return _refreshCompleter!.future;
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<bool>();

    try {
      final currentUser = _storage.getCurrentUser();
      if (currentUser == null || currentUser.refreshToken == null) {
        throw Exception('No refresh token available');
      }

      _logger.info('Refreshing access token...');

      final result = await _graphql.mutate(
        AuthQueries.refreshTokens,
        variables: {
          'input': {
            'refreshToken': currentUser.refreshToken,
          },
        },
      );

      if (result.hasException || result.data == null) {
        final errorMsg = result.exception?.graphqlErrors.firstOrNull?.message ??
            'Token refresh failed';
        _logger.error('Token refresh failed: $errorMsg', null, null);
        _refreshCompleter!.complete(false);
        return false;
      }

      final data = result.data!['Auth_Session_RefreshTokens'];
      final newAccessToken = data['accessToken'] as String;
      final newRefreshToken = data['refreshToken'] as String;

      // Update stored user with new tokens
      final updatedUser = currentUser.copyWith(
        token: newAccessToken,
        refreshToken: newRefreshToken,
      );
      await _storage.saveUser(updatedUser);

      // Update GraphQL client
      _graphql.updateToken(newAccessToken);

      _logger.info('Token refresh successful');
      _tokenRefreshedController.add(null);
      _refreshCompleter!.complete(true);
      return true;
    } catch (e, stackTrace) {
      _logger.error('Token refresh failed', e, stackTrace);
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }

  // ============================================================================
  // LOGOUT
  // ============================================================================

  /// Logout via API
  Future<void> logout() async {
    try {
      _logger.info('Logging out user');

      final currentUser = _storage.getCurrentUser();
      if (currentUser?.token != null) {
        try {
          await _graphql.mutate(AuthQueries.logout);
          _logger.info('GraphQL logout successful');
        } catch (e) {
          _logger.warning('GraphQL logout failed, clearing local data: $e');
        }
      }

      // Always clear local data and reset client
      await _storage.clearUser();
      _graphql.reset();
      _logger.info('Logout successful');
    } catch (e, stackTrace) {
      _logger.error('Logout failed', e, stackTrace);
      rethrow;
    }
  }

  /// Force logout - clears local data without calling API
  Future<void> forceLogout() async {
    try {
      _logger.info('Force logging out user (token expired)');
      await _storage.clearUser();
      _graphql.reset();
      _forceLogoutController.add(null);
      _logger.info('Force logout complete');
    } catch (e, stackTrace) {
      _logger.error('Force logout failed', e, stackTrace);
      await _storage.clearUser();
      _graphql.reset();
      _forceLogoutController.add(null);
    }
  }

  // ============================================================================
  // PROFILE SYNC
  // ============================================================================

  /// Fetch user profile from API and update local storage
  Future<void> syncUserProfile() async {
    try {
      final currentUser = _storage.getCurrentUser();
      if (currentUser == null || currentUser.token == null) {
        _logger.warning('Cannot sync profile: no user or token');
        return;
      }

      _logger.info('Syncing user profile from GraphQL...');

      final result = await _graphql.query(AuthQueries.getMyProfile);

      if (result.hasException || result.data == null) {
        if (result.exception != null && _graphql.isAuthError(result.exception)) {
          // Try token refresh
          final refreshed = await refreshAccessToken();
          if (refreshed) {
            await syncUserProfile();
          } else {
            _logger.warning('Token refresh failed during profile sync, forcing logout');
            await forceLogout();
          }
          return;
        }
        _logger.warning('Failed to sync profile: ${result.exception}');
        return;
      }

      final profile = result.data!['Employee_GetMyProfile'];
      final updatedUser = User.fromGraphqlProfile(
        profile,
        currentUser.token!,
        currentUser.refreshToken,
      );
      await _storage.saveUser(updatedUser);
      _logger.info('User profile synced: ${updatedUser.name}');
    } catch (e, stackTrace) {
      _logger.error('Error syncing user profile', e, stackTrace);
    }
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  /// Get current user from storage
  User? getCurrentUser() {
    try {
      return _storage.getCurrentUser();
    } catch (e, stackTrace) {
      _logger.error('Failed to get current user', e, stackTrace);
      return null;
    }
  }

  /// Check if user is logged in
  bool isLoggedIn() {
    return getCurrentUser() != null;
  }

  /// Dispose resources
  void dispose() {
    _forceLogoutController.close();
    _tokenRefreshedController.close();
  }
}
