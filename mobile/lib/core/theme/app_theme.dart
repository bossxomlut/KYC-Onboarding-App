import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const primary = Color(0xFF026220);
  static const background = Colors.white;
  static const ink = Color(0xFF172D24);
  static const muted = Color(0xFF617169);
  static const border = Color(0xFFD8E2DC);
  static const mint = Color(0xFFE8F3EA);
  static const disabledSurface = Color(0xFFE9EEEB);
  static const controlRadius = 14.0;
  static const panelRadius = 16.0;

  static ThemeData get light {
    final colors =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: primary,
          onPrimary: Colors.white,
          primaryContainer: mint,
          onPrimaryContainer: primary,
          surface: Colors.white,
          onSurface: ink,
          onSurfaceVariant: muted,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: background,
          surfaceContainer: const Color(0xFFF7F9F7),
          surfaceContainerHigh: mint,
          surfaceContainerHighest: mint,
          outline: muted,
          outlineVariant: border,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        centerTitle: false,
        scrolledUnderElevation: 0,
        elevation: 0,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
          color: ink,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: -.6,
          color: ink,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          height: 1.25,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: ink),
        bodySmall: TextStyle(fontSize: 12, height: 1.4, color: muted),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: muted,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: muted,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        labelStyle: const TextStyle(color: muted),
        hintStyle: const TextStyle(color: muted, fontWeight: FontWeight.w400),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: disabledSurface,
          disabledForegroundColor: muted,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          foregroundColor: primary,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(panelRadius),
          side: const BorderSide(color: border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: disabledSurface,
      ),
      iconTheme: const IconThemeData(color: ink, size: 22),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: mint,
        selectionHandleColor: primary,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
