import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/window_service.dart';
import '../widgets/window_controls.dart';
import 'otp_verification_screen.dart';

/// Email domain for autocomplete suggestion
const List<String> _emailDomains = [
  '@ssarchitects.com',
];

class EmailEntryScreen extends ConsumerStatefulWidget {
  const EmailEntryScreen({super.key});

  @override
  ConsumerState<EmailEntryScreen> createState() => _EmailEntryScreenState();
}

class _EmailEntryScreenState extends ConsumerState<EmailEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _windowService = WindowService();
  bool _isLoading = false;
  bool _showEmailSuggestions = false;

  @override
  void initState() {
    super.initState();
    _windowService.setEmailEntryWindowSize();
    _emailController.addListener(_onEmailChanged);
    _emailFocusNode.addListener(_onEmailFocusChanged);
  }

  @override
  void dispose() {
    _emailController.removeListener(_onEmailChanged);
    _emailFocusNode.removeListener(_onEmailFocusChanged);
    _emailController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  void _onEmailChanged() {
    final text = _emailController.text;
    final hasAtSymbol = text.contains('@');
    final hasText = text.isNotEmpty;

    setState(() {
      if (hasText && !hasAtSymbol) {
        _showEmailSuggestions = true;
      } else if (hasAtSymbol) {
        final atIndex = text.indexOf('@');
        final domain = text.substring(atIndex);
        final matchingDomains = _emailDomains.where((d) =>
            d.toLowerCase().startsWith(domain.toLowerCase()) &&
            d.toLowerCase() != domain.toLowerCase());
        _showEmailSuggestions = matchingDomains.isNotEmpty;
      } else {
        _showEmailSuggestions = false;
      }
    });
  }

  void _onEmailFocusChanged() {
    if (!_emailFocusNode.hasFocus) {
      setState(() {
        _showEmailSuggestions = false;
      });
    } else {
      if (_emailController.text.isNotEmpty) {
        _emailController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _emailController.text.length,
        );
      }
      _onEmailChanged();
    }
  }

  void _selectEmailDomain(String domain) {
    final text = _emailController.text;
    final atIndex = text.indexOf('@');

    String newEmail;
    if (atIndex >= 0) {
      newEmail = text.substring(0, atIndex) + domain;
    } else {
      newEmail = text + domain;
    }

    _emailController.text = newEmail;
    _emailController.selection = TextSelection.fromPosition(
      TextPosition(offset: newEmail.length),
    );
    setState(() {
      _showEmailSuggestions = false;
    });
  }

  List<String> _getFilteredDomains() {
    final text = _emailController.text;
    final atIndex = text.indexOf('@');

    if (atIndex >= 0) {
      final partialDomain = text.substring(atIndex).toLowerCase();
      return _emailDomains
          .where((d) =>
              d.toLowerCase().startsWith(partialDomain) &&
              d.toLowerCase() != partialDomain)
          .toList();
    }

    return _emailDomains;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  Future<void> _handleSignIn() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();

    setState(() => _isLoading = true);

    try {
      await ref.read(currentUserProvider.notifier).requestOtp(email);

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => OTPVerificationScreen(email: email),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      String errorMessage = 'Failed to send verification code';
      if (e is Exception) {
        final msg = e.toString().replaceFirst('Exception: ', '').toLowerCase();
        if (msg.contains('network') || msg.contains('socket') || msg.contains('connection')) {
          errorMessage = 'Please check your internet connection and try again.';
        } else if (msg.contains('timeout')) {
          errorMessage = 'The request timed out. Please try again.';
        } else if (msg.contains('not found') || msg.contains('no account')) {
          errorMessage = 'No account found with this email address.';
        } else if (msg.contains('wait') || msg.contains('rate limit')) {
          errorMessage = 'Too many attempts. Please wait a moment and try again.';
        } else {
          errorMessage = e.toString().replaceFirst('Exception: ', '');
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleBack() {
    _windowService.setAuthWindowSize();
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
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
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

                        const SizedBox(height: 24),

                        // Title
                        const Text(
                          'Sign in',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Email field with suggestions
                        _buildEmailFieldWithSuggestions(),

                        const SizedBox(height: 32),

                        // Log in button
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleSignIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
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
                                    'Log in',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
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

  Widget _buildEmailFieldWithSuggestions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email address',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _emailController,
          focusNode: _emailFocusNode,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(fontSize: 16, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Your email',
            hintStyle: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Colors.white,
                width: 1,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Colors.red,
                width: 1,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Colors.red,
                width: 2,
              ),
            ),
          ),
          validator: _validateEmail,
          onFieldSubmitted: (_) => _handleSignIn(),
        ),
        // Email domain suggestions
        if (_showEmailSuggestions) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _getFilteredDomains().map((domain) {
              final text = _emailController.text;
              final atIndex = text.indexOf('@');
              final prefix = atIndex >= 0 ? text.substring(0, atIndex) : text;

              return GestureDetector(
                onTap: () => _selectEmailDomain(domain),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '$prefix$domain',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
