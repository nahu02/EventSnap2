import 'package:event_snap_2/models/ai_provider.dart';
import 'package:event_snap_2/models/extraction.dart';
import 'package:event_snap_2/models/settings.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/services/ai/legacy/legacy_ai_service_factory.dart';
import 'package:event_snap_2/services/openai_calendar_event_interpreter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // .env is optional (absent in CI).
    }
  });

  group('OpenAiCalendarEventInterpreter (legacy)', () {
    const validSettings = Settings(
      openAiApiKey: 'sk-test123456789abcdef',
      openAiModel: 'gpt-4.1-nano',
      maxRetries: 3,
      timeoutSeconds: 30,
    );

    group('constructor', () {
      test('accepts settings with an OpenAI key', () {
        expect(
          () => OpenAiCalendarEventInterpreter(validSettings),
          returnsNormally,
        );
      });

      test('throws without an OpenAI key', () {
        expect(
          () => OpenAiCalendarEventInterpreter(Settings.defaults()),
          throwsArgumentError,
        );
      });
    });

    test('rejects empty text', () {
      final interpreter = OpenAiCalendarEventInterpreter(validSettings);
      expect(() => interpreter.extractEventsFromText(''), throwsArgumentError);
      expect(
        () => interpreter.extractEventsFromText('   '),
        throwsArgumentError,
      );
    });

    test('detects reasoning models', () {
      for (final id in ['gpt-5-mini', 'gpt-5', 'o3', 'o4-mini', 'gpt-6']) {
        expect(
          OpenAiCalendarEventInterpreter.isReasoningModel(id),
          isTrue,
          reason: id,
        );
      }
      for (final id in ['gpt-4.1', 'gpt-4o-mini', 'gpt-3.5-turbo', 'omni']) {
        expect(
          OpenAiCalendarEventInterpreter.isReasoningModel(id),
          isFalse,
          reason: id,
        );
      }
    });

    group('parseEventsResponse', () {
      const start = '2025-05-25T10:00:00+02:00';
      const end = '2025-05-25T11:00:00+02:00';

      test('parses capitalised keys (v2 OpenAI format)', () {
        final result = OpenAiCalendarEventInterpreter.parseEventsResponse('''
          {"events": [{
            "Summary": "Test Event",
            "Description": "Test Description",
            "Location": "Test Location",
            "Start": "$start",
            "End": "$end"
          }]}''');
        final event = result.events.single;
        expect(event.title, 'Test Event');
        expect(event.description, 'Test Description');
        expect(event.location, 'Test Location');
        expect(event.startDateTime.isUtc, isFalse);
        expect(event.startDateTime, DateTime.parse(start).toLocal());
        expect(event.endDateTime, DateTime.parse(end).toLocal());
        expect(result.warnings, isEmpty);
      });

      test('parses lowercase keys', () {
        final result = OpenAiCalendarEventInterpreter.parseEventsResponse(
          '{"events": [{"summary": "Lower", "start": "$start", "end": "$end"}]}',
        );
        expect(result.events.single.title, 'Lower');
      });

      test('prefers capitalised keys over lowercase ones', () {
        final result = OpenAiCalendarEventInterpreter.parseEventsResponse(
          '{"events": [{"Summary": "Capitalized", "summary": "lowercase", '
          '"Start": "$start", "End": "$end"}]}',
        );
        expect(result.events.single.title, 'Capitalized');
      });

      test('accepts a bare array, a single object and code fences', () {
        expect(
          OpenAiCalendarEventInterpreter.parseEventsResponse(
            '[{"Summary": "A", "Start": "$start", "End": "$end"}]',
          ).events,
          hasLength(1),
        );
        expect(
          OpenAiCalendarEventInterpreter.parseEventsResponse(
            '{"Summary": "A", "Start": "$start", "End": "$end"}',
          ).events,
          hasLength(1),
        );
        expect(
          OpenAiCalendarEventInterpreter.parseEventsResponse(
            '```json\n{"events": [{"Summary": "A", "Start": "$start"}]}\n```',
          ).events,
          hasLength(1),
        );
      });

      test('returns no events for an empty list', () {
        final result = OpenAiCalendarEventInterpreter.parseEventsResponse(
          '{"events": []}',
        );
        expect(result.events, isEmpty);
        expect(result.rawResponse, '{"events": []}');
      });

      test('defaults a missing title and a missing/invalid end', () {
        final result = OpenAiCalendarEventInterpreter.parseEventsResponse(
          '{"events": [{"Start": "$start"}, '
          '{"Summary": "Backwards", "Start": "$end", "End": "$start"}]}',
        );
        expect(result.events[0].title, 'Untitled event');
        expect(result.events[0].duration, const Duration(hours: 1));
        expect(result.events[1].duration, const Duration(hours: 1));
        expect(result.events[1].startDateTime, DateTime.parse(end).toLocal());
      });

      test('skips unusable events with a warning', () {
        final result = OpenAiCalendarEventInterpreter.parseEventsResponse(
          '{"events": [{"Summary": "No start"}, '
          '{"Summary": "Bad date", "Start": "invalid-date"}, '
          '"not an object", '
          '{"Summary": "Good", "Start": "$start", "End": "$end"}]}',
        );
        expect(result.events.single.title, 'Good');
        expect(result.warnings, hasLength(3));
      });

      test('throws invalidResponse for non-JSON', () {
        expect(
          () => OpenAiCalendarEventInterpreter.parseEventsResponse('Sorry!'),
          throwsA(
            isA<AiException>().having(
              (e) => e.kind,
              'kind',
              AiErrorKind.invalidResponse,
            ),
          ),
        );
      });
    });

    group('live API (needs OPENAI_API_KEY in .env)', () {
      String apiKey() {
        final key = dotenv.isInitialized
            ? (dotenv.env['OPENAI_API_KEY'] ?? '')
            : '';
        return key == 'your_openai_api_key_here' ? '' : key;
      }

      test('extracts multiple events end-to-end', () async {
        final key = apiKey();
        if (key.isEmpty) {
          markTestSkipped('No OpenAI API key provided');
          return;
        }
        final settings = Settings(openAiApiKey: key, maxRetries: 1);
        final result = await LegacyAiServiceFactory()
            .createInterpreter(settings)
            .extractEvents(
              const ExtractionInput(
                text: 'Team lunch next Monday at 12, then project review from 3 to 4 PM.',
              ),
            );
        expect(result.provider, AiProvider.openai);
        expect(result.events.length, greaterThanOrEqualTo(2));
      }, skip: 'Requires a real API key');
    });
  });
}
