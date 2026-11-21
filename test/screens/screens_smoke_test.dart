// Smoke tests for the temporary Phase 1 screens. Workstreams D/E/F add
// dedicated tests (review_screen_test.dart, settings_screen_test.dart,
// home_screen_test.dart) and may delete the cases here that they replace.
import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/navigation/app_router.dart';
import 'package:event_snap_2/screens/event_text_input_screen.dart';
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
    testWidgets('renders welcome and setup state', (tester) async {
      final services = TestServices();
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to EventSnap!'), findsOneWidget);
      expect(find.text('Setup required'), findsOneWidget);
    });

    testWidgets('shows provider and model when configured', (tester) async {
      final services = TestServices(settings: configured);
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Ready to go!'), findsOneWidget);
      expect(find.text('OpenAI · gpt-5-mini'), findsOneWidget);
    });

    testWidgets('opens the text input with initially shared text', (
      tester,
    ) async {
      final services = TestServices(
        settings: configured,
        sharedContentSource: FakeSharedContentSource(
          initial: const SharedContent(text: 'Concert on Saturday at 8pm'),
        ),
      );
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(EventTextInputScreen), findsOneWidget);
      expect(find.text('Concert on Saturday at 8pm'), findsOneWidget);
      expect(services.sharedContentSource.initialCalls, 1);
    });

    testWidgets('opens the text input for live shares', (tester) async {
      final services = TestServices(settings: configured);
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      services.sharedContentSource.emit(
        const SharedContent(text: 'Lunch at noon'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lunch at noon'), findsOneWidget);
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

  group('EventTextInputScreen', () {
    testWidgets('enables the button once text is entered', (tester) async {
      useTallView(tester);
      final services = TestServices(settings: configured);
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const EventTextInputScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Create Event from Text'), findsOneWidget);
      final button = find.byKey(const Key('create_event_button'));
      expect(tester.widget<ButtonStyleButton>(button).enabled, isFalse);

      await tester.enterText(
        find.byType(TextField),
        'Meeting tomorrow at 2 PM',
      );
      await tester.pump();
      expect(tester.widget<ButtonStyleButton>(button).enabled, isTrue);
      expect(
        find.descendant(of: button, matching: find.text('Create Event')),
        findsOneWidget,
      );
    });

    testWidgets('extracts events and opens the review screen', (tester) async {
      useTallView(tester);
      final services = TestServices(settings: configured);
      services.interpreter.result = sampleResult(
        events: [sampleEvent(title: 'Board meeting')],
      );
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const EventTextInputScreen()));

      await tester.enterText(
        find.byType(TextField),
        'Board meeting May 25 10am',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('create_event_button')));
      await tester.pumpAndSettle();

      expect(
        services.interpreter.calls.single.text,
        'Board meeting May 25 10am',
      );
      expect(services.aiServiceFactory.createdWith.single, configured);
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.text('Board meeting'), findsOneWidget);
    });

    testWidgets('shows a message when no events are found', (tester) async {
      useTallView(tester);
      final services = TestServices(settings: configured);
      await services.initAppState();
      await tester.pumpWidget(services.wrap(const EventTextInputScreen()));

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byKey(const Key('create_event_button')));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsNothing);
      expect(find.textContaining('No events found'), findsOneWidget);
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
      await tester.pumpWidget(services.wrap(const EventTextInputScreen()));

      await tester.enterText(find.byType(TextField), 'Lunch at 12');
      await tester.pump();
      await tester.tap(find.byKey(const Key('create_event_button')));
      await tester.pumpAndSettle();

      expect(
        find.text(AiException.userMessageFor(AiErrorKind.auth)),
        findsOneWidget,
      );
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
