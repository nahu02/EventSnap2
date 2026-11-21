import 'dart:convert';

import 'package:event_snap_2/models/event_model.dart';
import 'package:event_snap_2/models/field_evidence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EventModel', () {
    final validStartTime = DateTime(2025, 5, 25, 10, 0);
    final validEndTime = DateTime(2025, 5, 25, 11, 0);

    group('Constructor', () {
      test('creates valid event model with required fields', () {
        final event = EventModel(
          title: 'Test Event',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );

        expect(event.title, equals('Test Event'));
        expect(event.startDateTime, equals(validStartTime));
        expect(event.endDateTime, equals(validEndTime));
        expect(event.description, isNull);
        expect(event.location, isNull);
      });

      test('creates valid event model with all fields', () {
        final event = EventModel(
          title: 'Test Event',
          description: 'Test Description',
          location: 'Test Location',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );

        expect(event.title, equals('Test Event'));
        expect(event.description, equals('Test Description'));
        expect(event.location, equals('Test Location'));
        expect(event.startDateTime, equals(validStartTime));
        expect(event.endDateTime, equals(validEndTime));
      });

      test('throws error when end time is before start time', () {
        expect(
          () => EventModel(
            title: 'Test Event',
            startDateTime: validEndTime,
            endDateTime: validStartTime,
          ),
          throwsArgumentError,
        );
      });

      test('throws error when title is empty', () {
        expect(
          () => EventModel(
            title: '',
            startDateTime: validStartTime,
            endDateTime: validEndTime,
          ),
          throwsArgumentError,
        );
      });

      test('throws error when title is only whitespace', () {
        expect(
          () => EventModel(
            title: '   ',
            startDateTime: validStartTime,
            endDateTime: validEndTime,
          ),
          throwsArgumentError,
        );
      });
    });

    group('JSON Serialization', () {
      test('converts to JSON correctly', () {
        final event = EventModel(
          title: 'Test Event',
          description: 'Test Description',
          location: 'Test Location',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );

        final json = event.toJson();

        expect(json['title'], equals('Test Event'));
        expect(json['description'], equals('Test Description'));
        expect(json['location'], equals('Test Location'));
        expect(json['startDateTime'], equals(validStartTime.toIso8601String()));
        expect(json['endDateTime'], equals(validEndTime.toIso8601String()));
      });

      test('converts from JSON correctly', () {
        final json = {
          'title': 'Test Event',
          'description': 'Test Description',
          'location': 'Test Location',
          'startDateTime': validStartTime.toIso8601String(),
          'endDateTime': validEndTime.toIso8601String(),
        };

        final event = EventModel.fromJson(json);

        expect(event.title, equals('Test Event'));
        expect(event.description, equals('Test Description'));
        expect(event.location, equals('Test Location'));
        expect(event.startDateTime, equals(validStartTime));
        expect(event.endDateTime, equals(validEndTime));
      });

      test('handles null optional fields in JSON', () {
        final json = {
          'title': 'Test Event',
          'description': null,
          'location': null,
          'startDateTime': validStartTime.toIso8601String(),
          'endDateTime': validEndTime.toIso8601String(),
        };

        final event = EventModel.fromJson(json);

        expect(event.title, equals('Test Event'));
        expect(event.description, isNull);
        expect(event.location, isNull);
        expect(event.startDateTime, equals(validStartTime));
        expect(event.endDateTime, equals(validEndTime));
      });
    });

    group('Validation', () {
      test('validates correctly for valid event', () {
        final event = EventModel(
          title: 'Test Event',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );

        expect(event.validate(), isEmpty);
        expect(event.isValid, isTrue);
      });

      test('validates empty title', () {
        final event = EventModel(
          title: 'Valid Title',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        // Manually set invalid title to test validation method
        event.title = '';

        final errors = event.validate();
        expect(errors, contains('Title is required'));
        expect(event.isValid, isFalse);
      });

      test('validates end time before start time', () {
        final event = EventModel(
          title: 'Test Event',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        // Manually set invalid times to test validation method
        event.endDateTime = validStartTime.subtract(const Duration(hours: 1));

        final errors = event.validate();
        expect(errors, contains('End time must be after start time'));
        expect(event.isValid, isFalse);
      });

      test('validates same start and end time', () {
        final event = EventModel(
          title: 'Test Event',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        // Manually set same times to test validation method
        event.endDateTime = validStartTime;

        final errors = event.validate();
        expect(errors, contains('End time must be different from start time'));
        expect(event.isValid, isFalse);
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final original = EventModel(
          title: 'Original Title',
          description: 'Original Description',
          location: 'Original Location',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );

        final copy = original.copyWith(
          title: 'Updated Title',
          description: 'Updated Description',
        );

        expect(copy.title, equals('Updated Title'));
        expect(copy.description, equals('Updated Description'));
        expect(copy.location, equals('Original Location'));
        expect(copy.startDateTime, equals(validStartTime));
        expect(copy.endDateTime, equals(validEndTime));
      });
    });

    group('Helper Methods', () {
      test('calculates duration correctly', () {
        final event = EventModel(
          title: 'Test Event',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );

        expect(event.duration, equals(const Duration(hours: 1)));
      });

      test('formats times correctly', () {
        final event = EventModel(
          title: 'Test Event',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );

        expect(event.formattedStartTime, contains('May 25, 2025'));
        expect(event.formattedEndTime, contains('May 25, 2025'));
      });

      test('formats duration correctly', () {
        final event1 = EventModel(
          title: 'Test Event',
          startDateTime: validStartTime,
          endDateTime: validStartTime.add(const Duration(hours: 2)),
        );

        final event2 = EventModel(
          title: 'Test Event',
          startDateTime: validStartTime,
          endDateTime: validStartTime.add(const Duration(minutes: 30)),
        );

        final event3 = EventModel(
          title: 'Test Event',
          startDateTime: validStartTime,
          endDateTime: validStartTime.add(const Duration(days: 1)),
        );

        expect(event1.formattedDuration, equals('2 hours'));
        expect(event2.formattedDuration, equals('30 minutes'));
        expect(event3.formattedDuration, equals('1 day'));
      });
    });

    group('Equality and HashCode', () {
      test('events with same properties are equal', () {
        final event1 = EventModel(
          title: 'Test Event',
          description: 'Test Description',
          location: 'Test Location',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );

        final event2 = EventModel(
          title: 'Test Event',
          description: 'Test Description',
          location: 'Test Location',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );

        expect(event1, equals(event2));
        expect(event1.hashCode, equals(event2.hashCode));
      });

      test('events with different properties are not equal', () {
        final event1 = EventModel(
          title: 'Test Event 1',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );

        final event2 = EventModel(
          title: 'Test Event 2',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );

        expect(event1, isNot(equals(event2)));
      });
    });
    group('Contract v3 additions', () {
      test('generates a unique id when absent and keeps a given id', () {
        final a = EventModel(
          title: 'A',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        final b = EventModel(
          title: 'A',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        expect(a.id, isNotEmpty);
        expect(a.id, isNot(b.id));
        final c = EventModel(
          id: 'fixed-id',
          title: 'A',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        expect(c.id, 'fixed-id');
      });

      test('id is not part of equality', () {
        final a = EventModel(
          id: 'one',
          title: 'A',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        final b = EventModel(
          id: 'two',
          title: 'A',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
      });

      test('copyWith preserves id', () {
        final a = EventModel(
          title: 'A',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        expect(a.copyWith(title: 'B').id, a.id);
      });

      test('defaults: not all-day, no evidence', () {
        final e = EventModel(
          title: 'A',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        expect(e.isAllDay, isFalse);
        expect(e.evidence, isEmpty);
      });

      test('throws when end equals start', () {
        expect(
          () => EventModel(
            title: 'A',
            startDateTime: validStartTime,
            endDateTime: validStartTime,
          ),
          throwsArgumentError,
        );
      });

      test('stores UTC inputs as local time', () {
        final utcStart = DateTime.utc(2025, 5, 25, 8);
        final e = EventModel(
          title: 'A',
          startDateTime: utcStart,
          endDateTime: utcStart.add(const Duration(hours: 1)),
        );
        expect(e.startDateTime.isUtc, isFalse);
        expect(e.endDateTime.isUtc, isFalse);
        expect(e.startDateTime.isAtSameMomentAs(utcStart), isTrue);
      });

      test('all-day events are normalised to midnights (exclusive end)', () {
        final e = EventModel(
          title: 'Festival',
          startDateTime: DateTime(2025, 6, 1, 10),
          endDateTime: DateTime(2025, 6, 3, 18),
          isAllDay: true,
        );
        expect(e.startDateTime, DateTime(2025, 6, 1));
        expect(e.endDateTime, DateTime(2025, 6, 4));
        expect(e.lastDay, DateTime(2025, 6, 3));
        expect(e.isValid, isTrue);
        expect(e.formattedDuration, '3 days');
      });

      test('all-day end already at midnight is kept', () {
        final e = EventModel(
          title: 'Holiday',
          startDateTime: DateTime(2025, 6, 1),
          endDateTime: DateTime(2025, 6, 2),
          isAllDay: true,
        );
        expect(e.endDateTime, DateTime(2025, 6, 2));
        expect(e.formattedDuration, '1 day');
        expect(e.formattedStartTime, contains('Jun 01, 2025'));
        expect(e.formattedEndTime, contains('Jun 01, 2025'));
        expect(e.formattedTimeRange, contains('all day'));
      });

      test('single-day all-day event from a timed range covers that day', () {
        final e = EventModel(
          title: 'Dentist',
          startDateTime: DateTime(2025, 6, 1, 10),
          endDateTime: DateTime(2025, 6, 1, 11),
          isAllDay: true,
        );
        expect(e.startDateTime, DateTime(2025, 6, 1));
        expect(e.endDateTime, DateTime(2025, 6, 2));
      });

      test('validate flags all-day events that are not at midnight', () {
        final e = EventModel(
          title: 'Holiday',
          startDateTime: DateTime(2025, 6, 1),
          endDateTime: DateTime(2025, 6, 2),
          isAllDay: true,
        );
        e.startDateTime = DateTime(2025, 6, 1, 9);
        expect(
          e.validate(),
          contains('All-day events must start and end at midnight'),
        );
      });

      test('copyWith can toggle all-day and replace evidence', () {
        final e = EventModel(
          title: 'A',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        const ev = FieldEvidence(
          quote: 'May 25',
          reasoning: 'Date stated explicitly.',
          confidence: EvidenceConfidence.high,
        );
        final allDay = e.copyWith(
          isAllDay: true,
          evidence: {EventField.start: ev},
        );
        expect(allDay.isAllDay, isTrue);
        expect(allDay.startDateTime, DateTime(2025, 5, 25));
        expect(allDay.endDateTime, DateTime(2025, 5, 26));
        expect(allDay.evidence[EventField.start], ev);
        expect(allDay.id, e.id);
      });

      test('evidence participates in equality', () {
        const ev = FieldEvidence(
          reasoning: 'Inferred.',
          confidence: EvidenceConfidence.low,
        );
        final a = EventModel(
          title: 'A',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
          evidence: {EventField.title: ev},
        );
        final b = EventModel(
          title: 'A',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
          evidence: {EventField.title: ev},
        );
        final c = EventModel(
          title: 'A',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        expect(a, equals(b));
        expect(a.hashCode, b.hashCode);
        expect(a, isNot(equals(c)));
      });

      test('evidence map is unmodifiable', () {
        final e = EventModel(
          title: 'A',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );
        expect(
          () => e.evidence[EventField.title] = const FieldEvidence(
            reasoning: 'x',
            confidence: EvidenceConfidence.low,
          ),
          throwsUnsupportedError,
        );
      });

      test('full JSON round-trip including id, all-day and evidence', () {
        final e = EventModel(
          id: 'evt-1',
          title: 'Conference',
          description: 'Day 1; talks, workshops',
          location: 'Hall A',
          startDateTime: DateTime(2025, 9, 1),
          endDateTime: DateTime(2025, 9, 3),
          isAllDay: true,
          evidence: const {
            EventField.title: FieldEvidence(
              quote: 'Conference',
              reasoning: 'Named in the first line.',
              confidence: EvidenceConfidence.high,
            ),
            EventField.end: FieldEvidence(
              reasoning: 'Two-day event per the agenda.',
              confidence: EvidenceConfidence.medium,
            ),
          },
        );
        final json = jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>;
        expect(json['isAllDay'], isTrue);
        expect((json['evidence'] as Map).keys, containsAll(['title', 'end']));
        final restored = EventModel.fromJson(json);
        expect(restored, equals(e));
        expect(restored.id, 'evt-1');
      });

      test('fromJson accepts the v2 format (no id/isAllDay/evidence)', () {
        final restored = EventModel.fromJson({
          'title': 'Old',
          'startDateTime': validStartTime.toIso8601String(),
          'endDateTime': validEndTime.toIso8601String(),
        });
        expect(restored.id, isNotEmpty);
        expect(restored.isAllDay, isFalse);
        expect(restored.evidence, isEmpty);
      });

      test('fromJson ignores unknown evidence fields', () {
        final restored = EventModel.fromJson({
          'title': 'Old',
          'startDateTime': validStartTime.toIso8601String(),
          'endDateTime': validEndTime.toIso8601String(),
          'evidence': {
            'organizer': {'reasoning': 'x', 'confidence': 'high'},
            'location': {'reasoning': 'y', 'confidence': 'low'},
          },
        });
        expect(restored.evidence.keys, [EventField.location]);
      });

      test('fromJson throws FormatException for invalid dates', () {
        expect(
          () => EventModel.fromJson({
            'title': 'Bad',
            'startDateTime': 'invalid-date',
            'endDateTime': validEndTime.toIso8601String(),
          }),
          throwsFormatException,
        );
      });

      test(
        'formattedTimeRange shows only the end time for same-day events',
        () {
          final e = EventModel(
            title: 'A',
            startDateTime: DateTime(2020, 5, 25, 10),
            endDateTime: DateTime(2020, 5, 25, 11, 30),
          );
          expect(e.formattedTimeRange, 'May 25, 2020; 10:00 - 11:30');
        },
      );
    });
  });
}
