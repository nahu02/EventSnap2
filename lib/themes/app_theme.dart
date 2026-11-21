import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';

/// App theme (Material 3, light and dark) realising the shared UI conventions
/// of docs/v3_plan.md §6.0.
///
/// Colours come from the platform's dynamic scheme (Material You) when
/// available and otherwise from a scheme generated from [seedColor]. Widgets
/// must only use `Theme.of(context).colorScheme` roles: success → primary,
/// warning → tertiary, error → error.
class AppTheme {
  AppTheme._();

  /// Brand seed colour used when no dynamic colour scheme is available
  /// (a calm indigo that works well in light and dark).
  static const Color seedColor = Color(0xFF4355B9);

  /// Corner radius of cards, inputs and other medium-sized surfaces.
  static const double radius = 12;

  /// Corner radius of small components (chips, snack bars).
  static const double smallRadius = 8;

  static ThemeData light({ColorScheme? dynamicScheme}) =>
      fromColorScheme(colorSchemeFor(Brightness.light, dynamicScheme));

  static ThemeData dark({ColorScheme? dynamicScheme}) =>
      fromColorScheme(colorSchemeFor(Brightness.dark, dynamicScheme));

  /// The colour scheme for [brightness]: [dynamicScheme] (with its error
  /// colours harmonized) when given, otherwise one generated from
  /// [seedColor]. A dynamic scheme of the wrong brightness is regenerated from
  /// its primary colour.
  static ColorScheme colorSchemeFor(
    Brightness brightness, [
    ColorScheme? dynamicScheme,
  ]) {
    if (dynamicScheme == null) {
      return ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
    }
    if (dynamicScheme.brightness != brightness) {
      return ColorScheme.fromSeed(
        seedColor: dynamicScheme.primary,
        brightness: brightness,
      ).harmonized();
    }
    return dynamicScheme.harmonized();
  }

  /// Builds the full theme with component themes for [colorScheme].
  static ThemeData fromColorScheme(ColorScheme colorScheme) {
    final cs = colorScheme;
    const smallShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(smallRadius)),
    );
    const buttonMinimumSize = Size(64, 48);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 12);

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      appBarTheme: AppBarThemeData(
        // Surface-coloured; a slightly darker container tone when content
        // scrolls underneath instead of a shadow or tint.
        backgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.scrolledUnder)
              ? cs.surfaceContainer
              : cs.surface,
        ),
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: cs.surfaceContainer,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        contentTextStyle: TextStyle(color: cs.onSurface),
      ),
      bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
      // No `shape` here: overriding it strips the outline Card.outlined
      // draws. The M3 default card radius already matches [radius] (12).
      cardTheme: const CardThemeData(clipBehavior: Clip.antiAlias),
      chipTheme: const ChipThemeData(shape: smallShape),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMinimumSize,
          padding: buttonPadding,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonMinimumSize,
          padding: buttonPadding,
        ),
      ),
      inputDecorationTheme: const InputDecorationThemeData(
        // Only the shape is set; Material 3 resolves the border colour per
        // state (outline, primary when focused, error, disabled).
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        alignLabelWithHint: true,
        helperMaxLines: 3,
        errorMaxLines: 3,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: cs.onSurfaceVariant,
        minVerticalPadding: 8,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: smallShape,
        insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }
}
