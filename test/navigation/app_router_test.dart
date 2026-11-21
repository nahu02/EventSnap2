import 'package:event_snap_2/models/extraction.dart';
import 'package:event_snap_2/navigation/app_router.dart';
import 'package:event_snap_2/screens/home_screen.dart';
import 'package:event_snap_2/screens/review_screen.dart';
import 'package:event_snap_2/screens/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

void main() {
  group('AppRouter.generateRoute', () {
    test('route names', () {
      expect(AppRouter.home, '/');
      expect(AppRouter.review, '/review');
      expect(AppRouter.settings, '/settings');
    });

    test('creates routes for every name', () {
      expect(
        AppRouter.generateRoute(const RouteSettings(name: AppRouter.home)),
        isA<MaterialPageRoute<void>>(),
      );
      expect(
        AppRouter.generateRoute(const RouteSettings(name: AppRouter.settings)),
        isA<MaterialPageRoute<void>>(),
      );
      expect(
        AppRouter.generateRoute(
          RouteSettings(name: AppRouter.review, arguments: sampleResult()),
        ),
        isA<MaterialPageRoute<ReviewOutcome>>(),
      );
    });

    testWidgets('review without a result and unknown routes show not found', (
      tester,
    ) async {
      for (final settings in const [
        RouteSettings(name: AppRouter.review),
        RouteSettings(name: '/nope'),
      ]) {
        final route = AppRouter.generateRoute(settings)! as MaterialPageRoute;
        await tester.pumpWidget(
          MaterialApp(home: Builder(builder: route.builder)),
        );
        expect(find.text('Page not found'), findsWidgets);
      }
    });

    testWidgets('builds the contract screens', (tester) async {
      final services = TestServices();
      await services.initAppState();
      Widget build(RouteSettings s) {
        final route = AppRouter.generateRoute(s)! as MaterialPageRoute;
        return services.wrap(Builder(builder: route.builder));
      }

      await tester.pumpWidget(build(const RouteSettings(name: AppRouter.home)));
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.pumpWidget(
        build(const RouteSettings(name: AppRouter.settings)),
      );
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.pumpWidget(
        build(RouteSettings(name: AppRouter.review, arguments: sampleResult())),
      );
      expect(find.byType(ReviewScreen), findsOneWidget);
    });
  });

  group('AppRouter navigation helpers', () {
    Future<BuildContext> pumpLauncher(
      WidgetTester tester,
      TestServices services,
    ) async {
      late BuildContext launcherContext;
      await tester.pumpWidget(
        services.wrap(
          Scaffold(
            body: Builder(
              builder: (context) {
                launcherContext = context;
                return const Text('launcher');
              },
            ),
          ),
        ),
      );
      return launcherContext;
    }

    testWidgets('openReview completes with discarded on back', (tester) async {
      final services = TestServices();
      final context = await pumpLauncher(tester, services);
      ReviewOutcome? outcome;
      var completed = false;
      AppRouter.openReview(context, sampleResult()).then((value) {
        outcome = value;
        completed = true;
      });
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(outcome, ReviewOutcome.discarded);
    });

    testWidgets('openReview completes with exported after export', (
      tester,
    ) async {
      final services = TestServices();
      final context = await pumpLauncher(tester, services);
      ReviewOutcome? outcome;
      AppRouter.openReview(context, sampleResult()).then((v) => outcome = v);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add to calendar'));
      await tester.pumpAndSettle();

      expect(outcome, ReviewOutcome.exported);
      expect(services.calendarCreator.created, hasLength(1));
      expect(services.calendarCreator.opened, hasLength(1));
      expect(find.byType(ReviewScreen), findsNothing);
    });

    testWidgets('openSettings pushes the settings screen', (tester) async {
      final services = TestServices();
      await services.initAppState();
      final context = await pumpLauncher(tester, services);
      AppRouter.openSettings(context);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  test('ExtractionResult is the review argument type', () {
    final result = sampleResult();
    expect(result, isA<ExtractionResult>());
  });
}
