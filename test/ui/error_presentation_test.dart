import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/themes/app_theme.dart';
import 'package:event_snap_2/ui/error_presentation.dart';
import 'package:event_snap_2/ui/inline_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('ErrorPresentation', () {
    test('maps kinds to the documented actions', () {
      const expected = <AiErrorKind, ErrorAction?>{
        AiErrorKind.notConfigured: ErrorAction.openSettings,
        AiErrorKind.auth: ErrorAction.openSettings,
        AiErrorKind.modelNotFound: ErrorAction.chooseModel,
        AiErrorKind.unsupportedInput: ErrorAction.chooseVisionModel,
        AiErrorKind.network: ErrorAction.retry,
        AiErrorKind.timeout: ErrorAction.retry,
        AiErrorKind.server: ErrorAction.retry,
        AiErrorKind.rateLimited: ErrorAction.retry,
        AiErrorKind.invalidResponse: ErrorAction.retry,
        AiErrorKind.unknown: ErrorAction.retry,
        AiErrorKind.quotaExceeded: null,
        AiErrorKind.cancelled: null,
      };
      expect(expected.keys, unorderedEquals(AiErrorKind.values));
      for (final MapEntry(key: kind, value: action) in expected.entries) {
        final p = ErrorPresentation.forKind(kind);
        expect(p.kind, kind);
        expect(p.action, action, reason: kind.name);
        expect(p.message, AiException.userMessageFor(kind));
        expect(p.title, isNotEmpty);
      }
    });

    test('action labels are sentence case', () {
      expect(ErrorAction.openSettings.label, 'Open settings');
      expect(ErrorAction.chooseModel.label, 'Choose model');
      expect(ErrorAction.chooseVisionModel.label, 'Choose a vision model');
      expect(ErrorAction.retry.label, 'Retry');
      expect(ErrorAction.retry.opensSettings, isFalse);
      expect(ErrorAction.chooseModel.opensSettings, isTrue);
    });

    test('forError handles AiException and other errors', () {
      expect(
        ErrorPresentation.forError(
          const AiException(AiErrorKind.timeout, 'slow'),
        ).kind,
        AiErrorKind.timeout,
      );
      expect(
        ErrorPresentation.forError(StateError('boom')).kind,
        AiErrorKind.unknown,
      );
    });
  });

  group('ErrorBanner', () {
    Widget wrap(Widget child, {ThemeMode mode = ThemeMode.light}) =>
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: Scaffold(body: child),
        );

    testWidgets('shows the message and calls back with the action', (
      tester,
    ) async {
      ErrorAction? tapped;
      var dismissed = false;
      await tester.pumpWidget(
        wrap(
          ErrorBanner(
            presentation: ErrorPresentation.forKind(AiErrorKind.auth),
            onAction: (a) => tapped = a,
            onDismiss: () => dismissed = true,
          ),
        ),
      );

      expect(find.text('API key not accepted'), findsOneWidget);
      expect(
        find.text(AiException.userMessageFor(AiErrorKind.auth)),
        findsOneWidget,
      );
      await tester.tap(find.text('Open settings'));
      expect(tapped, ErrorAction.openSettings);
      await tester.tap(find.byTooltip('Dismiss'));
      expect(dismissed, isTrue);
    });

    testWidgets('hides the action without a handler or action', (tester) async {
      await tester.pumpWidget(
        wrap(
          ErrorBanner(
            presentation: ErrorPresentation.forKind(AiErrorKind.network),
          ),
        ),
      );
      expect(find.text('Retry'), findsNothing);
      expect(find.byTooltip('Dismiss'), findsNothing);

      await tester.pumpWidget(
        wrap(
          ErrorBanner(
            presentation: ErrorPresentation.forKind(AiErrorKind.quotaExceeded),
            onAction: (_) {},
          ),
        ),
      );
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('uses error container colours in light and dark', (
      tester,
    ) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpWidget(
          wrap(
            ErrorBanner(
              presentation: ErrorPresentation.forKind(AiErrorKind.server),
            ),
            mode: mode,
          ),
        );
        final card = tester.widget<Card>(find.byType(Card));
        final cs = Theme.of(tester.element(find.byType(Card))).colorScheme;
        expect(card.color, cs.errorContainer);
      }
    });
  });

  group('InlineBanner', () {
    testWidgets('maps tones to colour roles', (tester) async {
      final scheme = AppTheme.light().colorScheme;
      final expected = {
        BannerTone.info: scheme.surfaceContainerHigh,
        BannerTone.success: scheme.primaryContainer,
        BannerTone.warning: scheme.tertiaryContainer,
        BannerTone.error: scheme.errorContainer,
      };
      for (final MapEntry(key: tone, value: color) in expected.entries) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: InlineBanner(
                tone: tone,
                icon: Icons.info_outline,
                message: 'Message',
              ),
            ),
          ),
        );
        expect(tester.widget<Card>(find.byType(Card)).color, color);
      }
    });
  });
}
