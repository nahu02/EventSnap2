import 'dart:convert';

import 'package:event_snap_2/models/extraction.dart';
import 'package:event_snap_2/services/ai/extraction_prompt.dart';
import 'package:event_snap_2/services/ai/extraction_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Saturday, as in the live findings ("next Friday" must be 2026-11-27).
  final saturday = DateTime(2026, 11, 21, 14, 5);

  group('ExtractionPrompt.dateTable', () {
    test('lists today, tomorrow and three weeks of weekdays', () {
      final table = ExtractionPrompt.dateTable(saturday);
      expect(table, hasLength(ExtractionPrompt.lookupDays));
      expect(table[0], 'Saturday 2026-11-21 = today');
      expect(table[1], 'Sunday 2026-11-22 = tomorrow');
      expect(table, contains('Friday 2026-11-27'));
      expect(table, contains('Tuesday 2026-12-01'));
      expect(table.last, 'Friday 2026-12-11');
    });

    test('every entry has the right weekday', () {
      for (final line in ExtractionPrompt.dateTable(DateTime(2027, 3, 25))) {
        final parts = line.split(' ');
        final date = DateTime.parse(parts[1]);
        expect(parts[0], ExtractionPrompt.weekdayName(date), reason: line);
      }
    });
  });

  group('ExtractionPrompt.system', () {
    test('contains the context, the date table and the rules', () {
      final prompt = ExtractionPrompt.system(
        now: saturday,
        includeSchema: false,
      );
      final offset = ExtractionPrompt.formatOffset(saturday.timeZoneOffset);
      expect(prompt, contains('Now: Saturday 2026-11-21 14:05'));
      expect(prompt, contains('UTC offset $offset'));
      expect(prompt, contains('Friday 2026-11-27'));
      expect(prompt, contains('2026-11-21T19:00:00$offset'));
      expect(prompt, contains('all_day'));
      expect(prompt, contains('inclusive'));
      expect(prompt, contains('max ~8 words'));
      expect(prompt, contains('{"events": []}'));
      // Required by OpenAI's JSON mode.
      expect(prompt, contains('JSON'));
      expect(prompt, isNot(contains('"additionalProperties"')));
    });

    test('appends the schema when the API does not enforce it', () {
      final prompt = ExtractionPrompt.system(
        now: saturday,
        includeSchema: true,
      );
      expect(prompt, contains(ExtractionSchema.schemaText));
      final schemaStart = prompt.indexOf('{"type":"object"');
      expect(
        jsonDecode(prompt.substring(schemaStart)),
        ExtractionSchema.schema,
      );
    });
  });

  group('ExtractionPrompt.user', () {
    test('wraps the text', () {
      final text = ExtractionPrompt.user(
        const ExtractionInput(text: '  Lunch tomorrow  '),
      );
      expect(text, contains('"""\nLunch tomorrow\n"""'));
      expect(text, isNot(contains('image')));
    });

    test('mentions images', () {
      expect(
        ExtractionPrompt.user(
          const ExtractionInput(images: [InputImage(path: '/a.jpg')]),
        ),
        'Extract the calendar events from the attached image.',
      );
      final both = ExtractionPrompt.user(
        const ExtractionInput(
          text: 'See flyer',
          images: [
            InputImage(path: '/a.jpg'),
            InputImage(path: '/b.jpg'),
          ],
        ),
      );
      expect(both, contains('See flyer'));
      expect(both, contains('the 2 attached images'));
    });
  });

  test('formatOffset', () {
    expect(ExtractionPrompt.formatOffset(const Duration(hours: 1)), '+01:00');
    expect(ExtractionPrompt.formatOffset(Duration.zero), '+00:00');
    expect(
      ExtractionPrompt.formatOffset(const Duration(hours: -5, minutes: -30)),
      '-05:30',
    );
    expect(
      ExtractionPrompt.formatOffset(const Duration(hours: 5, minutes: 45)),
      '+05:45',
    );
  });
}
