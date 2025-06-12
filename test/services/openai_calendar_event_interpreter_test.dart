import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:event_snap_2/models/settings.dart';
import 'package:event_snap_2/services/openai_calendar_event_interpreter.dart';

// Mock class for testing
class MockSettings extends Mock implements Settings {}

void main() {
  setUpAll(() async {
    // Load environment variables for testing
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      // .env file might not exist in CI/CD, that's ok
      // Silently handle missing .env file in test environment
    }
  });

  group('OpenAiCalendarEventInterpreter', () {
    late Settings validSettings;
    late Settings invalidSettings;

    setUp(() {
      validSettings = Settings(
        openAiApiKey: 'sk-test123456789abcdef',
        openAiModel: 'gpt-4.1-nano',
        maxRetries: 3,
        timeoutSeconds: 30,
      );

      invalidSettings = Settings.defaults();
    });

    group('Constructor', () {
      test('creates instance with valid settings', () {
        expect(
          () => OpenAiCalendarEventInterpreter(validSettings),
          returnsNormally,
        );
      });

      test('throws error with invalid settings (no API key)', () {
        expect(
          () => OpenAiCalendarEventInterpreter(invalidSettings),
          throwsArgumentError,
        );
      });
    });

    group('Input Validation', () {
      test('throws error for empty event text', () async {
        final interpreter = OpenAiCalendarEventInterpreter(validSettings);

        expect(
          () => interpreter.eventToCalendarPropertiesAsync(''),
          throwsArgumentError,
        );

        expect(
          () => interpreter.eventToCalendarPropertiesAsync('   '),
          throwsArgumentError,
        );
      });
    });

    group('Message Creation', () {
      test('creates proper message structure', () {
        final interpreter = OpenAiCalendarEventInterpreter(validSettings);

        // Use reflection or expose method for testing
        // For now, we'll test through integration
        expect(interpreter, isNotNull);
      });
    });

    group('Integration Tests', () {
      // Note: These tests would require actual API keys and should be run separately
      // or with environment variables for CI/CD    group('Real API Tests', () {
      test('processes simple event text', () async {
        // Try to get API key from .env file first, then from environment
        final apiKey =
            dotenv.env['OPENAI_API_KEY'] ??
            const String.fromEnvironment('OPENAI_API_KEY');

        if (apiKey.isEmpty) {
          markTestSkipped('No OpenAI API key provided');
          return;
        }

        final settings = Settings(
          openAiApiKey: apiKey,
          openAiModel: 'gpt-4.1-nano',
          maxRetries: 1,
          timeoutSeconds: 30,
        );

        final interpreter = OpenAiCalendarEventInterpreter(settings);

        final result = await interpreter.eventToCalendarPropertiesAsync(
          'Meeting with team tomorrow at 2pm for 1 hour',
        );

        expect(result.summary, isNotNull);
        expect(result.start, isNotNull);
        expect(result.end, isNotNull);
      }, skip: 'Requires real API key');

      test('handles complex event descriptions', () async {
        final apiKey =
            dotenv.env['OPENAI_API_KEY'] ??
            const String.fromEnvironment('OPENAI_API_KEY');

        if (apiKey.isEmpty || apiKey == 'your_openai_api_key_here') {
          markTestSkipped('No OpenAI API key provided');
          return;
        }

        final settings = Settings(
          openAiApiKey: apiKey,
          openAiModel: 'gpt-4.1-nano',
          maxRetries: 1,
          timeoutSeconds: 30,
        );

        final interpreter = OpenAiCalendarEventInterpreter(settings);

        final result = await interpreter.eventToCalendarPropertiesAsync(
          'Come to our annual company retreat next Friday at the Mountain View Resort, from 9am to 5pm! Team building activities and lunch are included in the price.',
        );

        expect(result.summary, isNotNull);
        expect(result.description, isNotNull);
        expect(result.location, isNotNull);
        expect(result.start, isNotNull);
        expect(result.end, isNotNull);

        expect(result.summary, contains('retreat'));
        expect(result.description, contains('lunch'));
        expect(result.location, contains('Mountain View Resort'));
      }, skip: 'Requires real API key');
      group('Date Handling and Timezone Tests', () {
        test(
          'correctly interprets time in user timezone',
          () async {
            final apiKey =
                dotenv.env['OPENAI_API_KEY'] ??
                const String.fromEnvironment('OPENAI_API_KEY');

            if (apiKey.isEmpty || apiKey == 'your_openai_api_key_here') {
              markTestSkipped('No OpenAI API key provided');
              return;
            }

            final settings = Settings(
              openAiApiKey: apiKey,
              openAiModel: 'gpt-4.1-nano',
              maxRetries: 1,
              timeoutSeconds: 30,
            );
            final interpreter = OpenAiCalendarEventInterpreter(settings);

            // Test: "Dentist tomorrow at 6pm" in UTC+2 timezone
            // Should create event at 6pm local time (4pm UTC = 6pm UTC+2)
            final eventText = 'Dentist tomorrow at 6pm';

            final result = await interpreter.eventToCalendarPropertiesAsync(
              eventText,
            );

            expect(result, isNotNull);
            expect(result.start, isNotNull);
            expect(result.end, isNotNull);

            final startTimeUtc = DateTime.parse(result.start!).toUtc();

            // Check that it's actually tomorrow, 6PM local time
            final now = DateTime.now();
            final tomorrow = now.add(Duration(days: 1));
            final expectedStartUtc = DateTime(
              tomorrow.year,
              tomorrow.month,
              tomorrow.day,
              18,
            ).toUtc();
            expect(
              startTimeUtc.toIso8601String(),
              equals(expectedStartUtc.toIso8601String()),
            );
          },
          skip: 'Requires real API key',
        );
      });

      group('Multiple Event Handling Tests', () {
        test(
          'processes multiple events from International Week text',
          () async {
            final apiKey =
                dotenv.env['OPENAI_API_KEY'] ??
                const String.fromEnvironment('OPENAI_API_KEY');

            if (apiKey.isEmpty || apiKey == 'your_openai_api_key_here') {
              markTestSkipped('No OpenAI API key provided');
              return;
            }

            final settings = Settings(
              openAiApiKey: apiKey,
              openAiModel:
                  'gpt-4.1-nano',
              maxRetries: 1,
              timeoutSeconds:
                  60,
            );
            final interpreter = OpenAiCalendarEventInterpreter(settings);

            final eventText = '''\
We are excited to announce our 4th International Week event series from May 5th to May 10th! 🎊
We have five diverse programs planned, and we hope everyone finds one that suits them perfectly. The primary goal of International Week is to create opportunities for all students at BME to connect. This event will allow you to meet new students from around the world and get to know Hungarian students as well.
Here is the program plan of the week:
🖼️*May 5th, 16:00*: Art Exhibition @K Ballroom
https://www.facebook.com/events/1025436869510359
🍷*May 5th, 19:00*: Night of Wine @K Ballroom
https://www.facebook.com/events/1784358835459005
💃🏼*May 6th, 17:00*: Folk Night @Baross Gábor Dormitory
https://www.facebook.com/events/1711503172909771
🪩*May 8th 21:00*: Party @VPK Dormitory
https://www.facebook.com/events/1158943645913044
🏅*May 10th 15:00*: Sport's Day @BME Sporttelep
https://www.facebook.com/events/1348334763166427
''';

            final results = await interpreter.eventsToCalendarPropertiesAsync(
              eventText,
            );

            expect(results, isNotNull);
            expect(results.length, 5);

            // Event 1: Art Exhibition
            expect(results[0].summary, contains('Art Exhibition'));
            expect(results[0].start, contains('05-05T16:00:00'));
            expect(results[0].location, contains('K Ballroom'));

            // Event 2: Night of Wine
            expect(results[1].summary, contains('Night of Wine'));
            expect(results[1].start, contains('05-05T19:00:00'));
            expect(results[1].location, contains('K Ballroom'));

            // Event 3: Folk Night
            expect(results[2].summary, contains('Folk Night'));
            expect(results[2].start, contains('05-06T17:00:00'));
            expect(results[2].location, contains('Baross Gábor'));

            // Event 4: Party
            expect(results[3].summary, contains('Party'));
            expect(results[3].start, contains('05-08T21:00:00'));
            expect(results[3].location, contains('VPK Dormitory'));

            // Event 5: Sport's Day
            expect(results[4].summary, contains('Sport\'s Day'));
            expect(results[4].start, contains('05-10T15:00:00'));
            expect(results[4].location, contains('BME Sporttelep'));
          },
          skip: 'Requires real API key and multi-event capable model',
        );

        test(
          'processes multiple events from Fair of Wonders schedule',
          () async {
            final apiKey =
                dotenv.env['OPENAI_API_KEY'] ??
                const String.fromEnvironment('OPENAI_API_KEY');

            if (apiKey.isEmpty || apiKey == 'your_openai_api_key_here') {
              markTestSkipped('No OpenAI API key provided');
              return;
            }

            final settings = Settings(
              openAiApiKey: apiKey,
              openAiModel: 'gpt-4.1-nano',
              maxRetries: 1,
              timeoutSeconds: 60,
            );
            final interpreter = OpenAiCalendarEventInterpreter(settings);

            final eventText = '''\
Fair of Wonders – One-Day Schedule

Morning
- 9:00 AM: Fair Opens & Welcome Parade  
- 10:00 AM: Opening Ceremony (Main Stage) 
- 11:45 AM: Local Band Performance (Main Stage)

Afternoon
- 12:30 PM: Food Trucks Open (Food Court) 
- 2:00 PM: Cooking Demonstration (Culinary Tent)  
- 4:00 PM: Art Contest Judging (Art Pavilion)

Evening
- 5:00 PM: Sunset Stroll & Lantern Lighting  
- 7:00 PM: Fireworks Finale (Fairgrounds)  
''';
            final results = await interpreter.eventsToCalendarPropertiesAsync(
              eventText,
            );

            expect(results, isNotNull);
            // Expecting 8 events based on the provided text
            expect(results.length, 8);

            // Event 1: Fair Opens & Welcome Parade
            expect(
              results[0].summary,
              isNotNull,
            ); // e.g., contains('Fair Opens') or similar
            expect(results[0].start, contains('T09:00:00'));
            // Location might not be specified for this one or could be general like "Fairgrounds"

            // Event 2: Opening Ceremony
            expect(results[1].summary, contains('Opening'));
            expect(results[1].start, contains('T10:00:00'));
            expect(results[1].location, contains('Main Stage'));

            // Event 3: Local Band Performance
            expect(results[2].summary, contains('Band'));
            expect(results[2].start, contains('T11:45:00'));
            expect(results[2].location, contains('Main Stage'));

            // Event 4: Food Trucks Open
            expect(results[3].summary, contains('Food Truck'));
            expect(results[3].start, contains('T12:30:00'));
            expect(results[3].location, contains('Food Court'));

            // Event 5: Cooking Demonstration
            expect(results[4].summary, contains('Cooking'));
            expect(results[4].start, contains('T14:00:00'));
            expect(results[4].location, contains('Culinary Tent'));

            // Event 6: Art Contest Judging
            expect(results[5].summary, contains('Art Contest'));
            expect(results[5].start, contains('T16:00:00'));
            expect(results[5].location, contains('Art Pavilion'));

            // Event 7: Sunset Stroll & Lantern Lighting
            expect(results[6].summary, contains('Sunset'));
            expect(results[6].start, contains('T17:00:00'));
            // Location might not be specified or could be general

            // Event 8: Fireworks Finale
            expect(results[7].summary, contains('Fireworks'));
            expect(results[7].start, contains('T19:00:00'));
            expect(results[7].location, contains('Fairgrounds'));
          },
          skip: 'Requires real API key and multi-event capable model',
        );
      });
    });
  });
}
