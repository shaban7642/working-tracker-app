import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import 'storage_service.dart';
import 'logger_service.dart';
import 'socket_service.dart';
// OTP-based auth commented out - now using API login
// import 'otp_service.dart';
// import 'email_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  static const String _baseUrl = 'https://api.ssapp.site/api/v1';

  final _storage = StorageService();
  final _logger = LoggerService();
  final _socketService = SocketService();
  // OTP-based auth commented out - now using API login
  // final _otpService = OTPService();
  // final _emailService = EmailService();

  AuthService._internal();

  /// Login with email and password via API
  /// Returns User object on success, throws on failure
  Future<User> loginWithEmailPassword(String email, String password) async {
    try {
      _logger.info('Logging in with email: $email');

      // Validate email format
      if (email.isEmpty || !_isValidEmail(email)) {
        throw Exception('Please enter a valid email address');
      }

      if (password.isEmpty || password.length < 6) {
        throw Exception('Password must be at least 6 characters');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && responseData['success'] == true) {
        final user = User.fromLoginResponse(responseData);
        await _storage.saveUser(user);
        _logger.info('Login successful for: $email');

        // Connect to Socket.IO for real-time updates
        try {
          await _socketService.connect();
          _logger.info('Socket.IO connected after login');
        } catch (e) {
          _logger.warning('Failed to connect Socket.IO after login: $e');
          // Don't fail login if socket connection fails
        }

        return user;
      } else {
        final message = responseData['message'] ?? 'Login failed';
        _logger.info('Login failed for $email: $message');
        throw Exception(message);
      }
    } catch (e, stackTrace) {
      _logger.error('Login failed', e, stackTrace);
      rethrow;
    }
  }

  /*
  // ============ OTP-based authentication (commented out) ============

  /// Sends OTP code to the user's email
  /// Returns true if email was sent successfully
  Future<bool> sendOTP(String email) async {
    try {
      _logger.info('Sending OTP to: $email');

      // Validate email format
      if (email.isEmpty || !_isValidEmail(email)) {
        throw Exception('Please enter a valid email address');
      }

      // Generate OTP code
      final otpCode = _otpService.generateOTP(email);

      // Send email with OTP
      await _emailService.sendOTPEmail(email, otpCode);

      _logger.info('OTP sent successfully to: $email');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to send OTP', e, stackTrace);
      rethrow;
    }
  }

  /// Verifies OTP and logs in the user
  /// Returns User object on success, null on failure
  Future<User?> verifyOTPAndLogin(String email, String otp) async {
    try {
      _logger.info('Verifying OTP for: $email');

      // Verify OTP
      final isValid = _otpService.verifyOTP(email, otp);

      if (!isValid) {
        _logger.info('Invalid OTP for: $email');
        return null;
      }

      // Create user with secure token
      final user = User(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        email: email,
        name: email.split('@')[0],
        token: _generateSecureToken(),
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );

      // Save user to storage
      await _storage.saveUser(user);

      _logger.info('Login successful for: $email');
      return user;
    } catch (e, stackTrace) {
      _logger.error('OTP verification failed', e, stackTrace);
      rethrow;
    }
  }

  /// Generates a secure random token
  String _generateSecureToken() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return values.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  // ============ End OTP-based authentication ============
  */

  /// Validates email format
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  // Logout via API
  Future<void> logout() async {
    try {
      _logger.info('Logging out user');

      // Disconnect Socket.IO first
      _socketService.disconnect();
      _logger.info('Socket.IO disconnected on logout');

      // Get current user for tokens
      final currentUser = _storage.getCurrentUser();

      if (currentUser != null && currentUser.refreshToken != null && currentUser.token != null) {
        try {
          // Call logout API
          final response = await http.post(
            Uri.parse('$_baseUrl/auth/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${currentUser.token}',
            },
            body: jsonEncode({
              'refreshToken': currentUser.refreshToken,
            }),
          );

          if (response.statusCode == 200) {
            _logger.info('API logout successful');
          } else {
            _logger.warning('API logout returned status ${response.statusCode}, clearing local data anyway');
          }
        } catch (e) {
          // If API call fails, still clear local data
          _logger.warning('API logout failed, clearing local data: $e');
        }
      }

      // Always clear local user data
      await _storage.clearUser();
      _logger.info('Logout successful');
    } catch (e, stackTrace) {
      _logger.error('Logout failed', e, stackTrace);
      rethrow;
    }
  }

  // Get current user
  User? getCurrentUser() {
    try {
      return _storage.getCurrentUser();
    } catch (e, stackTrace) {
      _logger.error('Failed to get current user', e, stackTrace);
      return null;
    }
  }

  // Check if user is logged in
  bool isLoggedIn() {
    return getCurrentUser() != null;
  }

}
