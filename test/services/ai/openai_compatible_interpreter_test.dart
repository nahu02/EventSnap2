import 'dart:async';
import 'dart:convert';

import 'package:event_snap_2/models/ai_provider.dart';
import 'package:event_snap_2/models/extraction.dart';
import 'package:event_snap_2/models/field_evidence.dart';
import 'package:event_snap_2/models/settings.dart';
import 'package:event_snap_2/services/ai/ai_cancellation_token.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/services/ai/default_ai_service_factory.dart';
import 'package:event_snap_2/services/ai/default_model_catalog.dart';
import 'package:event_snap_2/services/ai/extraction_schema.dart';
import 'package:event_snap_2/services/ai/model_profile.dart';
import 'package:event_snap_2/services/ai/openai_compatible_client.dart';
import 'package:event_snap_2/services/ai/openai_compatible_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'ai_test_helpers.dart';

void main() {
  final now = DateTime(2026, 11, 21, 14, 5);
  final offset = now.timeZoneOffset;
  String ts(int day, int hour) {
    final sign = offset.isNegative ? '-' : '+';
    final h = offset.inHours.abs().toString().padLeft(2, '0');
    final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '2026-11-${day.toString().padLeft(2, '0')}T'
        '${hour.toString().padLeft(2, '0')}:00:00$sign$h:$m';
  }

  final validContent = eventsJson([
    wireEvent(start: ts(27, 19), end: ts(27, 21)),
  ]);
  const textInput = ExtractionInput(
    text: "Dinner with Anna next Friday at 7pm at Luigi's",
  );

  const opperSettings = Settings(
    provider: AiProvider.opper,
    opperApiKey: 'opper-test-key',
    opperModel: 'openai/gpt-5-mini',
  );

  const visionProfile = ModelProfile(
    modelId: 'openai/gpt-5-mini',
    supportsStructuredOutput: true,
    supportsVision: true,
    reasoningEfforts: ['minimal', 'low', 'medium', 'high'],
  );

  OpenAiCompatibleInterpreter interpreter(
    RecordingClient recording, {
    Settings settings = opperSettings,
    ModelProfile profile = visionProfile,
    ModelProfileResolver? resolver,
    AiSessionState? session,
    ImageBytesReader? imageReader,
    int maxImagePayloadBytes =
        OpenAiCompatibleInterpreter.defaultMaxImagePayloadBytes,
  }) => OpenAiCompatibleInterpreter(
    settings: settings,
    client: OpenAiCompatibleClient(
      httpClient: recording.client,
      maxRetries: 0,
      delay: (_) async {},
    ),
    profileResolver: resolver ?? FixedProfileResolver(profile),
    sessionState: session,
    clock: () => now,
    imageReader: imageReader ?? (_) async => [1, 2, 3, 4, 5],
    maxImagePayloadBytes: maxImagePayloadBytes,
  );

  Future<AiException> failure(Future<Object?> future) async {
    try {
      await future;
    } on AiException catch (e) {
      return e;
    }
    fail('expected an AiException');
  }

  group('request shape', () {
    test('Opper: strict json_schema, bearer auth, reasoning effort', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse(validContent),
      );
      final result = await interpreter(recording).extractEvents(textInput);

      final request = recording.requests.single;
      expect(
        request.url.toString(),
        'https://api.opper.ai/v3/compat/chat/completions',
      );
      expect(request.headers['Authorization'], 'Bearer opper-test-key');

      final body = recording.body(0);
      expect(body['model'], 'openai/gpt-5-mini');
      expect(
        body['response_format'],
        ExtractionSchema.jsonSchemaResponseFormat,
      );
      expect(body['response_format']['json_schema']['strict'], isTrue);
      expect(body['reasoning_effort'], 'low');
      expect(body.containsKey('temperature'), isFalse);
      expect(body.containsKey('max_tokens'), isFalse);

      final messages = body['messages'] as List;
      expect(messages[0]['role'], 'system');
      expect(messages[0]['content'], contains('Friday 2026-11-27'));
      expect(messages[0]['content'], isNot(contains('"additionalProperties"')));
      expect(messages[1]['role'], 'user');
      expect(messages[1]['content'], contains('next Friday at 7pm'));

      expect(result.usedStructuredOutput, isTrue);
      expect(result.provider, AiProvider.opper);
      expect(result.model, 'openai/gpt-5-mini');
      expect(result.warnings, isEmpty);
      expect(result.rawResponse, validContent);
      expect(result.input, textInput);
      final event = result.events.single;
      expect(event.startDateTime, DateTime(2026, 11, 27, 19));
      expect(event.endDateTime, DateTime(2026, 11, 27, 21));
      expect(event.evidence[EventField.start]?.quote, 'next Friday at 7pm');
    });

    test('OpenAI via the factory: base URL and per-model quirks', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse(validContent),
      );
      final factory = DefaultAiServiceFactory(
        httpClient: recording.client,
        modelCatalog: DefaultModelCatalog(
          httpClient: recording.client,
          cacheStore: InMemoryCatalogCacheStore(),
        ),
        clock: () => now,
        delay: (_) async {},
      );

      await factory
          .createInterpreter(
            const Settings(openAiApiKey: 'sk-test', openAiModel: 'gpt-5-mini'),
          )
          .extractEvents(textInput);
      // OpenAI capabilities come from heuristics: no model list request.
      expect(recording.requests, hasLength(1));
      final reasoning = recording.body(0);
      expect(
        recording.requests[0].url.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(recording.requests[0].headers['Authorization'], 'Bearer sk-test');
      expect(reasoning['reasoning_effort'], 'low');
      expect(reasoning.containsKey('temperature'), isFalse);

      await factory
          .createInterpreter(
            const Settings(
              openAiApiKey: 'sk-test',
              openAiModel: 'gpt-4.1-mini',
            ),
          )
          .extractEvents(textInput);
      final classic = recording.body(1);
      expect(classic['temperature'], 0.2);
      expect(classic.containsKey('reasoning_effort'), isFalse);
      expect(classic['response_format']['type'], 'json_schema');
    });

    test(
      'structured output off: JSON mode, schema in prompt, no warning',
      () async {
        final recording = RecordingClient(
          (_, _) async => chatResponse(validContent),
        );
        final result = await interpreter(
          recording,
          settings: opperSettings.copyWith(
            structuredOutputMode: StructuredOutputMode.off,
          ),
        ).extractEvents(textInput);

        final body = recording.body(0);
        expect(body['response_format'], {'type': 'json_object'});
        expect(
          (body['messages'] as List)[0]['content'],
          contains(ExtractionSchema.schemaText),
        );
        expect(result.usedStructuredOutput, isFalse);
        expect(result.warnings, isEmpty);
        expect(result.events, hasLength(1));
      },
    );

    test('a model without structured output starts in JSON mode', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse(validContent),
      );
      final result = await interpreter(
        recording,
        profile: const ModelProfile(
          modelId: 'x',
          supportsStructuredOutput: false,
          acceptsTemperature: true,
          minTemperature: 0,
          maxTemperature: 1,
        ),
      ).extractEvents(textInput);
      final body = recording.body(0);
      expect(body['response_format'], {'type': 'json_object'});
      expect(body['temperature'], 0.2);
      expect(result.usedStructuredOutput, isFalse);
      expect(result.warnings.single, contains('JSON mode'));
    });

    test('unknown capabilities still try strict structured output', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse(validContent),
      );
      await interpreter(
        recording,
        profile: const ModelProfile.unknown('acme/x'),
      ).extractEvents(textInput);
      final body = recording.body(0);
      expect(body['response_format']['type'], 'json_schema');
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body.containsKey('temperature'), isFalse);
    });

    test('a failing profile resolver falls back to heuristics', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse(validContent),
      );
      final result = await interpreter(
        recording,
        resolver: _ThrowingResolver(),
      ).extractEvents(textInput);
      expect(result.events, hasLength(1));
    });
  });

  group('downgrade ladder', () {
    test(
      'json_schema → json_object → prompt only, remembered per model',
      () async {
        final session = AiSessionState();
        final recording = RecordingClient((request, index) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final format = body['response_format']?['type'];
          if (format == 'json_schema') {
            return errorResponse(
              400,
              "Invalid parameter: 'response_format' of type 'json_schema' is "
              'not supported with this model.',
              param: 'response_format',
            );
          }
          if (format == 'json_object') {
            return errorResponse(
              400,
              "'response_format' of type 'json_object' is not supported.",
              param: 'response_format',
            );
          }
          return chatResponse('```json\n$validContent\n```');
        });

        final result = await interpreter(
          recording,
          session: session,
        ).extractEvents(textInput);
        expect(recording.requests, hasLength(3));
        expect(recording.body(0)['response_format']['type'], 'json_schema');
        expect(recording.body(1)['response_format']['type'], 'json_object');
        expect(recording.body(2).containsKey('response_format'), isFalse);
        expect(
          (recording.body(2)['messages'] as List)[0]['content'],
          contains(ExtractionSchema.schemaText),
        );
        expect(result.usedStructuredOutput, isFalse);
        expect(result.events, hasLength(1));
        expect(result.warnings.single, contains('less reliable'));
        expect(
          session.levelFor(AiProvider.opper, 'openai/gpt-5-mini'),
          StructuredOutputLevel.promptOnly,
        );

        // A new interpreter in the same session starts at prompt-only.
        await interpreter(recording, session: session).extractEvents(textInput);
        expect(recording.requests, hasLength(4));
        expect(recording.body(3).containsKey('response_format'), isFalse);

        // Other models are unaffected.
        await interpreter(
          recording,
          session: session,
          settings: opperSettings.copyWith(opperModel: 'anthropic/claude-x'),
        ).extractEvents(textInput);
        expect(recording.body(4)['response_format']['type'], 'json_schema');
      },
    );

    test(
      'a schema validation error from the gateway also downgrades',
      () async {
        final recording = RecordingClient(
          (_, index) async => index == 0
              ? errorResponse(422, 'Output failed JSON schema validation')
              : chatResponse(validContent),
        );
        final result = await interpreter(recording).extractEvents(textInput);
        expect(recording.requests, hasLength(2));
        expect(recording.body(1)['response_format'], {'type': 'json_object'});
        expect(result.events, hasLength(1));
      },
    );

    test('a rejected reasoning_effort is dropped and remembered', () async {
      final session = AiSessionState();
      final recording = RecordingClient((request, _) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body.containsKey('reasoning_effort')) {
          return errorResponse(
            400,
            "Unsupported value: 'reasoning_effort' does not support 'low' "
            'with this model.',
            param: 'reasoning_effort',
          );
        }
        return chatResponse(validContent);
      });
      final result = await interpreter(
        recording,
        session: session,
      ).extractEvents(textInput);
      expect(recording.requests, hasLength(2));
      expect(recording.body(1).containsKey('reasoning_effort'), isFalse);
      // Structured output is kept.
      expect(recording.body(1)['response_format']['type'], 'json_schema');
      expect(result.usedStructuredOutput, isTrue);

      await interpreter(recording, session: session).extractEvents(textInput);
      expect(recording.requests, hasLength(3));
      expect(recording.body(2).containsKey('reasoning_effort'), isFalse);
    });

    test('a rejected temperature is dropped', () async {
      final recording = RecordingClient((request, _) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body.containsKey('temperature')) {
          return errorResponse(
            400,
            "Unsupported value: 'temperature' does not support 0.2.",
          );
        }
        return chatResponse(validContent);
      });
      await interpreter(
        recording,
        profile: const ModelProfile(modelId: 'x', acceptsTemperature: true),
      ).extractEvents(textInput);
      expect(recording.requests, hasLength(2));
      expect(recording.body(1).containsKey('temperature'), isFalse);
    });

    test('other 400s are not retried', () async {
      final recording = RecordingClient(
        (_, _) async => errorResponse(400, "Invalid 'messages[1]'"),
      );
      final e = await failure(interpreter(recording).extractEvents(textInput));
      expect(e.kind, AiErrorKind.unknown);
      expect(recording.requests, hasLength(1));
    });

    test('errors are mapped (auth, model not found)', () async {
      for (final (response, kind) in [
        (errorResponse(401, 'Invalid API key'), AiErrorKind.auth),
        (errorResponse(404, 'model not found'), AiErrorKind.modelNotFound),
        (errorResponse(402, 'Insufficient credits'), AiErrorKind.quotaExceeded),
      ]) {
        final recording = RecordingClient((_, _) async => response);
        final e = await failure(
          interpreter(recording).extractEvents(textInput),
        );
        expect(e.kind, kind);
        expect(recording.requests, hasLength(1));
      }
    });
  });

  group('images', () {
    const imageInput = ExtractionInput(
      text: 'See the flyer',
      images: [InputImage(path: '/tmp/flyer.png', mimeType: 'image/png')],
    );

    test('are sent as base64 data URL content parts', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse(validContent),
      );
      final readPaths = <String>[];
      await interpreter(
        recording,
        imageReader: (path) async {
          readPaths.add(path);
          return utf8.encode('PNGDATA');
        },
      ).extractEvents(imageInput);

      expect(readPaths, ['/tmp/flyer.png']);
      final content = (recording.body(0)['messages'] as List)[1]['content'];
      expect(content, isA<List<dynamic>>());
      expect(content[0]['type'], 'text');
      expect(content[0]['text'], contains('See the flyer'));
      expect(content[0]['text'], contains('attached image'));
      expect(content[1], {
        'type': 'image_url',
        'image_url': {
          'url':
              'data:image/png;base64,${base64Encode(utf8.encode('PNGDATA'))}',
        },
      });
    });

    test('image-only input', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse(validContent),
      );
      await interpreter(recording).extractEvents(
        const ExtractionInput(
          images: [
            InputImage(path: '/a', mimeType: 'application/octet-stream'),
          ],
        ),
      );
      final content =
          (recording.body(0)['messages'] as List)[1]['content'] as List;
      expect(
        content[0]['text'],
        'Extract the calendar events from the attached image.',
      );
      expect(
        content[1]['image_url']['url'],
        startsWith('data:image/jpeg;base64,'),
      );
    });

    test('are refused early for a model known to lack vision', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse(validContent),
      );
      final e = await failure(
        interpreter(
          recording,
          profile: const ModelProfile(modelId: 'x', supportsVision: false),
        ).extractEvents(imageInput),
      );
      expect(e.kind, AiErrorKind.unsupportedInput);
      expect(recording.requests, isEmpty);
    });

    test('are capped in total size', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse(validContent),
      );
      final e = await failure(
        interpreter(
          recording,
          maxImagePayloadBytes: 100,
          imageReader: (_) async => List.filled(200, 7),
        ).extractEvents(imageInput),
      );
      expect(e.kind, AiErrorKind.unsupportedInput);
      expect(e.message, contains('too large'));
      expect(recording.requests, isEmpty);
    });

    test('an unreadable image is unsupportedInput', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse(validContent),
      );
      final e = await failure(
        interpreter(
          recording,
          imageReader: (_) async => throw StateError('gone'),
        ).extractEvents(imageInput),
      );
      expect(e.kind, AiErrorKind.unsupportedInput);
      expect(recording.requests, isEmpty);
    });

    test('a vision error from the API is unsupportedInput', () async {
      final recording = RecordingClient(
        (_, _) async => errorResponse(
          400,
          'Invalid content type. image_url is only supported by certain '
          'models.',
        ),
      );
      final e = await failure(
        interpreter(
          recording,
          profile: const ModelProfile.unknown('x'),
        ).extractEvents(imageInput),
      );
      expect(e.kind, AiErrorKind.unsupportedInput);
      expect(recording.requests, hasLength(1));
    });
  });

  group('preconditions, cancellation and responses', () {
    test(
      'missing key is notConfigured; empty input is unsupportedInput',
      () async {
        final recording = RecordingClient(
          (_, _) async => chatResponse(validContent),
        );
        expect(
          (await failure(
            interpreter(
              recording,
              settings: const Settings(provider: AiProvider.opper),
            ).extractEvents(textInput),
          )).kind,
          AiErrorKind.notConfigured,
        );
        expect(
          (await failure(
            interpreter(recording)
                .extractEvents(const ExtractionInput(text: ' ')),
          )).kind,
          AiErrorKind.unsupportedInput,
        );
        expect(recording.requests, isEmpty);
      },
    );

    test('a cancelled token stops before any request', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse(validContent),
      );
      final e = await failure(
        interpreter(recording).extractEvents(
          textInput,
          cancellationToken: AiCancellationToken()..cancel(),
        ),
      );
      expect(e.kind, AiErrorKind.cancelled);
      expect(recording.requests, isEmpty);
    });

    test('cancelling during the request', () async {
      final started = Completer<void>();
      final recording = RecordingClient((_, _) {
        started.complete();
        return Completer<http.Response>().future;
      });
      final token = AiCancellationToken();
      final future = interpreter(recording)
          .extractEvents(textInput, cancellationToken: token);
      await started.future;
      token.cancel();
      expect((await failure(future)).kind, AiErrorKind.cancelled);
    });

    test('cancelling while the profile is resolved', () async {
      final gate = Completer<ModelProfile>();
      final recording = RecordingClient(
        (_, _) async => chatResponse(validContent),
      );
      final token = AiCancellationToken();
      final future = interpreter(
        recording,
        resolver: _GatedResolver(gate.future),
      ).extractEvents(textInput, cancellationToken: token);
      token.cancel();
      expect((await failure(future)).kind, AiErrorKind.cancelled);
      expect(recording.requests, isEmpty);
    });

    test('empty, refused or non-JSON content is invalidResponse', () async {
      for (final response in [
        chatResponse(null),
        chatResponse('   '),
        chatResponse('No events here, sorry!'),
        jsonResponse({
          'choices': [
            {
              'message': {'content': null, 'refusal': 'I cannot help'},
              'finish_reason': 'stop',
            },
          ],
        }),
      ]) {
        final recording = RecordingClient((_, _) async => response);
        final e = await failure(
          interpreter(recording).extractEvents(textInput),
        );
        expect(e.kind, AiErrorKind.invalidResponse);
      }
    });

    test('no events is a valid, empty result', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse('{"events":[]}'),
      );
      final result = await interpreter(recording).extractEvents(textInput);
      expect(result.events, isEmpty);
      expect(result.usedStructuredOutput, isTrue);
    });

    test('skipped events become warnings', () async {
      final recording = RecordingClient(
        (_, _) async => chatResponse(
          eventsJson([
            wireEvent(start: ts(27, 19), end: ts(27, 20)),
            wireEvent(start: 'someday'),
          ]),
        ),
      );
      final result = await interpreter(recording).extractEvents(textInput);
      expect(result.events, hasLength(1));
      expect(result.warnings.single, contains('Skipped event 2'));
    });
  });

  group('DefaultAiServiceFactory', () {
    test('shares the catalogue and the session state', () {
      final factory = DefaultAiServiceFactory(
        httpClient: RecordingClient((_, _) async => chatResponse('')).client,
      );
      expect(factory.modelCatalog, isA<DefaultModelCatalog>());
      expect(
        factory.createInterpreter(opperSettings),
        isA<OpenAiCompatibleInterpreter>(),
      );
      final a = factory.createInterpreter(opperSettings);
      final b = factory.createInterpreter(opperSettings);
      expect(identical(a, b), isFalse);
      expect(factory.sessionState, isA<AiSessionState>());
      expect(
        factory.reasoningEffortPreference,
        OpenAiCompatibleInterpreter.defaultReasoningEffortPreference,
      );
    });

    test('uses settings for timeout and retries', () async {
      var calls = 0;
      final recording = RecordingClient((_, _) async {
        calls++;
        return errorResponse(503, 'busy');
      });
      final factory = DefaultAiServiceFactory(
        httpClient: recording.client,
        modelCatalog: DefaultModelCatalog(
          httpClient: recording.client,
          cacheStore: InMemoryCatalogCacheStore(),
        ),
        delay: (_) async {},
        clock: () => now,
      );
      final e = await failure(
        factory
            .createInterpreter(
              const Settings(openAiApiKey: 'sk-x', maxRetries: 3),
            )
            .extractEvents(textInput),
      );
      expect(e.kind, AiErrorKind.server);
      expect(calls, 4);
    });
  });
}

class _ThrowingResolver implements ModelProfileResolver {
  @override
  Future<ModelProfile> resolveProfile(
    AiProvider provider,
    String modelId, {
    required String apiKey,
  }) async => throw StateError('broken');
}

class _GatedResolver implements ModelProfileResolver {
  _GatedResolver(this.gate);
  final Future<ModelProfile> gate;

  @override
  Future<ModelProfile> resolveProfile(
    AiProvider provider,
    String modelId, {
    required String apiKey,
  }) => gate;
}
