import 'package:flutter/material.dart';

import 'package:dialabsetest/core/theme/app_theme.dart';
import 'package:dialabsetest/features/splash/presentation/screens/splash_screen.dart';

class DialabseApp extends StatelessWidget {
  const DialabseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'dialbase',
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
