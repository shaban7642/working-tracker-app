import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
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
  final _windowService = WindowService();
  final _devEmailController = TextEditingController();
  bool _isLoading = false;
  bool _isWaitingForSSO = false;

  @override
  void initState() {
    super.initState();
    _windowService.setAuthWindowSize();
  }

  Future<void> _handleSSOLogin() async {
    setState(() {
      _isLoading = true;
      _isWaitingForSSO = true;
    });

    // Resize window for waiting state
    await _windowService.setOtpWindowSize();

    try {
      // SSO login - opens browser and waits for callback
      await ref.read(currentUserProvider.notifier).loginWithSSO();

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

      String errorMessage = 'Login failed';
      if (e is Exception) {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      }

      // Resize window back
      _windowService.setAuthWindowSize();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 4),
        ),
      );

      setState(() {
        _isLoading = false;
        _isWaitingForSSO = false;
      });
    }
  }

  Future<void> _handleDevLogin() async {
    final email = _devEmailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(currentUserProvider.notifier).devLogin(email);

      if (!mounted) return;

      await StorageService().clearProjects();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
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

      setState(() => _isLoading = false);
    }
  }

  void _cancelSSO() {
    _windowService.setAuthWindowSize();
    setState(() {
      _isLoading = false;
      _isWaitingForSSO = false;
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
            // Main content - fills available space
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24.0, 40.0, 24.0, 24.0),
                child: _isWaitingForSSO ? _buildWaitingForm() : _buildLoginForm(),
              ),
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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top section - Title
          Text(
            'Welcome',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Sign in to continue',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),

          const SizedBox(height: 40),

          // SSO Sign In button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleSSOLogin,
              icon: const Icon(Icons.login, size: 20),
              label: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Sign In with SSO',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),

          // Dev login section (debug mode only)
          if (kDebugMode) ...[
            const SizedBox(height: 24),
            Divider(color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 8),
            Text(
              'Dev Login',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textHint,
                  ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: TextField(
                controller: _devEmailController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Email or Employee ID',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onSubmitted: (_) => _handleDevLogin(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleDevLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: const Text('Dev Login', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWaitingForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top section - Back button and Title
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.textSecondary),
            onPressed: _cancelSSO,
            tooltip: 'Cancel',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Signing In',
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Complete the login in your browser',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),

        // Spacer pushes content to middle
        const Spacer(),

        // Waiting indicator
        Center(
          child: Column(
            children: [
              const SizedBox(
                height: 48,
                width: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Waiting for browser login...',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'A browser window has been opened.\nSign in there to continue.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textHint,
                    ),
              ),
            ],
          ),
        ),

        // Spacer pushes button to bottom
        const Spacer(),

        // Cancel button
        SizedBox(
          height: 50,
          child: OutlinedButton(
            onPressed: _cancelSSO,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
