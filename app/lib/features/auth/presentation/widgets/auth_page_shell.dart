import 'package:flutter/material.dart';

import 'package:dialabsetest/core/theme/app_colors.dart';

class AuthPageShell extends StatelessWidget {
  const AuthPageShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.form,
    required this.footerText,
    required this.footerActionText,
    required this.onFooterTap,
  });

  final String title;
  final String subtitle;
  final Widget form;
  final String footerText;
  final String footerActionText;
  final VoidCallback onFooterTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    'dialabse',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ) ??
                        const TextStyle(
                          color: AppColors.primary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ) ??
                        const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFF5E6A66),
                        ) ??
                        const TextStyle(
                          color: Color(0xFF5E6A66),
                          fontSize: 16,
                        ),
                  ),
                  const SizedBox(height: 28),
                  form,
                  const SizedBox(height: 24),
                  if (footerText.isNotEmpty && footerActionText.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          footerText,
                          style: const TextStyle(color: Color(0xFF5E6A66)),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: onFooterTap,
                          child: Text(
                            footerActionText,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
