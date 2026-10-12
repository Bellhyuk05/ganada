import 'package:flutter/material.dart';

/// 회원가입 시안 기준 색상.
class AuthColors {
  static const primary = Color(0xFF3D5AFE);
  static const primarySoft = Color(0xFFEEF1FE);

  static const textStrong = Color(0xFF191F28);
  static const textBody = Color(0xFF333D4B);
  static const textSub = Color(0xFF6B7684);
  static const textHint = Color(0xFFB0B8C1);

  static const border = Color(0xFFE5E8EB);
  static const surface = Color(0xFFF7F8FA);
  static const disabledBg = Color(0xFFEDEFF2);
  static const disabledText = Color(0xFFB0B8C1);

  static const success = Color(0xFF1FA463);
  static const error = Color(0xFFE5484D);
}

ThemeData buildAuthTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AuthColors.primary,
      primary: AuthColors.primary,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: Colors.white,
    textSelectionTheme: const TextSelectionThemeData(cursorColor: AuthColors.primary),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
