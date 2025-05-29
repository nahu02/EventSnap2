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
        openAiModel: 'gpt-4',
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
          openAiModel: 'gpt-4.1',
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
          openAiModel: 'gpt-4.1',
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
              openAiModel: 'gpt-4.1',
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
    });
  });
}
