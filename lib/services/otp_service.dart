import 'dart:math';
import 'package:logger/logger.dart';

/// Service for managing OTP (One-Time Password) generation, verification, and rate limiting
class OTPService {
  static final OTPService _instance =
      OTPService._internal();
  factory OTPService() => _instance;
  OTPService._internal();

  final Logger _logger = Logger();

  // Storage for OTP data: email -> OTPData
  final Map<String, _OTPData> _otpStorage = {};

  // Rate limiting storage: email -> List of request timestamps
  final Map<String, List<DateTime>> _rateLimitStorage = {};

  // Configuration constants

  static const int _otpExpirationMinutes = 5;
  static const int _resendCooldownSeconds = 60;
  static const int _maxRequestsPerWindow = 3;
  static const int _rateLimitWindowMinutes = 10;

  /// Generates a new 6-digit OTP code for the given email
  /// Returns the generated OTP code
  /// Throws exception if rate limit is exceeded
  String generateOTP(String email) {
    email = email.toLowerCase().trim();

    // Check rate limiting
    if (!_checkRateLimit(email)) {
      final remainingMinutes =
          _getRateLimitRemainingMinutes(email);
      throw OTPException(
        'Too many OTP requests. Please try again in $remainingMinutes minutes.',
      );
    }

    // Generate random 6-digit code
    final random = Random.secure();
    final code = (random.nextInt(900000) + 100000)
        .toString();

    // Store OTP with timestamp
    _otpStorage[email] = _OTPData(
      code: code,
      generatedAt: DateTime.now(),
      attempts: 0,
    );

    // Record request for rate limiting
    _recordRequest(email);

    _logger.i(
      'OTP generated for $email (expires in $_otpExpirationMinutes minutes)',
    );

    // Clean up expired OTPs
    _cleanupExpiredOTPs();

    return code;
  }

  /// Verifies the OTP code for the given email
  /// Returns true if valid, false otherwise
  /// Clears the OTP from storage on successful verification
  bool verifyOTP(String email, String code) {
    email = email.toLowerCase().trim();
    code = code.trim();

    final otpData = _otpStorage[email];

    if (otpData == null) {
      _logger.w(
        'OTP verification failed: No OTP found for $email',
      );
      return false;
    }

    // Check if OTP has expired
    if (_isExpired(otpData.generatedAt)) {
      _logger.w(
        'OTP verification failed: OTP expired for $email',
      );
      _clearOTP(email);
      throw OTPException(
        'OTP has expired. Please request a new code.',
      );
    }

    // Increment attempt counter
    otpData.attempts++;

    // Check if code matches
    if (otpData.code == code) {
      _logger.i('OTP verified successfully for $email');
      _clearOTP(email);
      return true;
    }

    _logger.w(
      'OTP verification failed: Invalid code for $email (attempt ${otpData.attempts})',
    );

    // Clear OTP after 5 failed attempts
    if (otpData.attempts >= 5) {
      _logger.w(
        'OTP cleared due to too many failed attempts for $email',
      );
      _clearOTP(email);
      throw OTPException(
        'Too many failed attempts. Please request a new code.',
      );
    }

    return false;
  }

  /// Attempts to resend OTP to the given email
  /// Returns the new OTP code if successful
  /// Throws exception if cooldown period hasn't elapsed or rate limit exceeded
  String resendOTP(String email) {
    email = email.toLowerCase().trim();

    // Check if cooldown period has elapsed
    if (!canResendOTP(email)) {
      final remaining = getRemainingCooldown(email);
      throw OTPException(
        'Please wait $remaining seconds before requesting a new code.',
      );
    }

    // Generate new OTP
    return generateOTP(email);
  }

  /// Checks if a new OTP can be sent (cooldown period has elapsed)
  bool canResendOTP(String email) {
    email = email.toLowerCase().trim();
    final otpData = _otpStorage[email];

    if (otpData == null) {
      return true; // No existing OTP, can send
    }

    final secondsSinceGeneration = DateTime.now()
        .difference(otpData.generatedAt)
        .inSeconds;
    return secondsSinceGeneration >= _resendCooldownSeconds;
  }

  /// Returns remaining cooldown time in seconds
  /// Returns 0 if cooldown has elapsed
  int getRemainingCooldown(String email) {
    email = email.toLowerCase().trim();
    final otpData = _otpStorage[email];

    if (otpData == null) {
      return 0;
    }

    final secondsSinceGeneration = DateTime.now()
        .difference(otpData.generatedAt)
        .inSeconds;
    final remaining =
        _resendCooldownSeconds - secondsSinceGeneration;

    return remaining > 0 ? remaining : 0;
  }

  /// Returns remaining time until OTP expiration in seconds
  /// Returns 0 if expired
  int getRemainingExpirationTime(String email) {
    email = email.toLowerCase().trim();
    final otpData = _otpStorage[email];

    if (otpData == null) {
      return 0;
    }

    final secondsSinceGeneration = DateTime.now()
        .difference(otpData.generatedAt)
        .inSeconds;
    final expirationSeconds = _otpExpirationMinutes * 60;
    final remaining =
        expirationSeconds - secondsSinceGeneration;

    return remaining > 0 ? remaining : 0;
  }

  /// Checks if the OTP has expired based on generation timestamp
  bool _isExpired(DateTime generatedAt) {
    final now = DateTime.now();
    final difference = now.difference(generatedAt);
    return difference.inMinutes >= _otpExpirationMinutes;
  }

  /// Clears OTP data for the given email
  void _clearOTP(String email) {
    _otpStorage.remove(email);
    _logger.d('OTP cleared for $email');
  }

  /// Checks if the email has exceeded rate limit
  bool _checkRateLimit(String email) {
    final requests = _rateLimitStorage[email];

    if (requests == null || requests.isEmpty) {
      return true; // No requests yet, allow
    }

    final now = DateTime.now();
    final windowStart = now.subtract(
      Duration(minutes: _rateLimitWindowMinutes),
    );

    // Count requests within the time window
    final recentRequests = requests
        .where(
          (timestamp) => timestamp.isAfter(windowStart),
        )
        .toList();

    return recentRequests.length < _maxRequestsPerWindow;
  }

  /// Records an OTP request for rate limiting
  void _recordRequest(String email) {
    final now = DateTime.now();

    if (_rateLimitStorage[email] == null) {
      _rateLimitStorage[email] = [];
    }

    _rateLimitStorage[email]!.add(now);

    // Clean up old requests outside the window
    final windowStart = now.subtract(
      Duration(minutes: _rateLimitWindowMinutes),
    );
    _rateLimitStorage[email]!.removeWhere(
      (timestamp) => timestamp.isBefore(windowStart),
    );
  }

  /// Returns remaining minutes until rate limit resets
  int _getRateLimitRemainingMinutes(String email) {
    final requests = _rateLimitStorage[email];

    if (requests == null || requests.isEmpty) {
      return 0;
    }

    final now = DateTime.now();
    final oldestRequest = requests.first;
    final minutesSinceOldest = now
        .difference(oldestRequest)
        .inMinutes;
    final remaining =
        _rateLimitWindowMinutes - minutesSinceOldest;

    return remaining > 0 ? remaining : 0;
  }

  /// Cleans up expired OTPs from storage
  void _cleanupExpiredOTPs() {
    final expiredEmails = <String>[];

    _otpStorage.forEach((email, otpData) {
      if (_isExpired(otpData.generatedAt)) {
        expiredEmails.add(email);
      }
    });

    for (final email in expiredEmails) {
      _clearOTP(email);
    }

    if (expiredEmails.isNotEmpty) {
      _logger.d(
        'Cleaned up ${expiredEmails.length} expired OTPs',
      );
    }
  }

  /// Clears all OTP data (useful for testing)
  void clearAll() {
    _otpStorage.clear();
    _rateLimitStorage.clear();
    _logger.d('All OTP data cleared');
  }
}

/// Internal data structure for storing OTP information
class _OTPData {
  final String code;
  final DateTime generatedAt;
  int attempts;

  _OTPData({
    required this.code,
    required this.generatedAt,
    this.attempts = 0,
  });
}

/// Custom exception for OTP-related errors
class OTPException implements Exception {
  final String message;

  OTPException(this.message);

  @override
  String toString() => message;
}
