import 'package:flutter_test/flutter_test.dart';
import 'package:event_snap_2/models/event_model.dart';

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
        event.endDateTime = validStartTime.subtract(Duration(hours: 1));

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

        expect(event.duration, equals(Duration(hours: 1)));
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
          endDateTime: validStartTime.add(Duration(hours: 2)),
        );

        final event2 = EventModel(
          title: 'Test Event',
          startDateTime: validStartTime,
          endDateTime: validStartTime.add(Duration(minutes: 30)),
        );

        final event3 = EventModel(
          title: 'Test Event',
          startDateTime: validStartTime,
          endDateTime: validStartTime.add(Duration(days: 1)),
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
  });
}
