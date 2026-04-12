import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../services/window_service.dart';
import '../widgets/otp_input.dart';
import '../widgets/window_controls.dart';
import 'dashboard_screen.dart';

class OTPVerificationScreen extends ConsumerStatefulWidget {
  final String email;

  const OTPVerificationScreen({super.key, required this.email});

  @override
  ConsumerState<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends ConsumerState<OTPVerificationScreen> {
  final GlobalKey<OtpInputState> _otpKey = GlobalKey();
  final _windowService = WindowService();
  String _code = '';
  bool _isVerifying = false;
  bool _hasError = false;
  String? _errorMessage;
  int _resendCountdown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _windowService.setOtpWindowSize();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _resendCountdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_resendCountdown > 0) {
            _resendCountdown--;
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  String _formatCountdown() {
    int minutes = _resendCountdown ~/ 60;
    int seconds = _resendCountdown % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _handleVerify() async {
    if (_code.length != 6 || _isVerifying) return;

    setState(() {
      _isVerifying = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      await ref.read(currentUserProvider.notifier).verifyOtp(widget.email, _code);

      if (!mounted) return;

      await StorageService().clearProjects();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      String errorMsg = 'Wrong code, please try again';
      if (e is Exception) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        if (msg.toLowerCase().contains('expired')) {
          errorMsg = 'Code expired. Please request a new one.';
        } else if (msg.toLowerCase().contains('network') || msg.toLowerCase().contains('connection')) {
          errorMsg = 'Please check your internet connection.';
        } else if (msg.isNotEmpty) {
          errorMsg = msg;
        }
      }

      setState(() {
        _isVerifying = false;
        _hasError = true;
        _errorMessage = errorMsg;
      });
      _otpKey.currentState?.clearCode();
    }
  }

  Future<void> _handleResendCode() async {
    if (_resendCountdown > 0) return;

    setState(() {
      _hasError = false;
      _errorMessage = null;
    });

    try {
      await ref.read(currentUserProvider.notifier).requestOtp(widget.email);

      if (!mounted) return;

      _otpKey.currentState?.clearCode();
      _startCountdown();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A new code has been sent to ${widget.email}'),
          backgroundColor: AppTheme.successColor,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _handleBack() {
    _windowService.setEmailEntryWindowSize();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: AppTheme.backgroundDecoration,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24.0, 40.0, 24.0, 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Back button
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: _handleBack,
                          icon: const Icon(Icons.arrow_back, size: 18, color: Colors.white),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Title
                    const Text(
                      'Enter code',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Subtitle with email
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.7),
                          height: 1.5,
                        ),
                        children: [
                          const TextSpan(text: "We've sent a verification code to "),
                          TextSpan(
                            text: widget.email,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // OTP Input
                    OtpInput(
                      key: _otpKey,
                      length: 6,
                      hasError: _hasError,
                      onChanged: (code) {
                        setState(() {
                          _code = code;
                          if (_hasError && code.length < 6) {
                            _hasError = false;
                            _errorMessage = null;
                          }
                        });
                      },
                      onCompleted: (code) {
                        setState(() {
                          _code = code;
                        });
                        _handleVerify();
                      },
                    ),

                    const SizedBox(height: 12),

                    // Error message
                    if (_hasError)
                      Center(
                        child: Text(
                          _errorMessage ?? 'Wrong code, please try again',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.red,
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Verify button (shown when 6 digits entered)
                    if (_code.length == 6)
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isVerifying ? null : _handleVerify,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                            disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
                          ),
                          child: _isVerifying
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : Text(
                                  _hasError ? 'Retry' : 'Verify',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),

                    const Spacer(),

                    // Resend section
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          Text(
                            "Didn't receive a code?  ",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                          GestureDetector(
                            onTap: _resendCountdown == 0 && !_isVerifying
                                ? _handleResendCode
                                : null,
                            child: Text(
                              _resendCountdown > 0
                                  ? 'Resend in ${_formatCountdown()}'
                                  : 'Resend',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _resendCountdown == 0 && !_isVerifying
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(
              top: 8,
              right: 8,
              child: WindowControls(),
            ),
          ],
        ),
      ),
    );
  }
}
