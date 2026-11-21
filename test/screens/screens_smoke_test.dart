// Smoke tests for the temporary Phase 1 screens. Workstreams D/E/F add
// dedicated tests (review_screen_test.dart, settings_screen_test.dart,
// home_screen_test.dart) and may delete the cases here that they replace.
import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/navigation/app_router.dart';
import 'package:event_snap_2/screens/home_screen.dart';
import 'package:event_snap_2/screens/review_screen.dart';
import 'package:event_snap_2/screens/settings_screen.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

void main() {
  const configured = Settings(openAiApiKey: 'sk-test1234567890');

  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('HomeScreen', () {
    testWidgets('renders the composer and setup state', (tester) async {
      final services = TestServices();
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('EventSnap'), findsOneWidget);
      expect(find.text('Finish setting up'), findsOneWidget);
      expect(find.text('Find events'), findsOneWidget);
      expect(find.text('Try an example'), findsOneWidget);
    });

    testWidgets('shows provider and model when configured', (tester) async {
      final services = TestServices(settings: configured);
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Finish setting up'), findsNothing);
      expect(find.text('OpenAI · gpt-5-mini'), findsOneWidget);
    });

    testWidgets('fills the composer with initially shared text', (
      tester,
    ) async {
      final services = TestServices(
        settings: configured.copyWith(autoProcessShared: false),
        sharedContentSource: FakeSharedContentSource(
          initial: const SharedContent(text: 'Concert on Saturday at 8pm'),
        ),
      );
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Concert on Saturday at 8pm'), findsOneWidget);
      expect(services.sharedContentSource.initialCalls, 1);
      expect(services.interpreter.calls, isEmpty);
    });

    testWidgets('fills the composer with live shares', (tester) async {
      final services = TestServices(
        settings: configured.copyWith(autoProcessShared: false),
      );
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      services.sharedContentSource.emit(
        const SharedContent(text: 'Lunch at noon'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lunch at noon'), findsOneWidget);
    });

    testWidgets('extracts events and opens the review screen', (tester) async {
      useTallView(tester);
      final services = TestServices(settings: configured);
      services.interpreter.result = sampleResult(
        events: [sampleEvent(title: 'Board meeting')],
      );
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const HomeScreen()));

      await tester.enterText(
        find.byType(TextField),
        'Board meeting May 25 10am',
      );
      await tester.pump();
      await tester.tap(find.text('Find events'));
      await tester.pumpAndSettle();

      expect(
        services.interpreter.calls.single.text,
        'Board meeting May 25 10am',
      );
      expect(services.aiServiceFactory.createdWith.single, configured);
      expect(find.byType(ReviewScreen), findsOneWidget);
    });

    testWidgets('shows the friendly AiException message', (tester) async {
      useTallView(tester);
      final services = TestServices(settings: configured);
      services.interpreter.error = const AiException(
        AiErrorKind.auth,
        'HTTP 401',
        statusCode: 401,
      );
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const HomeScreen()));

      await tester.enterText(find.byType(TextField), 'Lunch at 12');
      await tester.pump();
      await tester.tap(find.text('Find events'));
      await tester.pumpAndSettle();

      expect(
        find.text(AiException.userMessageFor(AiErrorKind.auth)),
        findsOneWidget,
      );
    });
  });

  group('SettingsScreen', () {
    testWidgets('renders', (tester) async {
      final services = TestServices();
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const SettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('lists models from the ModelCatalog', (tester) async {
      final services = TestServices(settings: configured);
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const SettingsScreen()));
      await tester.pumpAndSettle();
      expect(services.modelCatalog.listCalls, 1);
    });
  });

  group('ReviewScreen', () {
    testWidgets('renders a single event', (tester) async {
      useTallView(tester);
      final services = TestServices();
      await tester.pumpWidget(
        services.wrap(
          ReviewScreen(
            result: sampleResult(
              events: [
                sampleEvent(
                  title: 'Test Event Details',
                  description: 'Test description 2345',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Review events'), findsOneWidget);
      expect(find.text('Test Event Details'), findsOneWidget);
      expect(find.text('Test description 2345'), findsOneWidget);
      expect(find.text('Add to calendar'), findsOneWidget);
    });

    testWidgets('renders several events and warnings', (tester) async {
      useTallView(tester);
      final services = TestServices();
      await tester.pumpWidget(
        services.wrap(
          ReviewScreen(
            result: sampleResult(
              events: [
                sampleEvent(title: 'One'),
                sampleEvent(title: 'Two'),
              ],
              warnings: const ['Model lacks structured output; used JSON mode'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(find.text('Add 2 events to calendar'), findsOneWidget);
      expect(
        find.text('Model lacks structured output; used JSON mode'),
        findsOneWidget,
      );
    });

    testWidgets('keeps the screen open when no calendar app exists', (
      tester,
    ) async {
      useTallView(tester);
      final services = TestServices(
        calendarCreator: FakeCalendarCreator(openResult: false),
      );
      await tester.pumpWidget(
        services.wrap(ReviewScreen(result: sampleResult())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add to calendar'));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.textContaining('No calendar app found'), findsOneWidget);
    });

    testWidgets('exports through the CalendarCreator', (tester) async {
      useTallView(tester);
      final services = TestServices();
      final event = sampleEvent(title: 'Export me');
      await tester.pumpWidget(
        services.wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  AppRouter.openReview(context, sampleResult(events: [event])),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to calendar'));
      await tester.pumpAndSettle();

      final exported = services.calendarCreator.created.single.single;
      expect(exported.title, 'Export me');
      expect(exported.id, event.id);
    });
  });
}
