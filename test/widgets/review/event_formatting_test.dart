import 'package:event_snap_2/models/event_model.dart';
import 'package:event_snap_2/widgets/review/event_formatting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// intl separates the time from AM/PM with a narrow no-break space.
const _sp = '\u202F';

void main() {
  final now = DateTime(2025, 3, 1);
  final fmt = EventFormatter(now: now);
  final fmt24 = EventFormatter(now: now, use24HourFormat: true);

  group('EventFormatter', () {
    test('omits the year only for the current year', () {
      expect(fmt.date(DateTime(2025, 5, 25)), 'Sun, May 25');
      expect(fmt.date(DateTime(2026, 5, 25)), 'Mon, May 25, 2026');
    });

    test('formats times with the 12- or 24-hour clock', () {
      final t = DateTime(2025, 5, 25, 14, 5);
      expect(fmt.time(t), '2:05${_sp}PM');
      expect(fmt24.time(t), '14:05');
    });

    test('falls back to en_US for locales without date data', () {
      final f = EventFormatter(locale: 'xx_YY', now: now);
      expect(f.locale, isNull);
      expect(f.date(DateTime(2025, 5, 25)), 'Sun, May 25');
    });

    test('formats timed ranges', () {
      final sameDay = EventModel(
        title: 'A',
        startDateTime: DateTime(2025, 5, 25, 10),
        endDateTime: DateTime(2025, 5, 25, 11, 30),
      );
      expect(fmt.range(sameDay), 'Sun, May 25 · 10:00${_sp}AM – 11:30${_sp}AM');
      expect(fmt24.range(sameDay), 'Sun, May 25 · 10:00 – 11:30');

      final untilMidnight = EventModel(
        title: 'A',
        startDateTime: DateTime(2025, 5, 25, 22),
        endDateTime: DateTime(2025, 5, 26),
      );
      expect(fmt24.range(untilMidnight), 'Sun, May 25 · 22:00 – 00:00');

      final overnight = EventModel(
        title: 'A',
        startDateTime: DateTime(2025, 5, 25, 22),
        endDateTime: DateTime(2025, 5, 26, 2),
      );
      expect(fmt24.range(overnight), 'Sun, May 25, 22:00 – Mon, May 26, 02:00');
    });

    test('formats all-day ranges with the inclusive last day', () {
      final single = EventModel(
        title: 'A',
        startDateTime: DateTime(2025, 5, 25),
        endDateTime: DateTime(2025, 5, 26),
        isAllDay: true,
      );
      expect(fmt.range(single), 'Sun, May 25');

      final multi = EventModel(
        title: 'A',
        startDateTime: DateTime(2025, 5, 25),
        endDateTime: DateTime(2025, 5, 28),
        isAllDay: true,
      );
      expect(fmt.range(multi), 'Sun, May 25 – Tue, May 27');
      expect(fmt.endValue(multi), 'Tue, May 27');
      expect(fmt.startValue(multi), 'Sun, May 25');
    });

    test('formats durations', () {
      String d(Duration duration, {bool allDay = false}) {
        final start = DateTime(2025, 5, 25);
        return fmt.duration(
          start: start,
          end: start.add(duration),
          isAllDay: allDay,
        );
      }

      expect(d(const Duration(minutes: 45)), '45 min');
      expect(d(const Duration(hours: 1)), '1 h');
      expect(d(const Duration(hours: 1, minutes: 30)), '1 h 30 min');
      expect(d(const Duration(days: 1, hours: 2)), '1 day 2 h');
      expect(d(const Duration(days: 1), allDay: true), '1 day');
      expect(d(const Duration(days: 3), allDay: true), '3 days');
      expect(d(Duration.zero), '0 min');
    });

    testWidgets('of(context) reads the 24-hour preference', (tester) async {
      late EventFormatter f;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(alwaysUse24HourFormat: true),
              child: Builder(
                builder: (context) {
                  f = EventFormatter.of(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(f.use24HourFormat, isTrue);
      expect(f.locale, 'en_US');
    });
  });
}
