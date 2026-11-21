import 'package:material_ui/material_ui.dart';

/// App theme configuration (Material 3, light and dark).
///
/// Uses the platform's dynamic colour scheme (Material You) when available and
/// falls back to a scheme generated from [seedColor].
class AppTheme {
  AppTheme._();

  /// Brand seed colour used when no dynamic colour scheme is available.
  static const Color seedColor = Color(0xFF2196F3);

  static ThemeData light({ColorScheme? dynamicScheme}) => _build(
    dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
  );

  static ThemeData dark({ColorScheme? dynamicScheme}) => _build(
    dynamicScheme ??
        ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark),
  );

  static ThemeData _build(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      cardTheme: const CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }
}
