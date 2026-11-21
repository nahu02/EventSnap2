import 'package:event_snap_2/themes/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('AppTheme', () {
    test('light and dark use Material 3 with the seed fallback', () {
      final light = AppTheme.light();
      final dark = AppTheme.dark();
      expect(light.useMaterial3, isTrue);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(
        light.colorScheme.primary,
        ColorScheme.fromSeed(seedColor: AppTheme.seedColor).primary,
      );
    });

    test('uses a dynamic scheme when given', () {
      final dynamicLight = ColorScheme.fromSeed(
        seedColor: const Color(0xFF00897B),
      );
      final dynamicDark = ColorScheme.fromSeed(
        seedColor: const Color(0xFF00897B),
        brightness: Brightness.dark,
      );
      expect(
        AppTheme.light(dynamicScheme: dynamicLight).colorScheme.primary,
        dynamicLight.primary,
      );
      expect(
        AppTheme.dark(dynamicScheme: dynamicDark).colorScheme.primary,
        dynamicDark.primary,
      );
    });

    test('a dynamic scheme of the wrong brightness is regenerated', () {
      final dynamicLight = ColorScheme.fromSeed(
        seedColor: const Color(0xFF00897B),
      );
      final dark = AppTheme.dark(dynamicScheme: dynamicLight);
      expect(dark.brightness, Brightness.dark);
      expect(dark.colorScheme.brightness, Brightness.dark);
    });

    test('component themes follow the shared UI conventions', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final cs = theme.colorScheme;
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
        // No card shape override: it would strip Card.outlined's border.
        expect(theme.cardTheme.shape, isNull);
        final appBarColor = theme.appBarTheme.backgroundColor!;
        expect(
          WidgetStateProperty.resolveAs<Color>(appBarColor, {}),
          cs.surface,
        );
        expect(
          WidgetStateProperty.resolveAs<Color>(appBarColor, {
            WidgetState.scrolledUnder,
          }),
          cs.surfaceContainer,
        );
        expect(theme.scaffoldBackgroundColor, cs.surface);
        expect(theme.inputDecorationTheme.border, isA<OutlineInputBorder>());
        expect(theme.inputDecorationTheme.errorMaxLines, greaterThan(1));
        expect(
          theme.filledButtonTheme.style!.minimumSize!.resolve({})!.height,
          48,
        );
        expect(theme.bottomAppBarTheme.color, cs.surfaceContainer);
      }
    });
  });
}
