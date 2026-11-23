import 'dart:convert';

import 'package:event_snap_2/models/event_model.dart';
import 'package:event_snap_2/models/recurrence.dart';
import 'package:event_snap_2/services/calendar/ical_serializer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final stamp = DateTime.utc(2025, 11, 21, 12, 30, 5);

  EventModel timed({
    String id = 'evt-1',
    String title = 'Team Meeting',
    String? description,
    String? location,
  }) {
    final start = DateTime.utc(2025, 5, 28, 14);
    return EventModel(
      id: id,
      title: title,
      description: description,
      location: location,
      startDateTime: start,
      endDateTime: start.add(const Duration(hours: 1)),
    );
  }

  /// Unfolds and splits into logical content lines.
  List<String> contentLines(String ics) =>
      ics.replaceAll('\r\n ', '').split('\r\n')..removeLast();

  group('ICalSerializer.serialize', () {
    test('produces a complete calendar with required properties', () {
      final ics = ICalSerializer.serialize([timed()], timestamp: stamp);
      expect(contentLines(ics), [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//EventSnap//EventSnap2 3.0//EN',
        'CALSCALE:GREGORIAN',
        'METHOD:PUBLISH',
        'BEGIN:VEVENT',
        'UID:evt-1@eventsnap.app',
        'DTSTAMP:20251121T123005Z',
        'DTSTART:20250528T140000Z',
        'DTEND:20250528T150000Z',
        'SUMMARY:Team Meeting',
        'END:VEVENT',
        'END:VCALENDAR',
      ]);
    });

    test('uses CRLF line endings everywhere, including the last line', () {
      final ics = ICalSerializer.serialize([timed()], timestamp: stamp);
      expect(ics.endsWith('END:VCALENDAR\r\n'), isTrue);
      expect(ics.replaceAll('\r\n', '').contains('\n'), isFalse);
      expect(ics.replaceAll('\r\n', '').contains('\r'), isFalse);
    });

    test('converts local times to UTC', () {
      final local = DateTime(2025, 7, 1, 9, 15);
      final event = EventModel(
        id: 'x',
        title: 'Local',
        startDateTime: local,
        endDateTime: local.add(const Duration(minutes: 45)),
      );
      final lines = contentLines(
        ICalSerializer.serialize([event], timestamp: stamp),
      );
      final expectedStart = ICalSerializer.formatUtcDateTime(local.toUtc());
      expect(lines, contains('DTSTART:$expectedStart'));
      expect(expectedStart, endsWith('Z'));
    });

    test('all-day events use VALUE=DATE with exclusive end', () {
      final event = EventModel(
        id: 'fest',
        title: 'Festival',
        startDateTime: DateTime(2025, 6, 1),
        endDateTime: DateTime(2025, 6, 4),
        isAllDay: true,
      );
      final lines = contentLines(
        ICalSerializer.serialize([event], timestamp: stamp),
      );
      expect(lines, contains('DTSTART;VALUE=DATE:20250601'));
      expect(lines, contains('DTEND;VALUE=DATE:20250604'));
      expect(lines.where((l) => l.startsWith('DTSTART:')), isEmpty);
    });

    test('includes description and location when present', () {
      final lines = contentLines(
        ICalSerializer.serialize([
          timed(description: 'Weekly sync', location: 'Room A'),
        ], timestamp: stamp),
      );
      expect(lines, contains('DESCRIPTION:Weekly sync'));
      expect(lines, contains('LOCATION:Room A'));
    });

    test('omits blank description and location', () {
      final ics = ICalSerializer.serialize([
        timed(description: '   ', location: ''),
      ], timestamp: stamp);
      expect(ics, isNot(contains('DESCRIPTION')));
      expect(ics, isNot(contains('LOCATION')));
    });

    test('escapes TEXT values', () {
      final lines = contentLines(
        ICalSerializer.serialize([
          timed(
            title: r'Meeting; with "Special", Chars \ & Symbols',
            description: 'Line 1\nLine 2\r\nLine 3\rEnd',
            location: 'Room #123, Hall; B',
          ),
        ], timestamp: stamp),
      );
      expect(
        lines,
        contains(r'SUMMARY:Meeting\; with "Special"\, Chars \\ & Symbols'),
      );
      expect(lines, contains(r'DESCRIPTION:Line 1\nLine 2\nLine 3\nEnd'));
      expect(lines, contains(r'LOCATION:Room #123\, Hall\; B'));
    });

    test('writes one VEVENT per event with distinct UIDs', () {
      final ics = ICalSerializer.serialize([
        timed(id: 'a', title: 'Event 1'),
        timed(id: 'b', title: 'Event 2'),
      ], timestamp: stamp);
      expect('BEGIN:VEVENT'.allMatches(ics), hasLength(2));
      expect('END:VEVENT'.allMatches(ics), hasLength(2));
      expect(ics, contains('UID:a@eventsnap.app'));
      expect(ics, contains('UID:b@eventsnap.app'));
      expect('BEGIN:VCALENDAR'.allMatches(ics), hasLength(1));
    });

    test('auto-generated ids give unique UIDs', () {
      final start = DateTime(2025, 5, 28, 10);
      EventModel make() => EventModel(
        title: 'Same',
        startDateTime: start,
        endDateTime: start.add(const Duration(hours: 1)),
      );
      final ics = ICalSerializer.serialize([make(), make()], timestamp: stamp);
      final uids = RegExp(
        r'^UID:(.+)$',
        multiLine: true,
      ).allMatches(contentLines(ics).join('\n')).map((m) => m.group(1)).toSet();
      expect(uids, hasLength(2));
    });

    test('folds long lines at 75 octets', () {
      final description = List.filled(40, 'word').join(' ');
      final ics = ICalSerializer.serialize([
        timed(description: description),
      ], timestamp: stamp);
      for (final physical in ics.split('\r\n')) {
        expect(utf8.encode(physical).length, lessThanOrEqualTo(75));
      }
      expect(contentLines(ics), contains('DESCRIPTION:$description'));
    });

    test('rejects an empty event list', () {
      expect(
        () => ICalSerializer.serialize([], timestamp: stamp),
        throwsArgumentError,
      );
    });

    test('rejects invalid events', () {
      final event = timed();
      event.endDateTime = event.startDateTime.subtract(
        const Duration(hours: 1),
      );
      expect(
        () => ICalSerializer.serialize([event], timestamp: stamp),
        throwsArgumentError,
      );
      final untitled = timed()..title = '  ';
      expect(
        () => ICalSerializer.serialize([untitled], timestamp: stamp),
        throwsArgumentError,
      );
    });
  });

  group('ICalSerializer.escapeText', () {
    test('escapes backslash first', () {
      expect(ICalSerializer.escapeText(r'a\;b'), r'a\\\;b');
    });

    test('leaves colons, quotes and unicode alone', () {
      expect(ICalSerializer.escapeText('Zeit: "Café" 🎉'), 'Zeit: "Café" 🎉');
    });

    test('drops control characters except TAB', () {
      expect(ICalSerializer.escapeText('a\u0000b\u0007c\td\u007f'), 'abc\td');
    });
  });

  group('ICalSerializer.foldLine', () {
    test('short lines are unchanged', () {
      final line = 'A' * 75;
      expect(ICalSerializer.foldLine(line), line);
    });

    test('76 ASCII octets fold into 75 + space + 1', () {
      final folded = ICalSerializer.foldLine('A' * 76);
      expect(folded, '${'A' * 75}\r\n A');
    });

    test('continuation lines carry at most 74 content octets', () {
      final folded = ICalSerializer.foldLine('B' * 200);
      final parts = folded.split('\r\n');
      expect(parts.first.length, 75);
      for (final part in parts.skip(1)) {
        expect(part.startsWith(' '), isTrue);
        expect(utf8.encode(part).length, lessThanOrEqualTo(75));
      }
      expect(parts.map((p) => p.trimLeft()).join(), 'B' * 200);
    });

    test('never splits multi-byte UTF-8 sequences', () {
      // 'é' is 2 octets, '€' is 3, '🎉' is 4 (a surrogate pair in Dart).
      for (final char in ['é', '€', '🎉']) {
        final line = 'SUMMARY:${List.filled(60, char).join()}';
        final folded = ICalSerializer.foldLine(line);
        final parts = folded.split('\r\n');
        expect(parts.length, greaterThan(1));
        for (final part in parts) {
          final bytes = utf8.encode(part);
          expect(bytes.length, lessThanOrEqualTo(75));
          // Each physical line must be valid UTF-8 on its own.
          expect(utf8.decode(bytes), part);
        }
        // Unfolding restores the original line.
        expect(folded.replaceAll('\r\n ', ''), line);
      }
    });

    test('the octet limit is reached exactly where possible', () {
      // 'SUMMARY:' (8) + 33 x 'é' (66) = 74, next 'é' would make 76.
      final line = 'SUMMARY:${'é' * 40}';
      final first = ICalSerializer.foldLine(line).split('\r\n').first;
      expect(utf8.encode(first).length, 74);
    });
  });

  group('formatting helpers', () {
    test('formatUtcDateTime pads all components', () {
      expect(
        ICalSerializer.formatUtcDateTime(DateTime.utc(2025, 1, 2, 3, 4, 5)),
        '20250102T030405Z',
      );
    });

    test('formatDate uses the local calendar date', () {
      expect(ICalSerializer.formatDate(DateTime(2025, 12, 31)), '20251231');
    });
  });

  group('recurring events', () {
    // Monday 2026-11-23, 10:00-11:00 local.
    EventModel recurring(RecurrenceRule rule, {bool allDay = false}) =>
        EventModel(
          id: 'evt-r',
          title: 'Yoga',
          startDateTime: allDay
              ? DateTime(2026, 11, 23)
              : DateTime(2026, 11, 23, 10),
          endDateTime: allDay
              ? DateTime(2026, 11, 24)
              : DateTime(2026, 11, 23, 11),
          isAllDay: allDay,
          recurrence: rule,
        );

    List<String> lines(EventModel e) =>
        contentLines(ICalSerializer.serialize([e], timestamp: stamp));

    String rrule(EventModel e) =>
        lines(e).firstWhere((l) => l.startsWith('RRULE:')).substring(6);

    test('timed recurring events use floating local time', () {
      final out = lines(
        recurring(
          RecurrenceRule(
            frequency: RecurrenceFrequency.weekly,
            byWeekdays: {DateTime.monday, DateTime.wednesday},
            until: DateTime(2026, 12, 15),
          ),
        ),
      );
      expect(out, contains('DTSTART:20261123T100000'));
      expect(out, contains('DTEND:20261123T110000'));
      expect(out.where((l) => l.startsWith('DTSTART')), hasLength(1));
      expect(out.join('\n'), isNot(contains('TZID')));
      expect(
        out,
        contains('RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261215T235959'),
      );
      // The RRULE follows DTEND and precedes SUMMARY.
      expect(
        out.indexOf('DTEND:20261123T110000') + 1,
        out.indexOf(out.firstWhere((l) => l.startsWith('RRULE'))),
      );
    });

    test('one-off events keep the UTC format and have no RRULE', () {
      final out = lines(timed());
      expect(out, contains('DTSTART:20250528T140000Z'));
      expect(out.any((l) => l.startsWith('RRULE')), isFalse);
    });

    test('all-day recurring events keep VALUE=DATE and a date UNTIL', () {
      final out = lines(
        recurring(
          RecurrenceRule(
            frequency: RecurrenceFrequency.daily,
            until: DateTime(2026, 12, 15),
          ),
          allDay: true,
        ),
      );
      expect(out, contains('DTSTART;VALUE=DATE:20261123'));
      expect(out, contains('DTEND;VALUE=DATE:20261124'));
      expect(out, contains('RRULE:FREQ=DAILY;UNTIL=20261215'));
    });

    test('daily with interval and count', () {
      expect(
        rrule(
          recurring(
            RecurrenceRule(
              frequency: RecurrenceFrequency.daily,
              interval: 3,
              count: 5,
            ),
          ),
        ),
        'FREQ=DAILY;INTERVAL=3;COUNT=5',
      );
    });

    test(
      'weekly without weekdays uses the start weekday; sorted otherwise',
      () {
        expect(
          rrule(
            recurring(RecurrenceRule(frequency: RecurrenceFrequency.weekly)),
          ),
          'FREQ=WEEKLY;BYDAY=MO',
        );
        expect(
          rrule(
            recurring(
              RecurrenceRule(
                frequency: RecurrenceFrequency.weekly,
                interval: 2,
                byWeekdays: {
                  DateTime.sunday,
                  DateTime.friday,
                  DateTime.tuesday,
                },
                count: 10,
              ),
            ),
          ),
          'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,FR,SU;COUNT=10',
        );
      },
    );

    test('monthly by day number, defaulting to the start day', () {
      expect(
        rrule(
          recurring(
            RecurrenceRule(
              frequency: RecurrenceFrequency.monthly,
              byMonthDay: 15,
            ),
          ),
        ),
        'FREQ=MONTHLY;BYMONTHDAY=15',
      );
      expect(
        rrule(
          recurring(RecurrenceRule(frequency: RecurrenceFrequency.monthly)),
        ),
        'FREQ=MONTHLY;BYMONTHDAY=23',
      );
    });

    test('monthly on the first Tuesday and the last Friday', () {
      expect(
        rrule(
          recurring(
            RecurrenceRule(
              frequency: RecurrenceFrequency.monthly,
              byWeekdays: {DateTime.tuesday},
              weekdayOrdinal: 1,
            ),
          ),
        ),
        'FREQ=MONTHLY;BYDAY=1TU',
      );
      expect(
        rrule(
          recurring(
            RecurrenceRule(
              frequency: RecurrenceFrequency.monthly,
              interval: 2,
              byWeekdays: {DateTime.friday},
              weekdayOrdinal: -1,
              until: DateTime(2027, 6, 30),
            ),
          ),
        ),
        'FREQ=MONTHLY;INTERVAL=2;BYDAY=-1FR;UNTIL=20270630T235959',
      );
    });

    test('yearly', () {
      expect(
        rrule(recurring(RecurrenceRule(frequency: RecurrenceFrequency.yearly))),
        'FREQ=YEARLY',
      );
      expect(
        rrule(
          recurring(
            RecurrenceRule(frequency: RecurrenceFrequency.yearly, interval: 2),
          ),
        ),
        'FREQ=YEARLY;INTERVAL=2',
      );
    });

    test('a long RRULE line is folded and unfolds losslessly', () {
      final ics = ICalSerializer.serialize([
        recurring(
          RecurrenceRule(
            frequency: RecurrenceFrequency.weekly,
            interval: 12,
            byWeekdays: {1, 2, 3, 4, 5, 6, 7},
            until: DateTime(2026, 12, 15),
          ),
        ),
      ], timestamp: stamp);
      const expected =
          'RRULE:FREQ=WEEKLY;INTERVAL=12;BYDAY=MO,TU,WE,TH,FR,SA,SU;'
          'UNTIL=20261215T235959';
      expect(expected.length, greaterThan(75));
      for (final physical in ics.split('\r\n')) {
        expect(utf8.encode(physical).length, lessThanOrEqualTo(75));
      }
      expect(contentLines(ics), contains(expected));
    });

    test('an invalid rule is rejected', () {
      expect(
        () => ICalSerializer.serialize([
          recurring(
            RecurrenceRule(
              frequency: RecurrenceFrequency.daily,
              count: 2,
              until: DateTime(2027),
            ),
          ),
        ], timestamp: stamp),
        throwsArgumentError,
      );
      expect(
        () => ICalSerializer.serialize([
          recurring(
            RecurrenceRule(
              frequency: RecurrenceFrequency.daily,
              until: DateTime(2026, 11, 1),
            ),
          ),
        ], timestamp: stamp),
        throwsArgumentError,
      );
    });

    test('formatFloatingDateTime has no zone designator', () {
      expect(
        ICalSerializer.formatFloatingDateTime(DateTime(2026, 1, 2, 3, 4, 5)),
        '20260102T030405',
      );
    });
  });
}
