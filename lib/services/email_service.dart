import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:logger/logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Service for sending emails via AWS SES SMTP
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  final Logger _logger = Logger();

  late final SmtpServer _smtpServer;
  late final String _fromEmail;
  late final String _fromName;

  /// Initializes the email service with credentials from .env
  void initialize() {
    final smtpHost = dotenv.env['SMTP_HOST'] ?? '';
    final smtpPort = int.tryParse(dotenv.env['SMTP_PORT'] ?? '587') ?? 587;
    final smtpUsername = dotenv.env['SMTP_USERNAME'] ?? '';
    final smtpPassword = dotenv.env['SMTP_PASSWORD'] ?? '';
    _fromEmail = dotenv.env['FROM_EMAIL'] ?? 'noreply@ssarchitects.ae';
    _fromName = dotenv.env['FROM_NAME'] ?? 'Silverstone Architects';

    // Debug logging
    _logger.d('SMTP_HOST: ${smtpHost.isEmpty ? "EMPTY" : smtpHost}');
    _logger.d('SMTP_PORT: $smtpPort');
    _logger.d('SMTP_USERNAME: ${smtpUsername.isEmpty ? "EMPTY" : "${smtpUsername.substring(0, 5)}..."}');
    _logger.d('SMTP_PASSWORD: ${smtpPassword.isEmpty ? "EMPTY" : "***${smtpPassword.length} chars***"}');
    _logger.d('FROM_EMAIL: $_fromEmail');

    if (smtpHost.isEmpty || smtpUsername.isEmpty || smtpPassword.isEmpty) {
      _logger.e('SMTP credentials not found in .env file');
      throw EmailException('SMTP configuration is missing');
    }

    _smtpServer = SmtpServer(
      smtpHost,
      port: smtpPort,
      username: smtpUsername,
      password: smtpPassword,
      ssl: false, // Use STARTTLS instead of SSL
      allowInsecure: false,
    );

    _logger.i('Email service initialized with SMTP server: $smtpHost:$smtpPort');
  }

  /// Sends an OTP code to the specified email address
  /// Returns true if email was sent successfully
  /// Throws EmailException on failure
  Future<bool> sendOTPEmail(String toEmail, String otpCode) async {
    try {
      _logger.i('Sending OTP email to $toEmail');

      final message = Message()
        ..from = Address(_fromEmail, _fromName)
        ..recipients.add(toEmail)
        ..subject = 'Your Login Code - Silverstone Architects'
        ..html = _buildOTPEmailHtml(otpCode);

      final sendReport = await send(message, _smtpServer);

      _logger.i('OTP email sent successfully to $toEmail: ${sendReport.toString()}');
      return true;
    } on MailerException catch (e) {
      _logger.e('Failed to send OTP email to $toEmail: ${e.message}');

      // Check for specific error types
      if (e.message.contains('authentication') || e.message.contains('credentials')) {
        throw EmailException('Email authentication failed. Please contact support.');
      } else if (e.message.contains('network') || e.message.contains('connection')) {
        throw EmailException('Network error. Please check your internet connection.');
      } else {
        throw EmailException('Failed to send email. Please try again later.');
      }
    } catch (e) {
      _logger.e('Unexpected error sending OTP email to $toEmail: $e');
      throw EmailException('Failed to send email. Please try again later.');
    }
  }

  /// Builds the HTML content for the OTP email
  String _buildOTPEmailHtml(String otpCode) {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Your Login Code</title>
</head>
<body style="margin: 0; padding: 0; font-family: Arial, sans-serif; background-color: #f4f4f4;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #f4f4f4; padding: 20px;">
        <tr>
            <td align="center">
                <table width="600" cellpadding="0" cellspacing="0" border="0" style="background-color: #ffffff; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
                    <!-- Header -->
                    <tr>
                        <td style="background-color: #2196F3; padding: 30px; text-align: center; border-radius: 8px 8px 0 0;">
                            <h1 style="color: #ffffff; margin: 0; font-size: 24px;">Silverstone Architects</h1>
                        </td>
                    </tr>

                    <!-- Content -->
                    <tr>
                        <td style="padding: 40px 30px;">
                            <h2 style="color: #333333; margin: 0 0 20px 0; font-size: 20px;">Your Login Code</h2>
                            <p style="color: #666666; line-height: 1.6; margin: 0 0 30px 0;">
                                You requested a login code for your Silverstone Architects account.
                                Use the code below to complete your login:
                            </p>

                            <!-- OTP Code Box -->
                            <table width="100%" cellpadding="0" cellspacing="0" border="0">
                                <tr>
                                    <td align="center" style="padding: 20px 0;">
                                        <div style="background-color: #f8f9fa; border: 2px solid #2196F3; border-radius: 8px; padding: 20px; display: inline-block;">
                                            <span style="font-size: 32px; font-weight: bold; color: #2196F3; letter-spacing: 8px; font-family: 'Courier New', monospace;">
                                                $otpCode
                                            </span>
                                        </div>
                                    </td>
                                </tr>
                            </table>

                            <!-- Expiration Notice -->
                            <p style="color: #666666; line-height: 1.6; margin: 30px 0 0 0; font-size: 14px;">
                                <strong>⏱️ This code will expire in 5 minutes.</strong>
                            </p>

                            <!-- Security Warning -->
                            <div style="background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin-top: 30px; border-radius: 4px;">
                                <p style="color: #856404; margin: 0; font-size: 14px;">
                                    <strong>🔒 Security Notice:</strong><br>
                                    Never share this code with anyone. Our team will never ask for your login code.
                                    If you didn't request this code, please ignore this email.
                                </p>
                            </div>
                        </td>
                    </tr>

                    <!-- Footer -->
                    <tr>
                        <td style="background-color: #f8f9fa; padding: 20px 30px; text-align: center; border-radius: 0 0 8px 8px; border-top: 1px solid #e0e0e0;">
                            <p style="color: #999999; margin: 0; font-size: 12px;">
                                This is an automated email from Silverstone Architects Time Tracker.<br>
                                Please do not reply to this email.
                            </p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
    ''';
  }
}

/// Custom exception for email-related errors
class EmailException implements Exception {
  final String message;

  EmailException(this.message);

  @override
  String toString() => message;
}
