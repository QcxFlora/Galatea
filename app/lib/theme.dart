import 'package:flutter/material.dart';

/// Galatea 的配色：深夜蓝紫 + 一点点舞台灯光。
class GColors {
  static const bg = Color(0xFF0E1117);
  static const panel = Color(0xFF161B26);
  static const panel2 = Color(0xFF1E2534);
  static const line = Color(0xFF2A3446);
  static const accent = Color(0xFF7C8CFF);
  static const accent2 = Color(0xFFC46BFF);
  static const ok = Color(0xFF22C08A);
  static const warn = Color(0xFFFFB02E);
  static const err = Color(0xFFFF5C74);
  static const text = Color(0xFFE6EAF2);
  static const dim = Color(0xFF8B96AC);

  static Color forNodeType(String type) {
    switch (type) {
      case 'say':
        return const Color(0xFF4F7CFF);
      case 'choice':
        return const Color(0xFFC46BFF);
      case 'branch':
        return const Color(0xFFFFB02E);
      case 'set':
        return const Color(0xFF22C08A);
      case 'jump':
        return const Color(0xFF8892A8);
      case 'call':
        return const Color(0xFF00B8D9);
      case 'return':
        return const Color(0xFF8892A8);
      case 'end':
        return const Color(0xFFFF5C74);
      case 'script':
        return const Color(0xFFFF7A45);
      default:
        return const Color(0xFF8892A8);
    }
  }
}

ThemeData buildGalateaTheme(Brightness brightness) {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: GColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: GColors.accent,
      secondary: GColors.accent2,
      surface: GColors.panel,
      error: GColors.err,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: GColors.panel,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: GColors.text,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: GColors.text,
      displayColor: GColors.text,
    ),
    dividerColor: GColors.line,
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: GColors.panel2,
      contentTextStyle: TextStyle(color: GColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GColors.panel2,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: GColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: GColors.accent),
      ),
      labelStyle: const TextStyle(color: GColors.dim, fontSize: 13),
      helperStyle: const TextStyle(color: GColors.dim, fontSize: 11),
    ),
  );
}