import 'dart:convert';

import 'package:event_snap_2/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  EventModel event({RecurrenceRule? recurrence, DateTime? start}) => EventModel(
    id: 'e1',
    title: 'Yoga',
    startDateTime: start ?? DateTime(2026, 11, 24, 19),
    endDateTime: (start ?? DateTime(2026, 11, 24, 19)).add(
      const Duration(hours: 1),
    ),
    recurrence: recurrence,
  );

  group('RecurrenceRule', () {
    test('defaults and immutability', () {
      final rule = RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        byWeekdays: {DateTime.tuesday},
      );
      expect(rule.interval, 1);
      expect(rule.hasEnd, isFalse);
      expect(rule.isValid, isTrue);
      expect(() => rule.byWeekdays.add(1), throwsUnsupportedError);
    });

    test('until is normalised to a date', () {
      final rule = RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        until: DateTime(2026, 12, 15, 18, 30),
      );
      expect(rule.until, DateTime(2026, 12, 15));
    });

    test('equality and hashCode ignore weekday set order', () {
      final a = RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        byWeekdays: {1, 3},
        count: 4,
      );
      final b = RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        byWeekdays: {3, 1},
        count: 4,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(a.copyWith(interval: 2)));
      expect(a, isNot(a.copyWith(byWeekdays: {1})));
      expect(a, isNot(a.copyWith(clearCount: true)));
    });

    test('copyWith can clear optional values', () {
      final rule = RecurrenceRule(
        frequency: RecurrenceFrequency.monthly,
        byMonthDay: 15,
        until: DateTime(2027),
      );
      expect(rule.copyWith(clearByMonthDay: true).byMonthDay, isNull);
      expect(rule.copyWith(clearUntil: true).until, isNull);
      expect(rule.copyWith(count: 3, clearUntil: true).count, 3);
    });

    test('json round trip', () {
      final rules = [
        RecurrenceRule(frequency: RecurrenceFrequency.yearly),
        RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          interval: 2,
          byWeekdays: {5, 1},
          until: DateTime(2026, 12, 15),
        ),
        RecurrenceRule(
          frequency: RecurrenceFrequency.monthly,
          byWeekdays: {DateTime.friday},
          weekdayOrdinal: -1,
          count: 6,
        ),
        RecurrenceRule(frequency: RecurrenceFrequency.monthly, byMonthDay: 31),
      ];
      for (final rule in rules) {
        final decoded = RecurrenceRule.fromJson(
          jsonDecode(jsonEncode(rule.toJson())) as Map<String, dynamic>,
        );
        expect(decoded, rule);
      }
      expect(rules[1].toJson()['byWeekdays'], [1, 5]);
      expect(rules[1].toJson()['until'], '2026-12-15');
    });

    test('fromJson rejects an unknown frequency', () {
      expect(
        () => RecurrenceRule.fromJson({'frequency': 'hourly'}),
        throwsFormatException,
      );
    });

    group('validate', () {
      test('count and until are mutually exclusive', () {
        final rule = RecurrenceRule(
          frequency: RecurrenceFrequency.daily,
          count: 3,
          until: DateTime(2027),
        );
        expect(rule.isValid, isFalse);
      });

      test('interval and count must be at least 1', () {
        expect(
          RecurrenceRule(
            frequency: RecurrenceFrequency.daily,
            interval: 0,
          ).isValid,
          isFalse,
        );
        expect(
          RecurrenceRule(
            frequency: RecurrenceFrequency.daily,
            count: 0,
          ).isValid,
          isFalse,
        );
      });

      test('until must not be before the start date (inclusive)', () {
        final rule = RecurrenceRule(
          frequency: RecurrenceFrequency.daily,
          until: DateTime(2026, 11, 24),
        );
        expect(rule.validate(start: DateTime(2026, 11, 24, 19)), isEmpty);
        expect(rule.validate(start: DateTime(2026, 11, 25)), isNotEmpty);
      });

      test('month day and ordinal rules', () {
        expect(
          RecurrenceRule(
            frequency: RecurrenceFrequency.monthly,
            byMonthDay: 32,
          ).isValid,
          isFalse,
        );
        expect(
          RecurrenceRule(
            frequency: RecurrenceFrequency.monthly,
            byWeekdays: {1},
            weekdayOrdinal: 5,
          ).isValid,
          isFalse,
        );
        expect(
          RecurrenceRule(
            frequency: RecurrenceFrequency.monthly,
            weekdayOrdinal: 1,
          ).isValid,
          isFalse,
          reason: 'needs a weekday',
        );
        expect(
          RecurrenceRule(
            frequency: RecurrenceFrequency.monthly,
            byWeekdays: {1},
            weekdayOrdinal: 1,
            byMonthDay: 3,
          ).isValid,
          isFalse,
        );
        expect(
          RecurrenceRule(
            frequency: RecurrenceFrequency.daily,
            byMonthDay: 3,
          ).isValid,
          isFalse,
        );
      });
    });
  });

  group('EventModel.recurrence', () {
    final weekly = RecurrenceRule(
      frequency: RecurrenceFrequency.weekly,
      byWeekdays: {DateTime.tuesday},
      count: 10,
    );

    test('is null by default and part of ==/hashCode', () {
      expect(event().recurrence, isNull);
      expect(event(recurrence: weekly), event(recurrence: weekly));
      expect(
        event(recurrence: weekly).hashCode,
        event(recurrence: weekly).hashCode,
      );
      expect(event(recurrence: weekly), isNot(event()));
    });

    test('copyWith sets, keeps and clears it', () {
      final e = event(recurrence: weekly);
      expect(e.copyWith(title: 'x').recurrence, weekly);
      expect(e.copyWith(clearRecurrence: true).recurrence, isNull);
      expect(event().copyWith(recurrence: weekly).recurrence, weekly);
    });

    test('json round trip, and old json without recurrence', () {
      final e = event(recurrence: weekly);
      final decoded = EventModel.fromJson(
        jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>,
      );
      expect(decoded, e);
      expect(decoded.recurrence, weekly);

      final old = Map<String, dynamic>.from(event().toJson())
        ..remove('recurrence');
      expect(EventModel.fromJson(old).recurrence, isNull);
      expect(event().toJson()['recurrence'], isNull);
    });

    test('an unreadable stored recurrence is dropped', () {
      final json = Map<String, dynamic>.from(event().toJson())
        ..['recurrence'] = {'frequency': 'sometimes'};
      expect(EventModel.fromJson(json).recurrence, isNull);
    });

    test('validate reports rule problems', () {
      expect(event(recurrence: weekly).isValid, isTrue);
      final before = event(
        recurrence: RecurrenceRule(
          frequency: RecurrenceFrequency.daily,
          until: DateTime(2026, 11, 1),
        ),
      );
      expect(before.validate(), isNotEmpty);
      final both = event(
        recurrence: RecurrenceRule(
          frequency: RecurrenceFrequency.daily,
          count: 2,
          until: DateTime(2027),
        ),
      );
      expect(both.isValid, isFalse);
    });

    test('EventField.recurrence exists', () {
      expect(EventField.values.last, EventField.recurrence);
    });
  });
}
