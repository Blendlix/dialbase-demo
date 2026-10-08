import 'package:flutter/material.dart';

import 'package:dialabsetest/core/theme/app_colors.dart';
import 'package:dialabsetest/features/auth/data/auth_repository.dart';
import 'package:dialabsetest/features/auth/presentation/screens/login_screen.dart';
import 'package:dialabsetest/features/auth/presentation/widgets/auth_action_button.dart';
import 'package:dialabsetest/features/auth/presentation/widgets/auth_page_shell.dart';
import 'package:dialabsetest/features/auth/presentation/widgets/auth_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  String? _message;
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    setState(() {
      _isLoading = true;
      _message = null;
      _errorMessage = null;
    });
    try {
      await authRepository.sendPasswordReset(_emailController.text);
      if (mounted) {
        setState(() {
          _message = 'If an account exists for that email, a reset link has been sent.';
        });
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
      title: 'Reset password',
      subtitle: 'Enter your email and we’ll send a reset link.',
      form: Column(
        children: [
          AuthTextField(
            controller: _emailController,
            hintText: 'Email address',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.email_outlined,
          ),
          const SizedBox(height: 20),
          AuthActionButton(
            label: _isLoading ? 'Please wait...' : 'Send reset link',
            onPressed: _isLoading ? () {} : _sendResetLink,
          ),
          if (_message != null || _errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _message ?? _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _errorMessage == null
                    ? const Color(0xFF52655F)
                    : Colors.red.shade700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text(
              'Back to login',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      footerText: '',
      footerActionText: '',
      onFooterTap: () {},
    );
  }
}
