import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/themes/app_theme.dart';
import 'package:event_snap_2/widgets/event_form.dart';
import 'package:event_snap_2/widgets/review/evidence_line.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fakes.dart';
import 'review/review_samples.dart';

const _sp = ' ';

void main() {
  late GlobalKey<EventFormState> formKey;
  late List<EventModel> changes;
  late List<Set<EventField>> editedReports;
  late List<EventField> focused;
  late List<EventField> shownInSource;

  setUp(() {
    formKey = GlobalKey<EventFormState>();
    changes = [];
    editedReports = [];
    focused = [];
    shownInSource = [];
  });

  Future<void> pumpForm(
    WidgetTester tester,
    EventModel event, {
    EventModel? original,
    String sourceText = planningText,
    bool use24h = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(alwaysUse24HourFormat: use24h),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: EventForm(
                  key: formKey,
                  initialEvent: event,
                  originalEvent: original,
                  sourceText: sourceText,
                  onChanged: changes.add,
                  onEditedFieldsChanged: editedReports.add,
                  onFieldFocused: focused.add,
                  onShowInSource: shownInSource.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  EventFormState form() => formKey.currentState!;

  Finder evidence(EventField field) =>
      find.byKey(ValueKey('evidence_line_${field.name}'));

  group('rendering', () {
    testWidgets('title and location wrap up to three lines', (tester) async {
      await pumpForm(tester, planningEvent());
      for (final key in const ['event_title_field', 'event_location_field']) {
        final field = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(TextField),
          ),
        );
        expect(field.minLines, 1, reason: key);
        expect(field.maxLines, 3, reason: key);
        expect(field.textInputAction, TextInputAction.next, reason: key);
      }
    });

    testWidgets('shows the values and an evidence line per field', (
      tester,
    ) async {
      await pumpForm(tester, planningEvent());

      expect(find.text('Quarterly planning meeting'), findsOneWidget);
      expect(find.text('Room 4B, Oslo office'), findsOneWidget);
      expect(find.text('Bring your Q3 numbers.'), findsOneWidget);
      expect(find.text('Thu, Jun 5, 2025'), findsNothing);
      expect(find.textContaining('Jun 6'), findsNWidgets(2));
      expect(find.text('2:00${_sp}PM'), findsOneWidget);
      expect(find.text('4:30${_sp}PM'), findsOneWidget);
      expect(find.text('2 h 30 min'), findsOneWidget);
      for (final field in EventField.values) {
        if (field == EventField.recurrence) continue;
        expect(evidence(field), findsOneWidget, reason: field.name);
      }
      expect(find.text('Does not repeat'), findsOneWidget);
      expect(evidence(EventField.recurrence), findsNothing);
      // Only the low-confidence description asks for a check.
      expect(
        find.descendant(
          of: evidence(EventField.description),
          matching: find.byType(CheckBadge),
        ),
        findsOneWidget,
      );
      expect(find.byType(CheckBadge), findsOneWidget);
    });

    testWidgets('uses the 24-hour clock when the system asks for it', (
      tester,
    ) async {
      await pumpForm(tester, planningEvent(), use24h: true);
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('16:30'), findsOneWidget);
    });

    testWidgets('hides evidence for empty fields and shows nothing without '
        'evidence', (tester) async {
      await pumpForm(
        tester,
        sampleEvent(
          evidence: const {
            EventField.location: FieldEvidence(
              reasoning: 'No location mentioned.',
              confidence: EvidenceConfidence.high,
            ),
          },
        ),
      );
      expect(evidence(EventField.location), findsNothing);
      expect(find.byType(EvidenceLine), findsNothing);
    });
  });

  group('edits', () {
    testWidgets('editing a field shows "Edited by you" and reports it; '
        'reverting restores the reasoning', (tester) async {
      await pumpForm(tester, planningEvent());

      await tester.enterText(
        find.byKey(const ValueKey('event_title_field')),
        'Planning',
      );
      await tester.pump();

      expect(
        find.descendant(
          of: evidence(EventField.title),
          matching: find.text('Edited by you'),
        ),
        findsOneWidget,
      );
      expect(editedReports.last, {EventField.title});
      expect(changes.last.title, 'Planning');
      expect(form().editedFields, {EventField.title});

      await tester.enterText(
        find.byKey(const ValueKey('event_title_field')),
        'Quarterly planning meeting',
      );
      await tester.pump();
      expect(find.text('Edited by you'), findsNothing);
      expect(editedReports.last, isEmpty);
    });

    testWidgets('editing a low-confidence field removes its Check badge', (
      tester,
    ) async {
      await pumpForm(tester, planningEvent());
      expect(find.byType(CheckBadge), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('event_description_field')),
        'Bring Q3 numbers and laptops.',
      );
      await tester.pump();
      expect(find.byType(CheckBadge), findsNothing);
      expect(find.text('Edited by you'), findsOneWidget);
    });

    testWidgets('a field differing from the original starts as edited', (
      tester,
    ) async {
      final original = planningEvent();
      await pumpForm(
        tester,
        original.copyWith(location: 'Room 5'),
        original: original,
      );
      expect(form().editedFields, {EventField.location});
      expect(
        find.descendant(
          of: evidence(EventField.location),
          matching: find.text('Edited by you'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('focusing a field and tapping evidence report the field', (
      tester,
    ) async {
      await pumpForm(tester, planningEvent());
      await tester.tap(find.byKey(const ValueKey('event_location_field')));
      await tester.pump();
      expect(focused.last, EventField.location);

      await tester.tap(find.byKey(const ValueKey('evidence_start')));
      await tester.pumpAndSettle();
      expect(focused.last, EventField.start);
      await tester.tap(find.text('Show in source'));
      expect(shownInSource, [EventField.start]);
    });
  });

  group('dates and times', () {
    testWidgets('changing the start date keeps the duration', (tester) async {
      await pumpForm(tester, planningEvent());

      await tester.tap(find.byKey(const ValueKey('event_start_date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(form().start, DateTime(2025, 6, 9, 14));
      expect(form().end, DateTime(2025, 6, 9, 16, 30));
      expect(find.text('2 h 30 min'), findsOneWidget);
      expect(form().editedFields, {EventField.start, EventField.end});
      expect(changes.last.startDateTime, DateTime(2025, 6, 9, 14));
      expect(focused, contains(EventField.start));
    });

    testWidgets('changing the start time keeps the duration', (tester) async {
      await pumpForm(tester, planningEvent());

      await tester.tap(find.byKey(const ValueKey('event_start_time')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final dialogFields = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), '09');
      await tester.enterText(dialogFields.at(1), '15');
      await tester.tap(find.text('AM'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(form().start, DateTime(2025, 6, 6, 9, 15));
      expect(form().end, DateTime(2025, 6, 6, 11, 45));
      expect(find.text('9:15${_sp}AM'), findsOneWidget);
      expect(find.text('11:45${_sp}AM'), findsOneWidget);
    });

    testWidgets('setStart shifts all-day events by whole days', (tester) async {
      await pumpForm(
        tester,
        sampleEvent(
          isAllDay: true,
          start: DateTime(2025, 5, 25),
          duration: const Duration(days: 3),
        ),
      );
      form().setStart(DateTime(2025, 5, 30, 15));
      await tester.pump();
      expect(form().start, DateTime(2025, 5, 30));
      expect(form().end, DateTime(2025, 6, 2));
      expect(find.text('3 days'), findsOneWidget);
    });

    testWidgets('an end before the start shows an error and fails '
        'validation', (tester) async {
      await pumpForm(tester, planningEvent());
      form().setEnd(DateTime(2025, 6, 6, 13));
      await tester.pump();

      expect(find.text('End must be after start'), findsOneWidget);
      expect(find.byKey(const ValueKey('event_duration_chip')), findsNothing);
      expect(form().validateForm(), isFalse);
    });

    testWidgets('an empty title fails validation', (tester) async {
      await pumpForm(tester, planningEvent());
      await tester.enterText(
        find.byKey(const ValueKey('event_title_field')),
        '  ',
      );
      await tester.pump();
      expect(form().validateForm(), isFalse);
      await tester.pump();
      expect(find.text('Add a title'), findsOneWidget);
      // Invalid states are not reported as events.
      expect(changes.where((e) => e.title.trim().isEmpty), isEmpty);
    });
  });

  group('all-day', () {
    testWidgets('toggling all-day covers the days and restores the times', (
      tester,
    ) async {
      await pumpForm(tester, planningEvent());
      expect(find.byKey(const ValueKey('event_start_time')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('event_all_day_switch')));
      await tester.pumpAndSettle();

      expect(form().isAllDay, isTrue);
      expect(form().start, DateTime(2025, 6, 6));
      expect(form().end, DateTime(2025, 6, 7));
      expect(find.byKey(const ValueKey('event_start_time')), findsNothing);
      expect(find.byKey(const ValueKey('event_end_time')), findsNothing);
      expect(find.text('1 day'), findsOneWidget);
      // End shows the inclusive last day.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('event_end_date')),
          matching: find.textContaining('Jun 6'),
        ),
        findsOneWidget,
      );
      final model = form().getCurrentEventModel();
      expect(model.isAllDay, isTrue);
      expect(model.lastDay, DateTime(2025, 6, 6));
      expect(changes.last.isAllDay, isTrue);

      await tester.tap(find.byKey(const ValueKey('event_all_day_switch')));
      await tester.pumpAndSettle();
      expect(form().isAllDay, isFalse);
      expect(form().start, DateTime(2025, 6, 6, 14));
      expect(form().end, DateTime(2025, 6, 6, 16, 30));
      expect(form().editedFields, isEmpty);
    });

    testWidgets('turning off an AI all-day event defaults to 09:00 for an '
        'hour', (tester) async {
      await pumpForm(
        tester,
        sampleEvent(isAllDay: true, start: DateTime(2025, 5, 25)),
      );
      form().setAllDay(false);
      await tester.pump();
      expect(form().start, DateTime(2025, 5, 25, 9));
      expect(form().end, DateTime(2025, 5, 25, 10));
    });

    testWidgets('turning off a multi-day all-day event keeps the last day', (
      tester,
    ) async {
      await pumpForm(
        tester,
        sampleEvent(
          isAllDay: true,
          start: DateTime(2025, 5, 25),
          duration: const Duration(days: 3),
        ),
      );
      form().setAllDay(false);
      await tester.pump();
      expect(form().start, DateTime(2025, 5, 25, 9));
      expect(form().end, DateTime(2025, 5, 27, 10));
    });

    testWidgets('changing the end date of an all-day event sets the last day', (
      tester,
    ) async {
      await pumpForm(
        tester,
        sampleEvent(isAllDay: true, start: DateTime(2025, 5, 25)),
      );
      await tester.tap(find.byKey(const ValueKey('event_end_date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('27'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(form().end, DateTime(2025, 5, 28));
      expect(form().getCurrentEventModel().lastDay, DateTime(2025, 5, 27));
      expect(find.text('3 days'), findsOneWidget);
    });
  });
}
