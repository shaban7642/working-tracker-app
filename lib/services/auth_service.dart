import 'dart:math';
import '../models/user.dart';
import 'storage_service.dart';
import 'logger_service.dart';
import 'otp_service.dart';
import 'email_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final _storage = StorageService();
  final _logger = LoggerService();
  final _otpService = OTPService();
  final _emailService = EmailService();

  AuthService._internal();

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

  /// Validates email format
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  /// Generates a secure random token
  String _generateSecureToken() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return values.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  // Logout
  Future<void> logout() async {
    try {
      _logger.info('Logging out user');
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
