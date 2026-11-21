import 'dart:convert';

import 'package:event_snap_2/models/field_evidence.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/services/ai/extraction_response_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ai_test_helpers.dart';

void main() {
  // The offset the prompt would have told the model to use.
  const reference = Duration(hours: 1);
  final parser = ExtractionResponseParser(referenceOffset: reference);

  ParsedExtraction parse(Object json) =>
      parser.parse(json is String ? json : jsonEncode(json));

  Map<String, dynamic> event({
    String? title = 'Party',
    Object? start = '2026-12-03T18:00:00+01:00',
    Object? end = '2026-12-03T20:00:00+01:00',
    Object? allDay = false,
    Map<String, dynamic>? evidence,
    Object? description,
    Object? location,
  }) => {
    'evidence': ?evidence,
    'title': title,
    'description': description,
    'location': location,
    'start': start,
    'end': end,
    'all_day': allDay,
  };

  group('formats', () {
    test('reads the strict schema output with evidence', () {
      final result = parse(
        eventsJson([
          wireEvent(
            start: '2026-11-27T19:00:00+01:00',
            end: '2026-11-27T21:00:00+01:00',
          ),
        ]),
      );
      expect(result.warnings, isEmpty);
      final e = result.events.single;
      expect(e.title, 'Dinner with Anna');
      expect(e.location, "Luigi's");
      expect(e.description, isNull);
      expect(e.isAllDay, isFalse);
      expect(e.startDateTime, DateTime(2026, 11, 27, 19));
      expect(e.endDateTime, DateTime(2026, 11, 27, 21));
      expect(e.startDateTime.isUtc, isFalse);
      expect(e.evidence[EventField.start]?.quote, 'next Friday at 7pm');
      expect(e.evidence[EventField.title]?.confidence, EvidenceConfidence.high);
      expect(e.evidence[EventField.end]?.quote, isNull);
      // description is null → its evidence is dropped.
      expect(e.evidence.containsKey(EventField.description), isFalse);
    });

    test('strips code fences', () {
      final content =
          '```json\n${jsonEncode({
            'events': [event()],
          })}\n```';
      expect(parse(content).events.single.title, 'Party');
    });

    test('finds JSON surrounded by prose', () {
      final content =
          'Sure! Here are the events:\n${jsonEncode({
            'events': [event()],
          })}\nHope this helps.';
      expect(parse(content).events, hasLength(1));
    });

    test('accepts a bare array and a single event object', () {
      expect(parse([event(), event(title: 'Other')]).events, hasLength(2));
      expect(parse(event()).events.single.title, 'Party');
    });

    test('accepts v2 capitalised keys', () {
      final result = parse({
        'events': [
          {
            'Summary': 'Team meeting',
            'Description': 'Weekly sync',
            'Location': 'Room A',
            'Start': '2026-11-22T10:00:00+01:00',
            'End': '2026-11-22T12:00:00+01:00',
          },
        ],
      });
      final e = result.events.single;
      expect(e.title, 'Team meeting');
      expect(e.description, 'Weekly sync');
      expect(e.location, 'Room A');
      expect(e.startDateTime, DateTime(2026, 11, 22, 10));
      expect(e.endDateTime, DateTime(2026, 11, 22, 12));
      expect(e.evidence, isEmpty);
    });

    test('accepts camelCase and synonym keys', () {
      final e = parse({
        'Events': [
          {
            'name': 'Gig',
            'startDateTime': '2026-11-28T21:00:00+01:00',
            'endTime': '2026-11-28T23:00:00+01:00',
            'venue': 'Club',
            'allDay': 'false',
            'Evidence': {
              'Title': {'Quote': 'Gig', 'Reasoning': 'r', 'Confidence': 'HIGH'},
              'Start': 'Read from the poster.',
            },
          },
        ],
      }).events.single;
      expect(e.title, 'Gig');
      expect(e.location, 'Club');
      expect(e.endDateTime, DateTime(2026, 11, 28, 23));
      expect(e.evidence[EventField.title]?.quote, 'Gig');
      expect(e.evidence[EventField.title]?.confidence, EvidenceConfidence.high);
      expect(e.evidence[EventField.start]?.reasoning, 'Read from the poster.');
      expect(e.evidence[EventField.start]?.confidence, EvidenceConfidence.low);
    });

    test('empty results', () {
      expect(parse({'events': []}).events, isEmpty);
      expect(parse(<String, dynamic>{}).events, isEmpty);
      expect(parse([]).events, isEmpty);
    });

    test('content without JSON is invalidResponse', () {
      expect(
        () => parser.parse('I could not find any events, sorry.'),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.invalidResponse,
          ),
        ),
      );
      expect(
        () => parser.parse('"just a string"'),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('all-day events', () {
    test('inclusive one-day end becomes an exclusive midnight', () {
      final e = parse([
        event(start: '2026-12-03', end: '2026-12-03', allDay: true),
      ]).events.single;
      expect(e.isAllDay, isTrue);
      expect(e.startDateTime, DateTime(2026, 12, 3));
      expect(e.endDateTime, DateTime(2026, 12, 4));
      expect(e.lastDay, DateTime(2026, 12, 3));
    });

    test('inclusive multi-day range', () {
      final e = parse([
        event(start: '2026-12-30', end: '2027-01-02', allDay: true),
      ]).events.single;
      expect(e.startDateTime, DateTime(2026, 12, 30));
      expect(e.endDateTime, DateTime(2027, 1, 3));
    });

    test('a midnight end on a later day is read as exclusive', () {
      final e = parse([
        event(
          start: '2026-12-03T00:00:00+01:00',
          end: '2026-12-04T00:00:00+01:00',
          allDay: true,
        ),
      ]).events.single;
      expect(e.startDateTime, DateTime(2026, 12, 3));
      expect(e.endDateTime, DateTime(2026, 12, 4));
    });

    test('a 23:59:59 end keeps its date (seen live)', () {
      final e = parse([
        event(
          start: '2026-12-03T00:00:00+01:00',
          end: '2026-12-03T23:59:59+01:00',
          allDay: true,
        ),
      ]).events.single;
      expect(e.endDateTime, DateTime(2026, 12, 4));
    });

    test('dates use the written day regardless of the offset', () {
      final e = parse([
        event(
          start: '2026-12-03T00:00:00-08:00',
          end: '2026-12-03T00:00:00-08:00',
          allDay: true,
        ),
      ]).events.single;
      expect(e.startDateTime, DateTime(2026, 12, 3));
      expect(e.endDateTime, DateTime(2026, 12, 4));
    });

    test('an end before the start becomes a one-day event', () {
      final e = parse([
        event(start: '2026-12-03', end: '2026-12-01', allDay: true),
      ]).events.single;
      expect(e.endDateTime, DateTime(2026, 12, 4));
      expect(e.evidence[EventField.end]?.confidence, EvidenceConfidence.low);
    });

    test('a missing end becomes a one-day event', () {
      final e = parse([event(start: '2026-12-03', end: null, allDay: true)])
          .events
          .single;
      expect(e.endDateTime, DateTime(2026, 12, 4));
      expect(e.evidence[EventField.end], isNotNull);
    });

    test('date-only values are all-day even if the flag is false', () {
      final e = parse([
        event(start: '2026-12-24', end: '2026-12-26', allDay: false),
      ]).events.single;
      expect(e.isAllDay, isTrue);
      expect(e.endDateTime, DateTime(2026, 12, 27));
    });

    test('the flag as a string is accepted', () {
      final e = parse([
        event(
          start: '2026-12-03T10:00:00+01:00',
          end: '2026-12-03T11:00:00+01:00',
          allDay: 'true',
        ),
      ]).events.single;
      expect(e.isAllDay, isTrue);
      expect(e.startDateTime, DateTime(2026, 12, 3));
      expect(e.endDateTime, DateTime(2026, 12, 4));
    });
  });

  group('timed events', () {
    test('a missing end defaults to one hour with low confidence', () {
      final e = parse([event(end: null)]).events.single;
      expect(e.endDateTime, DateTime(2026, 12, 3, 19));
      final evidence = e.evidence[EventField.end]!;
      expect(evidence.quote, isNull);
      expect(evidence.confidence, EvidenceConfidence.low);
    });

    test('an end earlier on the same day crosses midnight', () {
      final e = parse([
        event(
          start: '2026-12-03T22:00:00+01:00',
          end: '2026-12-03T02:00:00+01:00',
        ),
      ]).events.single;
      expect(e.endDateTime, DateTime(2026, 12, 4, 2));
      expect(e.evidence[EventField.end]?.confidence, EvidenceConfidence.medium);
    });

    test('an end days before the start defaults to one hour', () {
      final e = parse([
        event(
          start: '2026-12-03T10:00:00+01:00',
          end: '2026-11-01T09:00:00+01:00',
        ),
      ]).events.single;
      expect(e.endDateTime, DateTime(2026, 12, 3, 11));
      expect(e.evidence[EventField.end]?.confidence, EvidenceConfidence.low);
    });

    test('an end equal to the start defaults to one hour', () {
      final e = parse([
        event(
          start: '2026-12-03T10:00:00+01:00',
          end: '2026-12-03T10:00:00+01:00',
        ),
      ]).events.single;
      expect(e.endDateTime, DateTime(2026, 12, 3, 11));
      expect(e.evidence[EventField.end]?.confidence, EvidenceConfidence.low);
    });

    test('a date-only start with a timed end assumes 09:00', () {
      final e = parse([
        event(start: '2026-12-03', end: '2026-12-03T12:00:00+01:00'),
      ]).events.single;
      expect(e.isAllDay, isFalse);
      expect(e.startDateTime, DateTime(2026, 12, 3, 9));
      expect(e.endDateTime, DateTime(2026, 12, 3, 12));
      expect(e.evidence[EventField.start]?.confidence, EvidenceConfidence.low);
    });

    test(
      'the reference offset is read as local wall-clock time (DST-safe)',
      () {
        final e = parse([
          event(
            start: '2027-07-10T14:00:00+01:00',
            end: '2027-07-10T15:30:00+01:00',
          ),
        ]).events.single;
        expect(e.startDateTime, DateTime(2027, 7, 10, 14));
        expect(e.endDateTime, DateTime(2027, 7, 10, 15, 30));
      },
    );

    test('other offsets are converted to local time', () {
      final e = parse([
        event(start: '2026-11-27T19:00:00Z', end: '2026-11-27T20:00:00-05:00'),
      ]).events.single;
      expect(e.startDateTime, DateTime.utc(2026, 11, 27, 19).toLocal());
      expect(e.endDateTime, DateTime.utc(2026, 11, 28, 1).toLocal());
    });

    test('timestamps without offset, with a space or fractions', () {
      final e = parse([
        event(start: '2026-11-27 19:00', end: '2026-11-27T20:15:30.123'),
      ]).events.single;
      expect(e.startDateTime, DateTime(2026, 11, 27, 19));
      expect(e.endDateTime, DateTime(2026, 11, 27, 20, 15, 30));
    });
  });

  group('normalisation', () {
    test('a missing title becomes "Untitled event" with a note', () {
      final e = parse([event(title: null)]).events.single;
      expect(e.title, ExtractionResponseParser.untitled);
      expect(e.evidence[EventField.title]?.confidence, EvidenceConfidence.low);
      expect(
        parse([event(title: '   ')]).events.single.title,
        'Untitled event',
      );
    });

    test('null-like strings become null and drop their evidence', () {
      final e = parse([
        event(
          description: 'null',
          location: ' ',
          evidence: {
            'location': wireEvidence(null, confidence: 'low'),
            'description': wireEvidence('x'),
          },
        ),
      ]).events.single;
      expect(e.description, isNull);
      expect(e.location, isNull);
      expect(e.evidence, isEmpty);
    });

    test('a "null" quote string is treated as no quote (seen live)', () {
      final e = parse([
        event(
          evidence: {
            'title': wireEvidence('null'),
            'start': wireEvidence(' N/A '),
          },
        ),
      ]).events.single;
      expect(e.evidence[EventField.title]?.quote, isNull);
      expect(e.evidence[EventField.start]?.quote, isNull);
      expect(e.evidence[EventField.title]?.confidence, EvidenceConfidence.high);
    });

    group('weekday safety net', () {
      test('moves a mis-resolved "next Friday" to the Friday (seen live)', () {
        // Saturday 2026-11-28 returned for "next Friday" asked on Saturday
        // 2026-11-21; the correct day is Friday 2026-11-27.
        final e = parse([
          event(
            start: '2026-11-28T19:00:00+01:00',
            end: '2026-11-28T21:00:00+01:00',
            evidence: {'start': wireEvidence('next Friday at 7pm')},
          ),
        ]).events.single;
        expect(e.startDateTime, DateTime(2026, 11, 27, 19));
        expect(e.endDateTime, DateTime(2026, 11, 27, 21));
        final evidence = e.evidence[EventField.start]!;
        expect(evidence.quote, 'next Friday at 7pm');
        expect(evidence.confidence, EvidenceConfidence.medium);
        expect(evidence.reasoning, contains('Friday'));
      });

      test('moves all-day events by whole days', () {
        final e = parse([
          event(
            start: '2026-11-26',
            end: '2026-11-26',
            allDay: true,
            evidence: {'start': wireEvidence('on Friday')},
          ),
        ]).events.single;
        expect(e.startDateTime, DateTime(2026, 11, 27));
        expect(e.endDateTime, DateTime(2026, 11, 28));
      });

      test('leaves matching, explicit or ambiguous quotes alone', () {
        final friday = DateTime(2026, 11, 27, 19);
        final saturday = DateTime(2026, 11, 28, 19);
        int shift(DateTime d, String? q) =>
            ExtractionResponseParser.weekdayCorrection(d, q);
        expect(shift(friday, 'next Friday at 7pm'), 0);
        expect(shift(saturday, 'Friday, 5 December'), 0);
        expect(shift(saturday, 'Friday 28/11'), 0);
        expect(shift(saturday, 'Friday the 28th'), 0);
        expect(shift(saturday, 'Friday or Saturday'), 0);
        expect(shift(saturday, 'tomorrow at 7'), 0);
        expect(shift(saturday, null), 0);
        expect(shift(saturday, 'Fridays at 7pm'), -1);
        expect(shift(DateTime(2026, 11, 26), 'FRIDAY'), 1);
        // Never more than three days either way.
        expect(shift(DateTime(2026, 11, 23), 'Friday'), -3);
        expect(shift(DateTime(2026, 11, 24), 'Friday'), 3);
      });
    });

    test('a bad event is skipped with a warning; others are kept', () {
      final result = parse({
        'events': [
          event(start: 'next Friday'),
          event(start: '2026-02-30T10:00:00+01:00'),
          event(start: null),
          'not an object',
          event(start: '2026-13-01'),
          event(start: '2026-12-03T25:00:00+01:00'),
          event(title: 'Good'),
        ],
      });
      expect(result.events.single.title, 'Good');
      expect(result.warnings, hasLength(6));
      expect(result.warnings.first, contains('event 1'));
      expect(result.warnings[3], contains('event 4'));
    });

    test('unparseable timestamps return null', () {
      expect(parser.parseTimestamp('tomorrow'), isNull);
      expect(parser.parseTimestamp('2026-02-29'), isNull);
      expect(parser.parseTimestamp('2028-02-29')?.dateOnly, isTrue);
      expect(parser.parseTimestamp('2026-11-27T10:61:00'), isNull);
    });
  });
}
