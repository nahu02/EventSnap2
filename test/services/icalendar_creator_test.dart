import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:event_snap_2/models/calendar_event_properties.dart';
import 'package:event_snap_2/services/icalendar_creator.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Mock implementation of PathProviderPlatform for testing
class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    // Return a test directory path
    final testDir = Directory.systemTemp.createTempSync('eventsnap_test');
    return testDir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async => null;

  @override
  Future<String?> getLibraryPath() async => null;

  @override
  Future<String?> getApplicationDocumentsPath() async => null;

  @override
  Future<String?> getExternalStoragePath() async => null;

  @override
  Future<List<String>?> getExternalCachePaths() async => null;

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async => null;

  @override
  Future<String?> getDownloadsPath() async => null;
}

void main() {
  group('ICalendarCreator Tests', () {
    late ICalendarCreator creator;

    setUpAll(() {
      // Set up mock path provider for testing
      PathProviderPlatform.instance = MockPathProviderPlatform();
    });

    setUp(() {
      creator = ICalendarCreator();
    });

    tearDown(() async {
      // Clean up any test files created
      try {
        final tempDir = Directory.systemTemp
            .listSync()
            .where((entity) => entity.path.contains('eventsnap_test'))
            .cast<Directory>();

        for (final dir in tempDir) {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      } catch (e) {
        // Ignore cleanup errors in tests
      }
    });

    test(
      'should create valid iCalendar file with complete event data',
      () async {
        // Arrange
        final properties = CalendarEventProperties(
          summary: 'Test Meeting',
          description: 'A test meeting for unit testing',
          location: 'Test Conference Room',
          start: '2025-05-28T14:00:00.000Z',
          end: '2025-05-28T15:00:00.000Z',
        );

        // Act
        final filePath = await creator.createIcalFile(properties);

        // Assert
        expect(filePath, isNotEmpty);
        expect(filePath.endsWith('.ics'), isTrue);

        final file = File(filePath);
        expect(await file.exists(), isTrue);

        final content = await file.readAsString();
        expect(content, contains('BEGIN:VCALENDAR'));
        expect(content, contains('END:VCALENDAR'));
        expect(content, contains('BEGIN:VEVENT'));
        expect(content, contains('END:VEVENT'));
        expect(content, contains('SUMMARY:Test Meeting'));
        expect(
          content,
          contains('DESCRIPTION:A test meeting for unit testing'),
        );
        expect(content, contains('LOCATION:Test Conference Room'));
        expect(content, contains('UID:'));
        expect(content, contains('@eventsnap.app'));
      },
    );

    test('should create iCalendar file with minimal event data', () async {
      // Arrange
      final properties = CalendarEventProperties(
        summary: 'Minimal Event',
        start: '2025-05-28T10:00:00.000Z',
        end: '2025-05-28T11:00:00.000Z',
      );

      // Act
      final filePath = await creator.createIcalFile(properties);

      // Assert
      expect(filePath, isNotEmpty);

      final file = File(filePath);
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      expect(content, contains('SUMMARY:Minimal Event'));
      expect(content, contains('UID:'));
      expect(content, contains('@eventsnap.app'));
    });

    test('should generate default end time when not provided', () async {
      // Arrange
      final properties = CalendarEventProperties(
        summary: 'Event without end time',
        start: '2025-05-28T10:00:00.000Z',
        // No end time provided
      );

      // Act
      final filePath = await creator.createIcalFile(properties);

      // Assert
      expect(filePath, isNotEmpty);

      final file = File(filePath);
      final content = await file.readAsString();

      // Should contain both start and end times
      expect(content, contains('DTSTART:'));
      expect(content, contains('DTEND:'));
    });

    test('should throw ArgumentError for invalid event properties', () async {
      // Arrange
      final properties = CalendarEventProperties(
        // No summary provided
        start: '2025-05-28T10:00:00.000Z',
        end: '2025-05-28T09:00:00.000Z', // End before start
      );

      // Act & Assert
      expect(
        () => creator.createIcalFile(properties),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw ArgumentError when start time is missing', () async {
      // Arrange
      final properties = CalendarEventProperties(
        summary: 'Event without start time',
        // No start time provided
        end: '2025-05-28T15:00:00.000Z',
      );

      // Act & Assert
      expect(
        () => creator.createIcalFile(properties),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should generate unique UIDs for different events', () async {
      // Arrange
      final properties1 = CalendarEventProperties(
        summary: 'Event 1',
        start: '2025-05-28T10:00:00.000Z',
        end: '2025-05-28T11:00:00.000Z',
      );

      final properties2 = CalendarEventProperties(
        summary: 'Event 2',
        start: '2025-05-28T14:00:00.000Z',
        end: '2025-05-28T15:00:00.000Z',
      );

      // Act
      final filePath1 = await creator.createIcalFile(properties1);
      await Future.delayed(
        const Duration(milliseconds: 10),
      ); // Ensure different timestamps
      final filePath2 = await creator.createIcalFile(properties2);

      // Assert
      final content1 = await File(filePath1).readAsString();
      final content2 = await File(filePath2).readAsString();

      // Extract UIDs from both files
      final uid1Match = RegExp(r'UID:([^\r\n]+)').firstMatch(content1);
      final uid2Match = RegExp(r'UID:([^\r\n]+)').firstMatch(content2);

      expect(uid1Match, isNotNull);
      expect(uid2Match, isNotNull);
      expect(uid1Match!.group(1), isNot(equals(uid2Match!.group(1))));
    });

    test('should handle special characters in event fields', () async {
      // Arrange
      final properties = CalendarEventProperties(
        summary: 'Meeting with "Special" Characters & Symbols',
        description: 'Description with\nnew lines\nand symbols: @#\$%',
        location: 'Room #123 & Conference Hall',
        start: '2025-05-28T10:00:00.000Z',
        end: '2025-05-28T11:00:00.000Z',
      );

      // Act
      final filePath = await creator.createIcalFile(properties);

      // Assert
      expect(filePath, isNotEmpty);

      final file = File(filePath);
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      expect(content, contains('BEGIN:VCALENDAR'));
      expect(content, contains('END:VCALENDAR'));
    });

    test('should validate temporary directory access', () async {
      // Act & Assert
      expect(() => creator.validateTemporaryDirectory(), returnsNormally);
    });
  });
}
