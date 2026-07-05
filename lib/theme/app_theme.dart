import 'package:flutter/material.dart';

/// Semantic colors that stay fixed in meaning across both themes: night
/// surcharge (purple), carpool/secondary badges (teal), and the trip-ending
/// action (red). Referenced via `Theme.of(context).extension<AppSemanticColors>()`.
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color nightSurcharge;
  final Color secondaryAccent;
  final Color endAction;

  const AppSemanticColors({
    required this.nightSurcharge,
    required this.secondaryAccent,
    required this.endAction,
  });

  static const light = AppSemanticColors(
    nightSurcharge: Color(0xFF8E4FC7),
    secondaryAccent: Color(0xFF1E8A63),
    endAction: Color(0xFFD32F2F),
  );

  static const dark = AppSemanticColors(
    nightSurcharge: Color(0xFFD8A1FF),
    secondaryAccent: Color(0xFF7FD4B5),
    endAction: Color(0xFFE24B4A),
  );

  @override
  AppSemanticColors copyWith({
    Color? nightSurcharge,
    Color? secondaryAccent,
    Color? endAction,
  }) {
    return AppSemanticColors(
      nightSurcharge: nightSurcharge ?? this.nightSurcharge,
      secondaryAccent: secondaryAccent ?? this.secondaryAccent,
      endAction: endAction ?? this.endAction,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      nightSurcharge: Color.lerp(nightSurcharge, other.nightSurcharge, t)!,
      secondaryAccent: Color.lerp(secondaryAccent, other.secondaryAccent, t)!,
      endAction: Color.lerp(endAction, other.endAction, t)!,
    );
  }
}

/// App-wide theme definitions: the current design as the light ("주간")
/// theme, and a dark ("야간") theme modeled on the meter/history/settlement
/// mockups (dark navy surfaces + amber accent).
class AppTheme {
  AppTheme._();

  static const _darkBackground = Color(0xFF111318);
  static const _darkSurface = Color(0xFF1A1D24);
  static const _darkDivider = Color(0xFF2A2D34);
  static const _darkOnSurface = Color(0xFFE8EAEE);
  static const _amber = Color(0xFFF5B52E);

  static final ThemeData light = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
    useMaterial3: true,
    extensions: const [AppSemanticColors.light],
  );

  static final ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _amber,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _amber,
      surface: _darkBackground,
      onSurface: _darkOnSurface,
      surfaceContainerHighest: _darkSurface,
    ),
    scaffoldBackgroundColor: _darkBackground,
    cardTheme: const CardThemeData(
      color: _darkSurface,
      elevation: 0,
    ),
    dividerColor: _darkDivider,
    // Material 3's default AppBar/NavigationBar surfaces use an
    // auto-computed tonal tint derived from the seed color, which comes out
    // as an off, slightly purplish gray against the mockup's flat dark
    // background. Pin them to the same background instead so the chrome
    // reads as one continuous surface, matching the mockups.
    appBarTheme: const AppBarTheme(
      backgroundColor: _darkBackground,
      foregroundColor: _darkOnSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: _darkBackground,
      indicatorColor: _amber.withValues(alpha: 0.24),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    extensions: const [AppSemanticColors.dark],
  );
}

/// Dedicated text style for fare amounts. Tabular figures keep the digits
/// from shifting width as the meter counts up; this is deliberately not left
/// to the ambient text theme so every fare display in the app stays visually
/// consistent.
TextStyle fareTextStyle(
  BuildContext context, {
  required double fontSize,
  FontWeight weight = FontWeight.w600,
}) {
  return TextStyle(
    fontSize: fontSize,
    fontWeight: weight,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: Theme.of(context).colorScheme.primary,
  );
}
