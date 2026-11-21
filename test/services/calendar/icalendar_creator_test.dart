import 'dart:io';

import 'package:event_snap_2/models/event_model.dart';
import 'package:event_snap_2/services/calendar/calendar_creator.dart';
import 'package:event_snap_2/services/calendar/icalendar_creator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Path provider returning a per-test temp directory.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('eventsnap_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  EventModel event({String title = 'Test Meeting'}) {
    final start = DateTime.utc(2025, 5, 28, 14);
    return EventModel(
      id: 'evt-42',
      title: title,
      description: 'A test meeting for unit testing',
      location: 'Test Conference Room',
      startDateTime: start,
      endDateTime: start.add(const Duration(hours: 1)),
    );
  }

  group('ICalendarCreator', () {
    test('implements CalendarCreator', () {
      expect(ICalendarCreator(), isA<CalendarCreator>());
    });

    test('buildIcs is pure and uses the injected clock for DTSTAMP', () {
      final creator = ICalendarCreator(
        clock: () => DateTime.utc(2025, 1, 1, 8),
      );
      final a = creator.buildIcs([event()]);
      final b = creator.buildIcs([event()]);
      expect(a, b);
      expect(a, contains('DTSTAMP:20250101T080000Z\r\n'));
      expect(a, contains('UID:evt-42@eventsnap.app'));
    });

    test('createIcsFile writes the calendar to the directory', () async {
      final creator = ICalendarCreator(directoryProvider: () async => tempDir);
      final path = await creator.createIcsFile([event(), event(title: 'B')]);

      expect(path, startsWith(tempDir.path));
      expect(path, endsWith('.ics'));
      final content = await File(path).readAsString();
      expect(content, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(content, contains('SUMMARY:Test Meeting'));
      expect(content, contains('SUMMARY:B'));
      expect(content, contains('DESCRIPTION:A test meeting for unit testing'));
      expect(content, contains('LOCATION:Test Conference Room'));
    });

    test('createIcsFile uses the temporary directory by default', () async {
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      final path = await ICalendarCreator().createIcsFile([event()]);
      expect(File(path).existsSync(), isTrue);
      expect(path, startsWith(tempDir.path));
    });

    test('createIcsFile writes UTF-8', () async {
      final creator = ICalendarCreator(directoryProvider: () async => tempDir);
      final path = await creator.createIcsFile([event(title: 'Café 🎉')]);
      expect(await File(path).readAsString(), contains('SUMMARY:Café 🎉'));
    });

    test('createIcsFile rejects empty and invalid input', () async {
      final creator = ICalendarCreator(directoryProvider: () async => tempDir);
      expect(() => creator.createIcsFile([]), throwsArgumentError);
      final invalid = event()..endDateTime = DateTime.utc(2025, 5, 28, 13);
      expect(() => creator.createIcsFile([invalid]), throwsArgumentError);
    });

    test('openInCalendarApp delegates to the opener', () async {
      final opened = <String>[];
      final creator = ICalendarCreator(
        directoryProvider: () async => tempDir,
        fileOpener: (path) async {
          opened.add(path);
          return true;
        },
      );
      final path = await creator.createIcsFile([event()]);
      expect(await creator.openInCalendarApp(path), isTrue);
      expect(opened, [path]);
    });

    test('openInCalendarApp returns false when no app handles it', () async {
      final creator = ICalendarCreator(
        directoryProvider: () async => tempDir,
        fileOpener: (_) async => false,
      );
      final path = await creator.createIcsFile([event()]);
      expect(await creator.openInCalendarApp(path), isFalse);
    });

    test('openInCalendarApp returns false for a missing file', () async {
      var called = false;
      final creator = ICalendarCreator(fileOpener: (_) async => called = true);
      expect(
        await creator.openInCalendarApp('${tempDir.path}/missing.ics'),
        isFalse,
      );
      expect(called, isFalse);
    });
  });
}
