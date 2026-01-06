import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import '../services/storage_service.dart';
import '../services/window_service.dart';
import '../widgets/window_controls.dart';
import 'dashboard_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _windowService = WindowService();
  bool _isLoading = false;

  // 2FA login state
  bool _isOtpStep = false;
  String? _loginSessionToken;
  String? _email;

  @override
  void initState() {
    super.initState();
    _windowService.setAuthWindowSize();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final email = _emailController.text.trim();

    try {
      // Step 1: Initiate login (sends OTP to email)
      final sessionToken = await ref.read(currentUserProvider.notifier).initiateLogin(email);

      if (!mounted) return;

      // Resize window for OTP step (taller to fit content)
      await _windowService.setOtpWindowSize();

      if (!mounted) return;

      // Move to OTP step
      setState(() {
        _isOtpStep = true;
        _loginSessionToken = sessionToken;
        _email = email;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP sent to your email'),
          backgroundColor: AppTheme.successColor,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      String errorMessage = 'Login failed';
      if (e is Exception) {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 4),
        ),
      );

      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleVerifyOTP() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 6-digit OTP'),
          backgroundColor: AppTheme.errorColor,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Step 2: Verify OTP and complete login
      await ref.read(currentUserProvider.notifier).verifyLoginOTP(_loginSessionToken!, otp);

      if (!mounted) return;

      // Clear cached projects to ensure fresh data on login
      await StorageService().clearProjects();

      if (!mounted) return;

      // Navigate to dashboard
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const DashboardScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      String errorMessage = 'OTP verification failed';
      if (e is Exception) {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 4),
        ),
      );

      setState(() {
        _isLoading = false;
      });
    }
  }

  void _goBackToEmailStep() {
    // Resize window back to login size
    _windowService.setAuthWindowSize();

    setState(() {
      _isOtpStep = false;
      _loginSessionToken = null;
      _otpController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: AppTheme.backgroundDecoration,
        child: Stack(
          children: [
            SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24.0, 40.0, 24.0, 24.0),
            child: _isOtpStep ? _buildOtpForm() : _buildLoginForm(),
          ),
          // Window control buttons (minimize, close)
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

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Text(
            'Welcome',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Subtitle
          Text(
            'Sign in to continue',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Email Field
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            enabled: !_isLoading,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Email Address',
              hintText: 'your.email@example.com',
              hintStyle: const TextStyle(
                color: AppTheme.textHint,
                fontSize: 14,
              ),
              prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white, width: 2),
              ),
              filled: true,
              fillColor: AppTheme.elevatedSurfaceColor,
            ),
            validator: Validators.validateEmail,
            onFieldSubmitted: (_) {
              if (!_isLoading) {
                _handleLogin();
              }
            },
          ),
          const SizedBox(height: 24),

          // Login Button
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Sign In',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Back button
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.textSecondary),
            onPressed: _isLoading ? null : _goBackToEmailStep,
            tooltip: 'Go back',
          ),
        ),
        const SizedBox(height: 8),

        // Title
        Text(
          'Verify OTP',
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        // Subtitle with email
        Text(
          'Enter the 6-digit code sent to',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          _email ?? '',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // OTP Field
        TextFormField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          enabled: !_isLoading,
          maxLength: 6,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 24,
            letterSpacing: 8,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: 'OTP Code',
            hintText: '000000',
            counterText: '',
            hintStyle: const TextStyle(
              color: AppTheme.textHint,
              fontSize: 24,
              letterSpacing: 8,
            ),
            prefixIcon: const Icon(Icons.pin_outlined, color: AppTheme.textSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white, width: 2),
            ),
            filled: true,
            fillColor: AppTheme.elevatedSurfaceColor,
          ),
          onFieldSubmitted: (_) {
            if (!_isLoading) {
              _handleVerifyOTP();
            }
          },
        ),
        const SizedBox(height: 24),

        // Verify Button
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleVerifyOTP,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Text(
                    'Verify & Sign In',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),

        // Resend OTP link
        TextButton(
          onPressed: _isLoading ? null : () {
            _goBackToEmailStep();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please sign in again to receive a new OTP'),
                duration: Duration(seconds: 3),
              ),
            );
          },
          child: Text(
            'Didn\'t receive the code? Try again',
            style: TextStyle(
              color: _isLoading ? AppTheme.textHint : Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
