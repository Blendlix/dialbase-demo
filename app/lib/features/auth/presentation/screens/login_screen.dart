import 'package:flutter/material.dart';

import 'package:dialabsetest/core/theme/app_colors.dart';
import 'package:dialabsetest/features/auth/data/auth_repository.dart';
import 'package:dialabsetest/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:dialabsetest/features/auth/presentation/screens/signup_screen.dart';
import 'package:dialabsetest/features/auth/presentation/widgets/auth_action_button.dart';
import 'package:dialabsetest/features/auth/presentation/widgets/auth_page_shell.dart';
import 'package:dialabsetest/features/auth/presentation/widgets/auth_text_field.dart';
import 'package:dialabsetest/features/main/presentation/screens/main_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialEmail, this.infoMessage});

  final String? initialEmail;
  final String? infoMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;
  bool _verificationPending = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _verificationPending = false;
    });
    try {
      final session = await authRepository.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) {
        return;
      }
      if (!session.isEmailVerified) {
        setState(() {
          _verificationPending = true;
          _errorMessage = 'Please verify your email before continuing.';
        });
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MainShell(session: session),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendVerification() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await authRepository.resendVerification();
      if (mounted) {
        setState(() => _errorMessage = 'Verification email sent.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageShell(
      title: 'Welcome back',
      subtitle: 'Sign in to continue to your account.',
      form: Column(
        children: [
          AuthTextField(
            controller: _emailController,
            hintText: 'Email address',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.email_outlined,
          ),
          const SizedBox(height: 16),
          AuthTextField(
            controller: _passwordController,
            hintText: 'Password',
            obscureText: true,
            prefixIcon: Icons.lock_outline,
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ForgotPasswordScreen(),
                  ),
                );
              },
              child: const Text(
                'Forgot password?',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AuthActionButton(
            label: _isLoading ? 'Please wait...' : 'Login',
            onPressed: _isLoading ? () {} : _signIn,
          ),
          if (widget.infoMessage != null || _errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? widget.infoMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _verificationPending || widget.infoMessage != null
                    ? const Color(0xFF52655F)
                    : Colors.red.shade700,
              ),
            ),
          ],
          if (_verificationPending) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: _isLoading ? null : _resendVerification,
              child: const Text('Resend verification email'),
            ),
          ],
        ],
      ),
      footerText: 'Don’t have an account?',
      footerActionText: 'Create one',
      onFooterTap: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const SignupScreen()),
        );
      },
    );
  }
}
