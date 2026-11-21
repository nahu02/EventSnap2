// Live smoke tests against the real APIs. Skipped unless a key is set:
//
//   env $(cat .env) flutter test test/services/ai/live_api_test.dart
//
// OPPER_API_KEY: key verification (free), model list (free), one text and one
// image extraction with openai/gpt-5-nano at reasoning_effort "minimal"
// (about $0.0003 per run). OPENAI_API_KEY: key verification and one text
// extraction with gpt-5-nano. Keys are read from the environment only and
// never printed.
import 'dart:convert';
import 'dart:io';

import 'package:event_snap_2/models/ai_provider.dart';
import 'package:event_snap_2/models/event_model.dart';
import 'package:event_snap_2/models/extraction.dart';
import 'package:event_snap_2/models/field_evidence.dart';
import 'package:event_snap_2/models/settings.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/services/ai/default_ai_service_factory.dart';
import 'package:event_snap_2/services/ai/default_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Forwards to a real client and records request bodies and reported cost.
class _CostRecorder extends http.BaseClient {
  final http.Client _inner = http.Client();
  final List<Map<String, dynamic>> chatRequests = [];
  double cost = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isChat = request.url.path.endsWith('/chat/completions');
    if (isChat && request is http.Request) {
      chatRequests.add(jsonDecode(request.body) as Map<String, dynamic>);
    }
    final response = await _inner.send(request);
    if (!isChat) return response;
    final bytes = await response.stream.toBytes();
    try {
      final json = jsonDecode(utf8.decode(bytes));
      final value = json is Map
          ? (json['usage'] is Map ? json['usage']['cost'] : null) ??
                json['cost']
          : null;
      if (value is num) cost += value.toDouble();
    } catch (_) {
      // Not JSON: nothing to record.
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      request: response.request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

String? _env(String name) {
  final value = Platform.environment[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}

DateTime _nextWeekday(DateTime from, int weekday) {
  var day = DateTime(from.year, from.month, from.day + 1);
  while (day.weekday != weekday) {
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return day;
}

void _log(String message) => stdout.writeln('[live] $message');

String _describe(EventModel e) {
  final evidence = e.evidence.entries
      .map(
        (entry) =>
            '${entry.key.name}: "${entry.value.quote}" '
            '(${entry.value.confidence.name}) ${entry.value.reasoning}',
      )
      .join('\n      ');
  return '${e.title} | ${e.startDateTime} - ${e.endDateTime} '
      '| allDay: ${e.isAllDay} | location: ${e.location}\n      $evidence';
}

void main() {
  final opperKey = _env('OPPER_API_KEY');
  final openAiKey = _env('OPENAI_API_KEY');

  group('Opper (live)', () {
    final recorder = _CostRecorder();
    final catalog = DefaultModelCatalog(
      httpClient: recorder,
      cacheStore: InMemoryCatalogCacheStore(),
    );
    final factory = DefaultAiServiceFactory(
      httpClient: recorder,
      modelCatalog: catalog,
      // Budget rule for the dev key: cheapest effort only.
      reasoningEffortPreference: const ['minimal'],
    );
    final settings = Settings(
      provider: AiProvider.opper,
      opperApiKey: opperKey ?? '',
      opperModel: 'openai/gpt-5-nano',
      maxRetries: 0,
      timeoutSeconds: 90,
    );

    tearDownAll(() {
      _log(
        'Opper chat requests: ${recorder.chatRequests.length}, reported cost: '
        '\$${recorder.cost.toStringAsFixed(6)}',
      );
      recorder.close();
    });

    test('verifyApiKey accepts the key and rejects a wrong one', () async {
      await catalog.verifyApiKey(AiProvider.opper, opperKey!);
      await expectLater(
        catalog.verifyApiKey(AiProvider.opper, 'not-a-real-opper-key'),
        throwsA(
          isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.auth),
        ),
      );
    });

    test('lists the live catalogue with capabilities', () async {
      final models = await catalog.listModels(AiProvider.opper, apiKey: '');
      _log(
        'Opper models: ${models.length}, '
        'recommended: ${models.where((m) => m.recommended).length}',
      );
      expect(models.length, greaterThan(100));
      expect(models.first.id, AiProvider.opper.defaultModel);
      final nano = models.firstWhere((m) => m.id == 'openai/gpt-5-nano');
      expect(nano.supportsStructuredOutput, isTrue);
      expect(nano.supportsVision, isTrue);
      final profile = await catalog.resolveProfile(
        AiProvider.opper,
        'openai/gpt-5-nano',
        apiKey: '',
      );
      expect(profile.reasoningEfforts, contains('minimal'));
    });

    test('text: resolves "next Friday", all-day dates and evidence', () async {
      final now = DateTime.now();
      final friday = _nextWeekday(now, DateTime.friday);
      var partyYear = now.year;
      if (DateTime(
        partyYear,
        12,
        3,
      ).isBefore(DateTime(now.year, now.month, now.day))) {
        partyYear++;
      }

      final result = await factory
          .createInterpreter(settings)
          .extractEvents(
            const ExtractionInput(
              text:
                  "Dinner with Anna next Friday at 7pm at Luigi's on Main "
                  'Street. Also: the company holiday party is on 3 December, '
                  'all day.',
            ),
          );

      final request = recorder.chatRequests.last;
      expect(request['model'], 'openai/gpt-5-nano');
      expect(request['reasoning_effort'], 'minimal');
      expect(request['response_format']['type'], 'json_schema');
      expect(result.usedStructuredOutput, isTrue);
      for (final e in result.events) {
        _log('text event: ${_describe(e)}');
      }
      expect(result.events, hasLength(2));

      final dinner = result.events.firstWhere((e) => !e.isAllDay);
      expect(
        DateTime(
          dinner.startDateTime.year,
          dinner.startDateTime.month,
          dinner.startDateTime.day,
        ),
        friday,
      );
      expect(dinner.startDateTime.hour, 19);
      expect(dinner.location?.toLowerCase(), contains('luigi'));
      final startEvidence = dinner.evidence[EventField.start];
      expect(startEvidence, isNotNull);
      expect(startEvidence!.quote?.toLowerCase(), contains('friday'));
      expect(startEvidence.reasoning, isNotEmpty);

      final party = result.events.firstWhere((e) => e.isAllDay);
      expect(party.startDateTime, DateTime(partyYear, 12, 3));
      expect(party.endDateTime, DateTime(partyYear, 12, 4));
    });

    test('image: reads the event from a flyer', () async {
      final result = await factory
          .createInterpreter(settings)
          .extractEvents(
            const ExtractionInput(
              images: [
                InputImage(
                  path: 'test/fixtures/event_flyer.png',
                  mimeType: 'image/png',
                ),
              ],
            ),
          );
      final request = recorder.chatRequests.last;
      final content = (request['messages'] as List)[1]['content'] as List;
      expect(
        content[1]['image_url']['url'],
        startsWith('data:image/png;base64,'),
      );
      for (final e in result.events) {
        _log('image event: ${_describe(e)}');
      }
      final event = result.events.single;
      expect(event.title.toLowerCase(), contains('book club'));
      expect(event.startDateTime, DateTime(2026, 12, 4, 19));
      expect(event.endDateTime, DateTime(2026, 12, 4, 21));
      expect(event.location?.toLowerCase(), contains('library'));
    });
  }, skip: opperKey == null ? 'OPPER_API_KEY not set' : false);

  group('OpenAI (live)', () {
    final factory = DefaultAiServiceFactory(
      modelCatalog: DefaultModelCatalog(
        cacheStore: InMemoryCatalogCacheStore(),
      ),
    );

    test('verifyApiKey accepts the key and rejects a wrong one', () async {
      await factory.modelCatalog.verifyApiKey(AiProvider.openai, openAiKey!);
      await expectLater(
        factory.modelCatalog.verifyApiKey(AiProvider.openai, 'sk-invalid'),
        throwsA(
          isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.auth),
        ),
      );
    });

    test('text extraction with structured output', () async {
      final result = await factory
          .createInterpreter(
            Settings(
              openAiApiKey: openAiKey!,
              openAiModel: 'gpt-5-nano',
              maxRetries: 0,
            ),
          )
          .extractEvents(
            const ExtractionInput(text: 'Dentist on 9 December 2026 at 14:30'),
          );
      expect(result.usedStructuredOutput, isTrue);
      expect(result.events.single.startDateTime, DateTime(2026, 12, 9, 14, 30));
    });
  }, skip: openAiKey == null ? 'OPENAI_API_KEY not set' : false);
}
