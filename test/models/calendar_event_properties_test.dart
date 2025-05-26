import 'package:flutter_test/flutter_test.dart';
import 'package:event_snap_2/models/calendar_event_properties.dart';
import 'package:event_snap_2/models/event_model.dart';

void main() {
  group('CalendarEventProperties', () {
    final validStartTime = DateTime(2025, 5, 25, 10, 0);
    final validEndTime = DateTime(2025, 5, 25, 11, 0);
    final validStartString = validStartTime.toIso8601String();
    final validEndString = validEndTime.toIso8601String();

    group('Constructor', () {
      test('creates instance with all optional fields', () {
        final properties = CalendarEventProperties(
          summary: 'Test Event',
          description: 'Test Description',
          location: 'Test Location',
          start: validStartString,
          end: validEndString,
        );

        expect(properties.summary, equals('Test Event'));
        expect(properties.description, equals('Test Description'));
        expect(properties.location, equals('Test Location'));
        expect(properties.start, equals(validStartString));
        expect(properties.end, equals(validEndString));
      });

      test('creates instance with no fields', () {
        final properties = CalendarEventProperties();

        expect(properties.summary, isNull);
        expect(properties.description, isNull);
        expect(properties.location, isNull);
        expect(properties.start, isNull);
        expect(properties.end, isNull);
      });
    });

    group('JSON Serialization', () {
      test('converts from JSON with capitalized keys (OpenAI format)', () {
        final json = {
          'Summary': 'Test Event',
          'Description': 'Test Description',
          'Location': 'Test Location',
          'Start': validStartString,
          'End': validEndString,
        };

        final properties = CalendarEventProperties.fromJson(json);

        expect(properties.summary, equals('Test Event'));
        expect(properties.description, equals('Test Description'));
        expect(properties.location, equals('Test Location'));
        expect(properties.start, equals(validStartString));
        expect(properties.end, equals(validEndString));
      });

      test('converts from JSON with lowercase keys', () {
        final json = {
          'summary': 'Test Event',
          'description': 'Test Description',
          'location': 'Test Location',
          'start': validStartString,
          'end': validEndString,
        };

        final properties = CalendarEventProperties.fromJson(json);

        expect(properties.summary, equals('Test Event'));
        expect(properties.description, equals('Test Description'));
        expect(properties.location, equals('Test Location'));
        expect(properties.start, equals(validStartString));
        expect(properties.end, equals(validEndString));
      });

      test('prioritizes capitalized keys over lowercase keys', () {
        final json = {
          'Summary': 'Capitalized Summary',
          'summary': 'lowercase summary',
          'Description': 'Capitalized Description',
          'description': 'lowercase description',
          'Start': validStartString,
          'End': validEndString,
        };

        final properties = CalendarEventProperties.fromJson(json);

        expect(properties.summary, equals('Capitalized Summary'));
        expect(properties.description, equals('Capitalized Description'));
      });

      test('converts to JSON with capitalized keys', () {
        final properties = CalendarEventProperties(
          summary: 'Test Event',
          description: 'Test Description',
          location: 'Test Location',
          start: validStartString,
          end: validEndString,
        );

        final json = properties.toJson();

        expect(json['Summary'], equals('Test Event'));
        expect(json['Description'], equals('Test Description'));
        expect(json['Location'], equals('Test Location'));
        expect(json['Start'], equals(validStartString));
        expect(json['End'], equals(validEndString));
      });

      test('excludes null fields from JSON', () {
        final properties = CalendarEventProperties(
          summary: 'Test Event',
          start: validStartString,
          end: validEndString,
        );

        final json = properties.toJson();

        expect(json['Summary'], equals('Test Event'));
        expect(json['Start'], equals(validStartString));
        expect(json['End'], equals(validEndString));
        expect(json.containsKey('Description'), isFalse);
        expect(json.containsKey('Location'), isFalse);
      });
    });

    group('EventModel Conversion', () {
      test('converts to EventModel successfully', () {
        final properties = CalendarEventProperties(
          summary: 'Test Event',
          description: 'Test Description',
          location: 'Test Location',
          start: validStartString,
          end: validEndString,
        );

        final event = properties.toEventModel();

        expect(event.title, equals('Test Event'));
        expect(event.description, equals('Test Description'));
        expect(event.location, equals('Test Location'));
        expect(event.startDateTime, equals(validStartTime));
        expect(event.endDateTime, equals(validEndTime));
      });

      test('throws error when summary is missing', () {
        final properties = CalendarEventProperties(
          start: validStartString,
          end: validEndString,
        );

        expect(() => properties.toEventModel(), throwsArgumentError);
      });

      test('throws error when summary is empty', () {
        final properties = CalendarEventProperties(
          summary: '',
          start: validStartString,
          end: validEndString,
        );

        expect(() => properties.toEventModel(), throwsArgumentError);
      });

      test('throws error when start is missing', () {
        final properties = CalendarEventProperties(
          summary: 'Test Event',
          end: validEndString,
        );

        expect(() => properties.toEventModel(), throwsArgumentError);
      });

      test('throws error when end is missing', () {
        final properties = CalendarEventProperties(
          summary: 'Test Event',
          start: validStartString,
        );

        expect(() => properties.toEventModel(), throwsArgumentError);
      });

      test('throws error when date format is invalid', () {
        final properties = CalendarEventProperties(
          summary: 'Test Event',
          start: 'invalid-date',
          end: validEndString,
        );

        expect(() => properties.toEventModel(), throwsArgumentError);
      });

      test('creates from EventModel successfully', () {
        final event = EventModel(
          title: 'Test Event',
          description: 'Test Description',
          location: 'Test Location',
          startDateTime: validStartTime,
          endDateTime: validEndTime,
        );

        final properties = CalendarEventProperties.fromEventModel(event);

        expect(properties.summary, equals('Test Event'));
        expect(properties.description, equals('Test Description'));
        expect(properties.location, equals('Test Location'));
        expect(properties.start, equals(validStartString));
        expect(properties.end, equals(validEndString));
      });
    });

    group('Validation', () {
      test('validates successfully with complete data', () {
        final properties = CalendarEventProperties(
          summary: 'Test Event',
          start: validStartString,
          end: validEndString,
        );

        expect(properties.validate(), isEmpty);
        expect(properties.isValid, isTrue);
        expect(properties.isComplete, isTrue);
      });

      test('validates missing summary', () {
        final properties = CalendarEventProperties(
          start: validStartString,
          end: validEndString,
        );

        final errors = properties.validate();
        expect(errors, contains('Summary/title is required'));
        expect(properties.isValid, isFalse);
        expect(properties.isComplete, isFalse);
      });

      test('validates end time before start time', () {
        final properties = CalendarEventProperties(
          summary: 'Test Event',
          start: validEndString,
          end: validStartString,
        );

        final errors = properties.validate();
        expect(errors, contains('End time must be after start time'));
        expect(properties.isValid, isFalse);
      });

      test('validates same start and end time', () {
        final properties = CalendarEventProperties(
          summary: 'Test Event',
          start: validStartString,
          end: validStartString,
        );

        final errors = properties.validate();
        expect(errors, contains('End time must be different from start time'));
        expect(properties.isValid, isFalse);
      });

      test('validates invalid date format', () {
        final properties = CalendarEventProperties(
          summary: 'Test Event',
          start: 'invalid-date',
          end: validEndString,
        );

        final errors = properties.validate();
        expect(
          errors.any((error) => error.contains('Invalid date format')),
          isTrue,
        );
        expect(properties.isValid, isFalse);
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final original = CalendarEventProperties(
          summary: 'Original Summary',
          description: 'Original Description',
          location: 'Original Location',
          start: validStartString,
          end: validEndString,
        );

        final copy = original.copyWith(
          summary: 'Updated Summary',
          description: 'Updated Description',
        );

        expect(copy.summary, equals('Updated Summary'));
        expect(copy.description, equals('Updated Description'));
        expect(copy.location, equals('Original Location'));
        expect(copy.start, equals(validStartString));
        expect(copy.end, equals(validEndString));
      });
    });

    group('Equality and HashCode', () {
      test('properties with same values are equal', () {
        final properties1 = CalendarEventProperties(
          summary: 'Test Event',
          description: 'Test Description',
          location: 'Test Location',
          start: validStartString,
          end: validEndString,
        );

        final properties2 = CalendarEventProperties(
          summary: 'Test Event',
          description: 'Test Description',
          location: 'Test Location',
          start: validStartString,
          end: validEndString,
        );

        expect(properties1, equals(properties2));
        expect(properties1.hashCode, equals(properties2.hashCode));
      });

      test('properties with different values are not equal', () {
        final properties1 = CalendarEventProperties(
          summary: 'Test Event 1',
          start: validStartString,
          end: validEndString,
        );

        final properties2 = CalendarEventProperties(
          summary: 'Test Event 2',
          start: validStartString,
          end: validEndString,
        );

        expect(properties1, isNot(equals(properties2)));
      });
    });
  });
}
