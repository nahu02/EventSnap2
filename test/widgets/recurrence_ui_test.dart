import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/themes/app_theme.dart';
import 'package:event_snap_2/widgets/event_form.dart';
import 'package:event_snap_2/widgets/review/evidence_line.dart';
import 'package:event_snap_2/widgets/review/event_formatting.dart';
import 'package:event_snap_2/widgets/review/review_event_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // Tuesday, December 1st 2026: the first Tuesday of the month.
  final start = DateTime(2026, 12, 1, 19);
  final end = DateTime(2026, 12, 1, 20);

  EventModel event({
    RecurrenceRule? recurrence,
    Map<EventField, FieldEvidence> evidence = const {},
  }) => EventModel(
    id: 'e1',
    title: 'Yoga',
    startDateTime: start,
    endDateTime: end,
    recurrence: recurrence,
    evidence: evidence,
  );

  late GlobalKey<EventFormState> formKey;
  late List<EventModel> changes;

  Future<void> pumpForm(
    WidgetTester tester,
    EventModel initial, {
    EventModel? original,
  }) async {
    formKey = GlobalKey<EventFormState>();
    changes = [];
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: EventForm(
              key: formKey,
              initialEvent: initial,
              originalEvent: original,
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder summary() => find.byKey(const ValueKey('event_repeats_summary'));
  String summaryText(WidgetTester tester) =>
      tester.widget<Text>(summary()).data!;
  Finder tapKey(String key) => find.byKey(ValueKey(key));

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('event_repeats_row')));
    await tester.pumpAndSettle();
  }

  Future<void> tapKeyAndSettle(WidgetTester tester, String key) async {
    final finder = tapKey(key);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('EventFormatter.recurrence', () {
    final fmt = EventFormatter(locale: 'en_US');

    test('summaries', () {
      expect(fmt.recurrence(null, start), 'Does not repeat');
      expect(
        fmt.recurrence(
          RecurrenceRule(
            frequency: RecurrenceFrequency.weekly,
            byWeekdays: {DateTime.wednesday, DateTime.monday},
            until: DateTime(2026, 12, 15),
          ),
          start,
        ),
        'Every week on Mon, Wed · until Dec 15, 2026',
      );
      expect(
        fmt.recurrence(
          RecurrenceRule(
            frequency: RecurrenceFrequency.weekly,
            interval: 2,
            byWeekdays: {DateTime.friday},
            count: 10,
          ),
          start,
        ),
        'Every 2 weeks on Fri · 10 times',
      );
      expect(
        fmt.recurrence(
          RecurrenceRule(
            frequency: RecurrenceFrequency.monthly,
            byWeekdays: {DateTime.tuesday},
            weekdayOrdinal: 1,
          ),
          start,
        ),
        'Monthly on the first Tuesday',
      );
      expect(
        fmt.recurrence(
          RecurrenceRule(
            frequency: RecurrenceFrequency.monthly,
            interval: 3,
            byWeekdays: {DateTime.friday},
            weekdayOrdinal: -1,
          ),
          start,
        ),
        'Every 3 months on the last Friday',
      );
      expect(
        fmt.recurrence(
          RecurrenceRule(frequency: RecurrenceFrequency.monthly),
          start,
        ),
        'Monthly on day 1',
      );
      expect(
        fmt.recurrence(
          RecurrenceRule(
            frequency: RecurrenceFrequency.monthly,
            byMonthDay: 15,
          ),
          start,
        ),
        'Monthly on day 15',
      );
      expect(
        fmt.recurrence(
          RecurrenceRule(frequency: RecurrenceFrequency.yearly),
          start,
        ),
        'Every year',
      );
      expect(
        fmt.recurrence(
          RecurrenceRule(frequency: RecurrenceFrequency.daily, count: 1),
          start,
        ),
        'Every day · 1 time',
      );
      expect(
        fmt.recurrence(
          RecurrenceRule(frequency: RecurrenceFrequency.weekly),
          start,
        ),
        'Every week on Tue',
      );
    });

    test('dates and weekday names follow the locale', () async {
      await initializeDateFormatting('de');
      final de = EventFormatter(locale: 'de');
      expect(
        de.recurrence(
          RecurrenceRule(
            frequency: RecurrenceFrequency.daily,
            until: DateTime(2026, 12, 15),
          ),
          start,
        ),
        contains('15. Dez. 2026'),
      );
    });
  });

  group('Repeats row', () {
    testWidgets('shows "Does not repeat" for a one-off event', (tester) async {
      await pumpForm(tester, event());
      expect(summaryText(tester), 'Does not repeat');
      expect(find.byIcon(Icons.repeat), findsOneWidget);
    });

    testWidgets('shows the summary of the rule', (tester) async {
      await pumpForm(
        tester,
        event(
          recurrence: RecurrenceRule(
            frequency: RecurrenceFrequency.weekly,
            byWeekdays: {DateTime.monday, DateTime.wednesday},
            until: DateTime(2026, 12, 15),
          ),
        ),
      );
      expect(
        summaryText(tester),
        'Every week on Mon, Wed · until Dec 15, 2026',
      );
    });

    testWidgets('shows the recurrence evidence line, with a Check badge', (
      tester,
    ) async {
      await pumpForm(
        tester,
        event(
          recurrence: RecurrenceRule(frequency: RecurrenceFrequency.yearly),
          evidence: const {
            EventField.recurrence: FieldEvidence(
              quote: 'every year',
              reasoning: 'Guessed from "annual".',
              confidence: EvidenceConfidence.low,
            ),
          },
        ),
      );
      final line = find.byKey(const ValueKey('evidence_line_recurrence'));
      expect(line, findsOneWidget);
      expect(
        find.descendant(of: line, matching: find.byType(CheckBadge)),
        findsOneWidget,
      );
    });

    testWidgets('editing: weekly, two weekdays, after 5 times', (tester) async {
      await pumpForm(tester, event());
      await openEditor(tester);
      expect(find.text('Repeats'), findsWidgets);

      await tapKeyAndSettle(tester, 'recurrence_freq_weekly');
      // The start weekday (Tuesday) is preselected.
      await tapKeyAndSettle(tester, 'recurrence_weekday_4'); // + Thursday
      await tapKeyAndSettle(tester, 'recurrence_interval_plus');
      await tester.tap(find.text('After'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tapKeyAndSettle(tester, 'recurrence_count_minus');
      }
      expect(
        tester.widget<Text>(tapKey('recurrence_preview')).data,
        'Every 2 weeks on Tue, Thu · 5 times',
      );
      await tapKeyAndSettle(tester, 'recurrence_done');

      final rule = formKey.currentState!.getCurrentEventModel().recurrence!;
      expect(rule.frequency, RecurrenceFrequency.weekly);
      expect(rule.interval, 2);
      expect(rule.byWeekdays, {DateTime.tuesday, DateTime.thursday});
      expect(rule.count, 5);
      expect(rule.until, isNull);
      expect(summaryText(tester), 'Every 2 weeks on Tue, Thu · 5 times');
      expect(changes.last.recurrence, rule);
    });

    testWidgets('the last weekday cannot be deselected', (tester) async {
      await pumpForm(tester, event());
      await openEditor(tester);
      await tapKeyAndSettle(tester, 'recurrence_freq_weekly');
      await tapKeyAndSettle(tester, 'recurrence_weekday_2');
      expect(
        tester.widget<Text>(tapKey('recurrence_preview')).data,
        'Every week on Tue',
      );
    });

    testWidgets('monthly: choose the nth weekday', (tester) async {
      await pumpForm(tester, event());
      await openEditor(tester);
      await tapKeyAndSettle(tester, 'recurrence_freq_monthly');
      expect(
        tester.widget<Text>(tapKey('recurrence_preview')).data,
        'Monthly on day 1',
      );
      await tester.tap(find.text('On the first Tuesday'));
      await tester.pumpAndSettle();
      await tapKeyAndSettle(tester, 'recurrence_done');
      final rule = formKey.currentState!.recurrence!;
      expect(rule.weekdayOrdinal, 1);
      expect(rule.byWeekdays, {DateTime.tuesday});
      expect(rule.byMonthDay, isNull);
      expect(summaryText(tester), 'Monthly on the first Tuesday');
    });

    testWidgets('ends on a date chosen with the date picker', (tester) async {
      await pumpForm(tester, event());
      await openEditor(tester);
      await tapKeyAndSettle(tester, 'recurrence_freq_daily');
      await tester.tap(find.text('On date'));
      await tester.pumpAndSettle();
      await tapKeyAndSettle(tester, 'recurrence_until_button');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tapKeyAndSettle(tester, 'recurrence_done');
      final rule = formKey.currentState!.recurrence!;
      // Default: three months after the start.
      expect(rule.until, DateTime(2027, 3, 1));
      expect(rule.count, isNull);
    });

    testWidgets('choosing "Does not repeat" clears the rule', (tester) async {
      await pumpForm(
        tester,
        event(recurrence: RecurrenceRule(frequency: RecurrenceFrequency.daily)),
      );
      expect(summaryText(tester), 'Every day');
      await openEditor(tester);
      await tapKeyAndSettle(tester, 'recurrence_freq_none');
      await tapKeyAndSettle(tester, 'recurrence_done');
      expect(formKey.currentState!.recurrence, isNull);
      expect(summaryText(tester), 'Does not repeat');
    });

    testWidgets('cancelling keeps the rule', (tester) async {
      await pumpForm(
        tester,
        event(recurrence: RecurrenceRule(frequency: RecurrenceFrequency.daily)),
      );
      await openEditor(tester);
      await tapKeyAndSettle(tester, 'recurrence_freq_yearly');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(summaryText(tester), 'Every day');
    });

    testWidgets('editing shows "Edited by you" with the suggestion', (
      tester,
    ) async {
      final original = event(
        recurrence: RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          byWeekdays: {DateTime.tuesday},
        ),
        evidence: const {
          EventField.recurrence: FieldEvidence(
            quote: 'every Tuesday',
            reasoning: 'Stated.',
            confidence: EvidenceConfidence.low,
          ),
        },
      );
      await pumpForm(tester, original);
      final edited = <Set<EventField>>[];
      expect(formKey.currentState!.editedFields, isEmpty);
      expect(find.textContaining('Edited by you'), findsNothing);

      await openEditor(tester);
      await tapKeyAndSettle(tester, 'recurrence_freq_daily');
      await tapKeyAndSettle(tester, 'recurrence_done');
      edited.add(formKey.currentState!.editedFields);

      expect(edited.single, {EventField.recurrence});
      final line = find.byKey(const ValueKey('evidence_line_recurrence'));
      expect(
        find.descendant(
          of: line,
          matching: find.textContaining('Edited by you'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.byType(CheckBadge)),
        findsNothing,
      );
    });
  });

  group('start date changes', () {
    testWidgets('a weekly rule on the old weekday moves to the new weekday', (
      tester,
    ) async {
      await pumpForm(
        tester,
        event(
          recurrence: RecurrenceRule(
            frequency: RecurrenceFrequency.weekly,
            byWeekdays: {DateTime.tuesday},
          ),
        ),
      );
      formKey.currentState!.setStart(DateTime(2026, 12, 4, 19)); // Friday
      await tester.pumpAndSettle();
      expect(formKey.currentState!.recurrence!.byWeekdays, {DateTime.friday});
      expect(summaryText(tester), 'Every week on Fri');
    });

    testWidgets('other weekly selections are kept', (tester) async {
      final rule = RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        byWeekdays: {DateTime.tuesday, DateTime.thursday},
      );
      await pumpForm(tester, event(recurrence: rule));
      formKey.currentState!.setStart(DateTime(2026, 12, 4, 19));
      await tester.pumpAndSettle();
      expect(formKey.currentState!.recurrence, rule);
    });

    testWidgets('a monthly day or nth weekday follows the new date', (
      tester,
    ) async {
      await pumpForm(
        tester,
        event(
          recurrence: RecurrenceRule(
            frequency: RecurrenceFrequency.monthly,
            byMonthDay: 1,
          ),
        ),
      );
      formKey.currentState!.setStart(DateTime(2026, 12, 9, 19));
      await tester.pumpAndSettle();
      expect(formKey.currentState!.recurrence!.byMonthDay, 9);

      await pumpForm(
        tester,
        event(
          recurrence: RecurrenceRule(
            frequency: RecurrenceFrequency.monthly,
            byWeekdays: {DateTime.tuesday},
            weekdayOrdinal: 1,
          ),
        ),
      );
      formKey.currentState!.setStart(DateTime(2026, 12, 9, 19)); // 2nd Wed
      await tester.pumpAndSettle();
      final rule = formKey.currentState!.recurrence!;
      expect(rule.weekdayOrdinal, 2);
      expect(rule.byWeekdays, {DateTime.wednesday});
    });

    testWidgets('an end date before the new start moves to it', (tester) async {
      await pumpForm(
        tester,
        event(
          recurrence: RecurrenceRule(
            frequency: RecurrenceFrequency.daily,
            until: DateTime(2026, 12, 10),
          ),
        ),
      );
      formKey.currentState!.setStart(DateTime(2026, 12, 20, 19));
      await tester.pumpAndSettle();
      expect(formKey.currentState!.recurrence!.until, DateTime(2026, 12, 20));
      expect(formKey.currentState!.validateForm(), isTrue);
    });
  });

  group('ReviewEventCard', () {
    Future<void> pumpCard(WidgetTester tester, EventModel e) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ReviewEventCard(
              event: e,
              expanded: false,
              child: const SizedBox(),
            ),
          ),
        ),
      );
    }

    testWidgets('shows a Repeats pill only for recurring events', (
      tester,
    ) async {
      await pumpCard(tester, event());
      expect(find.text('Repeats'), findsNothing);
      await pumpCard(
        tester,
        event(recurrence: RecurrenceRule(frequency: RecurrenceFrequency.daily)),
      );
      expect(find.text('Repeats'), findsOneWidget);
    });
  });

  testWidgets('the editor fits large text without overflow', (tester) async {
    await pumpForm(
      tester,
      event(
        recurrence: RecurrenceRule(
          frequency: RecurrenceFrequency.monthly,
          byWeekdays: {DateTime.tuesday},
          weekdayOrdinal: 1,
          until: DateTime(2027, 1, 1),
        ),
      ),
    );
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openEditor(tester);
    expect(tester.takeException(), isNull);
  });
}
