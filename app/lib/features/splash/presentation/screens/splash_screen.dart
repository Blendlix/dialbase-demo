import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dialabsetest/core/theme/app_colors.dart';
import 'package:dialabsetest/features/auth/data/auth_repository.dart';
import 'package:dialabsetest/features/auth/data/auth_session.dart';
import 'package:dialabsetest/features/auth/presentation/screens/login_screen.dart';
import 'package:dialabsetest/features/main/presentation/screens/main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _controller.forward();

    _timer = Timer(const Duration(milliseconds: 1800), _openApp);
  }

  Future<void> _openApp() async {
    AuthSession? session;
    Object? restoreError;
    try {
      session = await authRepository.restoreSession();
    } catch (error) {
      restoreError = error;
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => session == null
            ? LoginScreen(infoMessage: restoreError?.toString())
          : MainShell(session: session),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: const Text(
            'dialabse',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
