import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/navigation/app_router.dart';
import 'package:event_snap_2/screens/review_screen.dart';
import 'package:event_snap_2/widgets/review/evidence_line.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';
import '../widgets/review/review_samples.dart';

/// Opens the review screen through [AppRouter.openReview] and records how it
/// was left.
class _Harness {
  _Harness(this.services);

  final TestServices services;
  ReviewOutcome? outcome;
  bool completed = false;
}

void main() {
  void useTallView(WidgetTester tester, {Size size = const Size(1080, 2400)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<_Harness> openReview(
    WidgetTester tester,
    ExtractionResult result, {
    TestServices? services,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    final harness = _Harness(services ?? TestServices());
    await harness.services.initAppState();
    await tester.pumpWidget(
      harness.services.wrap(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppRouter.openReview(context, result).then((v) {
                harness.outcome = v;
                harness.completed = true;
              }),
              child: const Text('open'),
            ),
          ),
        ),
        themeMode: themeMode,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsOneWidget);
    return harness;
  }

  Finder titleField() => find.byKey(const ValueKey('event_title_field'));
  Finder exportButton() => find.byKey(const ValueKey('review_export_button'));

  /// Text of the highlighted span in the expanded source panel, if any.
  String? sourceHighlight(WidgetTester tester) {
    final texts = find.descendant(
      of: find.byKey(const ValueKey('source_card')),
      matching: find.byType(Text),
    );
    for (final text in tester.widgetList<Text>(texts)) {
      final span = text.textSpan;
      if (span is! TextSpan || span.children == null) continue;
      for (final child in span.children!.whereType<TextSpan>()) {
        if (child.style?.backgroundColor != null) return child.text;
      }
    }
    return null;
  }

  group('layout', () {
    testWidgets('shows the app bar count, source, warnings and the export '
        'action', (tester) async {
      useTallView(tester);
      await openReview(
        tester,
        planningResult(
          events: [planningEvent(), lunchEvent()],
          warnings: const ['Model lacks structured output; used JSON mode'],
        ),
      );

      expect(find.text('Review events'), findsOneWidget);
      expect(find.text('2 events'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      expect(
        find.textContaining('Please bring your Q3 numbers.'),
        findsOneWidget,
      );
      expect(
        find.text('Model lacks structured output; used JSON mode'),
        findsOneWidget,
      );
      expect(find.text('Add 2 events to calendar'), findsOneWidget);
      // Both cards expanded: the title is in the form, not repeated above it.
      expect(find.text('Quarterly planning meeting'), findsOneWidget);
      expect(titleField(), findsNWidgets(2));
      expect(find.textContaining('Jun 6'), findsWidgets);
    });

    testWidgets('more than three events start collapsed and can be expanded', (
      tester,
    ) async {
      useTallView(tester);
      final h = await openReview(
        tester,
        planningResult(
          events: [
            planningEvent(),
            lunchEvent(),
            planningEvent(title: 'Follow-up'),
            sampleEvent(title: 'Retro'),
          ],
        ),
      );

      expect(titleField(), findsNothing);
      expect(find.text('Follow-up'), findsOneWidget);
      expect(find.text('Retro'), findsOneWidget);

      await tester.tap(find.byTooltip('Expand event').first);
      await tester.pumpAndSettle();
      expect(titleField(), findsOneWidget);
      expect(find.byTooltip('Collapse event'), findsOneWidget);

      // Collapsed forms stay mounted and are exported too.
      await tester.tap(exportButton());
      await tester.pumpAndSettle();
      expect(h.services.calendarCreator.created.single, hasLength(4));
      expect(h.outcome, ReviewOutcome.exported);
    });

    testWidgets('shows the empty state when nothing was found', (tester) async {
      useTallView(tester);
      final h = await openReview(tester, planningResult(events: const []));

      expect(find.text('No events found'), findsOneWidget);
      expect(find.text('No events'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      expect(exportButton(), findsNothing);

      await tester.tap(find.text('Edit text'));
      await tester.pumpAndSettle();
      expect(h.outcome, ReviewOutcome.discarded);
    });

    testWidgets('shows the raw AI response only in debug mode', (tester) async {
      useTallView(tester);
      final result = planningResult(rawResponse: '{"events": ["raw-123"]}');
      await openReview(tester, result);
      expect(find.text('Raw AI response'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await openReview(
        tester,
        result,
        services: TestServices(settings: const Settings(debugMode: true)),
      );
      expect(find.text('Raw AI response'), findsOneWidget);
      await tester.tap(find.text('Raw AI response'));
      await tester.pumpAndSettle();
      expect(find.text('{"events": ["raw-123"]}'), findsOneWidget);
      expect(find.byTooltip('Copy raw response'), findsOneWidget);
    });

    testWidgets('shows image thumbnails that open full screen', (tester) async {
      useTallView(tester);
      await openReview(
        tester,
        planningResult(
          images: const [
            InputImage(path: '/does/not/exist/a.jpg'),
            InputImage(path: '/does/not/exist/b.jpg'),
          ],
        ),
      );
      expect(find.text('Your text · 2 images'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('source_image_1')));
      await tester.pumpAndSettle();
      expect(find.text('Image 2 of 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsOneWidget);
    });

    testWidgets('bottom bar label stays on one line at large text', (
      tester,
    ) async {
      useTallView(tester, size: const Size(360, 640));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openReview(
        tester,
        planningResult(events: [planningEvent(), lunchEvent(), lunchEvent()]),
      );
      expect(find.text('Add 3 events to calendar'), findsNothing);
      final label = find.descendant(
        of: find.byKey(const ValueKey('review_export_button')),
        matching: find.text('Add to calendar'),
      );
      expect(label, findsOneWidget);
      expect(tester.getSize(label).height, lessThan(2 * 14 * 2 * 1.5));
      expect(find.text('3 events'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode at text scale 2 with the 24-hour clock', (
      tester,
    ) async {
      useTallView(tester, size: const Size(412, 915));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openReview(
        tester,
        planningResult(
          events: [planningEvent(), lunchEvent()],
          warnings: const ['A warning that is long enough to wrap twice.'],
          images: const [InputImage(path: '/does/not/exist/a.jpg')],
        ),
        services: TestServices(settings: const Settings(debugMode: true)),
        themeMode: ThemeMode.dark,
      );
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(ReviewScreen)))
            .scale(10),
        20,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('evidence_description')),
      );
      await tester.tap(find.byKey(const ValueKey('evidence_description')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show in source'));
      await tester.tap(find.text('Show in source'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove event').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('evidence', () {
    testWidgets('renders quotes, reasoning, inferred values and Check badges', (
      tester,
    ) async {
      useTallView(tester);
      await openReview(
        tester,
        planningResult(
          events: [planningEvent(), lunchEvent()],
          text: '$planningText\n$lunchText',
        ),
      );

      expect(
        find.text(
          '“Friday, June 6 from 2pm” · Date and start time are stated '
          'explicitly.',
        ),
        findsOneWidget,
      );
      // Null quote → "Inferred".
      expect(
        find.text('Inferred · No end time given; assumed one hour.'),
        findsOneWidget,
      );
      // Low confidence: the description of #1 and the end of #2.
      expect(find.text('Check'), findsNWidgets(2));
      expect(find.text('1 to check'), findsNWidgets(2));
    });

    testWidgets('tapping evidence highlights its quote in the source', (
      tester,
    ) async {
      useTallView(tester);
      await openReview(tester, planningResult());
      expect(sourceHighlight(tester), isNull);

      await tester.tap(find.byKey(const ValueKey('evidence_start')));
      await tester.pumpAndSettle();
      expect(sourceHighlight(tester), 'Friday, June 6 from 2pm');
      expect(find.text('Highlighted: start'), findsOneWidget);
    });

    testWidgets('focusing a field highlights its quote (case and whitespace '
        'insensitive)', (tester) async {
      useTallView(tester);
      await openReview(tester, planningResult());

      await tester.tap(find.byKey(const ValueKey('event_location_field')));
      await tester.pumpAndSettle();
      // Evidence quote is 'ROOM 4B   at the Oslo office'.
      expect(sourceHighlight(tester), 'Room 4B at the Oslo office');
      expect(find.text('Highlighted: location'), findsOneWidget);
    });

    testWidgets('a quote missing from the text is shown as a fallback', (
      tester,
    ) async {
      useTallView(tester);
      await openReview(
        tester,
        planningResult(
          events: [
            sampleEvent(
              title: 'Gig',
              evidence: const {
                EventField.title: FieldEvidence(
                  quote: 'Big Gig Night',
                  reasoning: 'Printed on the poster.',
                  confidence: EvidenceConfidence.medium,
                ),
              },
            ),
          ],
          images: const [InputImage(path: '/does/not/exist/a.jpg')],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('evidence_title')));
      await tester.pumpAndSettle();

      expect(sourceHighlight(tester), isNull);
      expect(
        find.textContaining(
          'is not word-for-word in your text; it may come '
          'from an image',
        ),
        findsOneWidget,
      );
      expect(find.text('Read from your image'), findsOneWidget);
      expect(find.text('Show in source'), findsNothing);
    });

    testWidgets('"Show in source" expands a collapsed source and highlights '
        'the quote', (tester) async {
      useTallView(tester);
      final longText =
          '${List.filled(12, 'Some unrelated line of the email.').join('\n')}'
          '\n$planningText';
      await openReview(tester, planningResult(text: longText));

      expect(find.byKey(const ValueKey('source_preview')), findsOneWidget);
      expect(find.byTooltip('Show source'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('evidence_end')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show in source'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Hide source'), findsOneWidget);
      expect(find.byKey(const ValueKey('source_preview')), findsNothing);
      expect(sourceHighlight(tester), 'to 4:30pm');
    });

    testWidgets('editing a field shows "Edited by you" and clears its Check', (
      tester,
    ) async {
      useTallView(tester);
      await openReview(tester, planningResult());
      expect(find.text('1 to check'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('event_description_field')),
        'Bring Q3 numbers and a laptop.',
      );
      await tester.pump();

      expect(find.text('Edited by you'), findsOneWidget);
      expect(find.text('1 to check'), findsNothing);
      expect(find.text('Check'), findsNothing);
      expect(find.text('Edited'), findsOneWidget);
    });
  });

  group('editing', () {
    testWidgets('removing an event can be undone, keeping its edits', (
      tester,
    ) async {
      useTallView(tester);
      await openReview(
        tester,
        planningResult(events: [planningEvent(), lunchEvent()]),
      );
      await tester.enterText(titleField().first, 'Q3 planning');
      await tester.pump();

      await tester.tap(find.byTooltip('Remove event').first);
      await tester.pumpAndSettle();
      expect(find.text('Removed “Q3 planning”'), findsOneWidget);
      expect(find.text('1 event'), findsOneWidget);
      expect(find.text('Add to calendar'), findsOneWidget);
      expect(find.text('Q3 planning'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('2 events'), findsOneWidget);
      expect(find.text('Q3 planning'), findsOneWidget);
      expect(find.text('Edited by you'), findsOneWidget);
      // Restored at its original position.
      expect(
        tester.getTopLeft(find.text('Q3 planning')).dy,
        lessThan(tester.getTopLeft(find.text('Lunch with Sam')).dy),
      );
    });

    testWidgets('removing every event shows the empty state', (tester) async {
      useTallView(tester);
      final h = await openReview(tester, planningResult());
      await tester.tap(find.byTooltip('Remove event'));
      await tester.pumpAndSettle();

      expect(find.text('All events removed'), findsOneWidget);
      expect(exportButton(), findsNothing);

      // Nothing left to lose: back leaves without asking.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(h.outcome, ReviewOutcome.discarded);
    });

    testWidgets('toggling all-day updates the header and the export', (
      tester,
    ) async {
      useTallView(tester);
      final h = await openReview(tester, planningResult());

      await tester.tap(find.byKey(const ValueKey('event_all_day_switch')));
      await tester.pumpAndSettle();

      expect(find.text('All day'), findsNWidgets(2)); // switch + header pill
      final range = tester.widget<Text>(
        find.byKey(const ValueKey('event_card_range')),
      );
      expect(range.data, isNot(contains('PM')));
      expect(range.data, contains('Jun 6'));

      await tester.tap(exportButton());
      await tester.pumpAndSettle();
      final exported = h.services.calendarCreator.created.single.single;
      expect(exported.isAllDay, isTrue);
      expect(exported.startDateTime, DateTime(2025, 6, 6));
      expect(exported.endDateTime, DateTime(2025, 6, 7));
    });

    testWidgets('changing the start keeps the duration', (tester) async {
      useTallView(tester);
      final h = await openReview(tester, planningResult());

      await tester.tap(find.byKey(const ValueKey('event_start_date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('2 h 30 min'), findsOneWidget);
      await tester.tap(exportButton());
      await tester.pumpAndSettle();
      final exported = h.services.calendarCreator.created.single.single;
      expect(exported.startDateTime, DateTime(2025, 6, 12, 14));
      expect(exported.endDateTime, DateTime(2025, 6, 12, 16, 30));
    });
  });

  group('export', () {
    testWidgets('exports the edited events and pops with exported', (
      tester,
    ) async {
      useTallView(tester);
      final event = planningEvent();
      final h = await openReview(
        tester,
        planningResult(events: [event, lunchEvent()]),
      );
      await tester.enterText(titleField().first, 'Q3 planning');
      await tester.pump();

      await tester.tap(find.text('Add 2 events to calendar'));
      await tester.pumpAndSettle();

      final exported = h.services.calendarCreator.created.single;
      expect(exported.map((e) => e.title), ['Q3 planning', 'Lunch with Sam']);
      expect(exported.first.id, event.id);
      expect(h.services.calendarCreator.opened, ['/fake/events_1.ics']);
      expect(h.outcome, ReviewOutcome.exported);
      expect(find.byType(ReviewScreen), findsNothing);
    });

    testWidgets('does not export invalid events', (tester) async {
      useTallView(tester);
      final h = await openReview(tester, planningResult());
      await tester.enterText(titleField(), '');
      await tester.pump();

      await tester.tap(exportButton());
      await tester.pumpAndSettle();

      expect(h.services.calendarCreator.created, isEmpty);
      expect(find.text('Add a title'), findsOneWidget);
      expect(find.text('Fix the highlighted fields first'), findsOneWidget);
      expect(find.byType(ReviewScreen), findsOneWidget);
    });

    testWidgets('explains what to do when no calendar app exists', (
      tester,
    ) async {
      useTallView(tester);
      final h = await openReview(
        tester,
        planningResult(),
        services: TestServices(
          calendarCreator: FakeCalendarCreator(openResult: false),
        ),
      );
      await tester.tap(exportButton());
      await tester.pumpAndSettle();

      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(h.completed, isFalse);
      expect(find.text('No calendar app found'), findsOneWidget);
      expect(find.text('Get a calendar app'), findsOneWidget);
      expect(ReviewScreen.calendarAppSearchUri.host, 'play.google.com');

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('No calendar app found'), findsNothing);
    });

    testWidgets('shows an error when the calendar file cannot be created', (
      tester,
    ) async {
      useTallView(tester);
      await openReview(
        tester,
        planningResult(),
        services: TestServices(
          calendarCreator: FakeCalendarCreator(
            createError: Exception('disk full'),
          ),
        ),
      );
      await tester.tap(exportButton());
      await tester.pumpAndSettle();

      expect(find.text('Could not create the calendar file'), findsOneWidget);
      expect(find.textContaining(r'$e'), findsNothing);
      expect(tester.widget<ButtonStyleButton>(exportButton()).enabled, isTrue);
    });
  });

  group('leaving', () {
    testWidgets('back without edits leaves without asking', (tester) async {
      useTallView(tester);
      final h = await openReview(tester, planningResult());
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(h.outcome, ReviewOutcome.discarded);
    });

    testWidgets('back with edits asks before discarding', (tester) async {
      useTallView(tester);
      final h = await openReview(tester, planningResult());
      await tester.enterText(titleField(), 'Something else');
      await tester.pump();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(h.completed, isFalse);

      // System back asks too.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsNothing);
      expect(h.outcome, ReviewOutcome.discarded);
    });

    testWidgets('a removed event counts as an edit', (tester) async {
      useTallView(tester);
      await openReview(
        tester,
        planningResult(events: [planningEvent(), lunchEvent()]),
      );
      await tester.tap(find.byTooltip('Remove event').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
    });
  });

  test('field labels', () {
    expect(EventField.values.map((f) => f.label), [
      'Title',
      'Description',
      'Location',
      'Start',
      'End',
    ]);
  });
}
