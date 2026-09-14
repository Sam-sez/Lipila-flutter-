import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Ported 1:1 from frontend/src/index.css in the Lipila web repo.
/// Don't invent new colors here — if the palette needs to change, change
/// it in both places deliberately, not by drift.
class LipilaColors {
  static const espresso = Color(0xFF2E1503);
  static const ember = Color(0xFFA8420B);
  static const emberDeep = Color(0xFF7A2F05);
  static const emberLight = Color(0xFFC4590F);
  static const paper = Color(0xFFFDFBF8);
  static const paperDim = Color(0xFFF3EEE7);
  static const line = Color(0xFFE4DACC);
  static const success = Color(0xFF2F6B3E);
  static const danger = Color(0xFFA32626);
  static const charcoal = Color(0xFF1B1712);
  static const charcoalSurface = Color(0xFF262019);
  static const charcoalLine = Color(0xFF3A3025);
}

class LipilaTheme {
  static ThemeData light() {
    final displayFont = GoogleFonts.soraTextTheme();
    final bodyFont = GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: LipilaColors.paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: LipilaColors.ember,
        primary: LipilaColors.ember,
        surface: LipilaColors.paper,
        error: LipilaColors.danger,
        brightness: Brightness.light,
      ),
      textTheme: bodyFont.copyWith(
        headlineLarge: displayFont.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700, color: LipilaColors.espresso,
        ),
        headlineMedium: displayFont.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600, color: LipilaColors.espresso,
        ),
        titleLarge: displayFont.titleLarge?.copyWith(
          fontWeight: FontWeight.w600, color: LipilaColors.espresso,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: LipilaColors.paper,
        foregroundColor: LipilaColors.espresso,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LipilaColors.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: LipilaColors.line, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: LipilaColors.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: LipilaColors.ember, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: LipilaColors.paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: LipilaColors.line),
        ),
      ),
    );
  }
}
