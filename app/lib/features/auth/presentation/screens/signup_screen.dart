import 'package:flutter/material.dart';

import 'package:dialabsetest/features/auth/data/auth_repository.dart';
import 'package:dialabsetest/features/auth/presentation/screens/login_screen.dart';
import 'package:dialabsetest/features/auth/presentation/widgets/auth_action_button.dart';
import 'package:dialabsetest/features/auth/presentation/widgets/auth_page_shell.dart';
import 'package:dialabsetest/features/auth/presentation/widgets/auth_text_field.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    final password = _passwordController.text;
    if (password.length < 10 ||
        !RegExp('[a-z]').hasMatch(password) ||
        !RegExp('[A-Z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      setState(() {
        _errorMessage =
            'Use at least 10 characters, with uppercase and lowercase letters and a number.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await authRepository.register(
        name: _nameController.text,
        email: _emailController.text,
        password: password,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(
            initialEmail: _emailController.text.trim(),
            infoMessage: 'Account created. Check your email to verify it.',
          ),
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

  @override
  Widget build(BuildContext context) {
    return AuthPageShell(
      title: 'Create account',
      subtitle: 'Start your journey with dialabse today.',
      form: Column(
        children: [
          AuthTextField(
            controller: _nameController,
            hintText: 'Full name',
            prefixIcon: Icons.person_outline,
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 20),
          AuthActionButton(
            label: _isLoading ? 'Please wait...' : 'Create account',
            onPressed: _isLoading ? () {} : _createAccount,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade700),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {},
            child: const Text(
              'By continuing, you agree to terms and privacy policy',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF5E6A66),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
      footerText: 'Already have an account?',
      footerActionText: 'Login',
      onFooterTap: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        );
      },
    );
  }
}
