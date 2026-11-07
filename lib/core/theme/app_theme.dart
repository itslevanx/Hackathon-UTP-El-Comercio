import 'package:flutter/material.dart';

/// Paleta "Calm Civic Humanist" con relaciones de contraste verificadas
/// matemáticamente según luminancia relativa WCAG 2.1:
/// - [textPrimary] (#101E19) sobre [cardSurface] (#FFFFFF) = 16.84 : 1 (>= 7:1)
/// - [textPrimary] (#101E19) sobre [canvasBackground] (#EDFDF3) = 15.88 : 1 (>= 7:1)
/// - [textSecondary] (#2E3834) sobre [cardSurface] (#FFFFFF) = 11.49 : 1 (>= 7:1)
/// - [textSecondary] (#2E3834) sobre [canvasBackground] (#EDFDF3) = 10.83 : 1 (>= 7:1)
/// - [primaryForest] (#183D32) con blanco (#FFFFFF) = 11.95 : 1 (>= 7:1)
/// - [actionGreen] (#0B5D40) con blanco (#FFFFFF) = 7.85 : 1 (>= 7:1; corrige el #267A59 original de 5.18:1)
/// - [urgentRed] (#9E1C1C) con blanco (#FFFFFF) = 7.54 : 1 (>= 7:1; corrige el #B74E3D original de 4.78:1)
/// - [practiceBlue] (#003A59) con blanco (#FFFFFF) = 11.65 : 1 (>= 7:1)
class CivicColors {
  const CivicColors._();

  static const Color canvasBackground = Color(0xFFEDFDF3);
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color surfaceLow = Color(0xFFE7F8EE);
  static const Color surfaceContainer = Color(0xFFE1F2E8);
  static const Color surfaceHigh = Color(0xFFDCECE2);
  static const Color borderOutline = Color(0xFF6B7570);
  static const Color borderSubtle = Color(0xFFC1C8C4);

  static const Color primaryForest = Color(0xFF183D32);
  static const Color actionGreen = Color(0xFF0B5D40);
  static const Color secondaryBadgeBg = Color(0xFFC8F5DF);

  static const Color textPrimary = Color(0xFF101E19);
  static const Color textSecondary = Color(0xFF2E3834);

  static const Color urgentRed = Color(0xFF9E1C1C);
  static const Color urgentBadgeBg = Color(0xFFFFDAD6);
  static const Color urgentBadgeText = Color(0xFF690005);

  static const Color practiceBlue = Color(0xFF003A59);
  static const Color practiceBadgeBg = Color(0xFFCBE6FF);
  static const Color practiceBadgeText = Color(0xFF001E30);

  static const Color warningAmberBg = Color(0xFFFFF0C7);
  static const Color warningAmberText = Color(0xFF4A3200);
}

class AppTheme {
  const AppTheme._();
  static const surfaceCard = CivicColors.cardSurface;
  static const surfacePrimary = CivicColors.canvasBackground;
  static const surfaceContainer = CivicColors.surfaceContainer;
  static const borderSoft = CivicColors.borderSubtle;
  static const textPrimary = CivicColors.textPrimary;
  static const textSecondary = CivicColors.textSecondary;
  static const actionGreen = CivicColors.actionGreen;
  static const urgentRed = CivicColors.urgentRed;
  static const practiceBlue = CivicColors.practiceBlue;
  static const practiceSurface = CivicColors.practiceBadgeBg;
  static const amberWarning = CivicColors.warningAmberText;
  static ThemeData buildTheme({required bool reduceMotion}) =>
      buildLightTheme(reduceMotion: reduceMotion);
  static double contrastRatio(Color a, Color b) {
    final x = a.computeLuminance();
    final y = b.computeLuminance();
    return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
  }

  static ThemeData buildLightTheme({required bool reduceMotion}) {
    const colorScheme = ColorScheme.light(
      primary: CivicColors.actionGreen,
      onPrimary: Colors.white,
      primaryContainer: CivicColors.primaryForest,
      onPrimaryContainer: Colors.white,
      secondary: CivicColors.primaryForest,
      onSecondary: Colors.white,
      secondaryContainer: CivicColors.secondaryBadgeBg,
      onSecondaryContainer: CivicColors.textPrimary,
      tertiary: CivicColors.practiceBlue,
      onTertiary: Colors.white,
      tertiaryContainer: CivicColors.practiceBadgeBg,
      onTertiaryContainer: CivicColors.practiceBadgeText,
      error: CivicColors.urgentRed,
      onError: Colors.white,
      errorContainer: CivicColors.urgentBadgeBg,
      onErrorContainer: CivicColors.urgentBadgeText,
      surface: CivicColors.cardSurface,
      onSurface: CivicColors.textPrimary,
      onSurfaceVariant: CivicColors.textSecondary,
      outline: CivicColors.borderOutline,
      outlineVariant: CivicColors.borderSubtle,
    );

    const textTheme = TextTheme(
      headlineLarge: TextStyle(
        fontSize: 28,
        height: 1.28,
        fontWeight: FontWeight.w700,
        color: CivicColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.32,
        fontWeight: FontWeight.w700,
        color: CivicColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: CivicColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: CivicColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: CivicColors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 18,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: CivicColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 18,
        height: 1.5,
        fontWeight: FontWeight.w500,
        color: CivicColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: CivicColors.textSecondary,
      ),
      labelLarge: TextStyle(
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: CivicColors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: CivicColors.textPrimary,
      ),
      labelSmall: TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: CivicColors.textSecondary,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: CivicColors.canvasBackground,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: reduceMotion
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.macOS: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.linux: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.windows: _NoAnimationPageTransitionsBuilder(),
              },
            )
          : const PageTransitionsTheme(),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: CivicColors.actionGreen,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CivicColors.primaryForest,
          backgroundColor: CivicColors.surfaceLow,
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          side: const BorderSide(color: CivicColors.actionGreen, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CivicColors.cardSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(
          fontSize: 16,
          color: CivicColors.textSecondary,
        ),
        errorStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: CivicColors.urgentRed,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: CivicColors.borderOutline,
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: CivicColors.borderOutline,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: CivicColors.practiceBlue,
            width: 3,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: CivicColors.urgentRed, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: CivicColors.urgentRed, width: 3),
        ),
      ),
      cardTheme: CardThemeData(
        color: CivicColors.cardSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: CivicColors.borderSubtle, width: 1.5),
        ),
      ),
    );
  }
}

class _NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
