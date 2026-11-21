import 'dart:convert';
import 'dart:io';

import 'package:event_snap_2/models/ai_model_info.dart';
import 'package:event_snap_2/models/ai_provider.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/services/ai/default_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'ai_test_helpers.dart';

void main() {
  final opperFixture = File('test/fixtures/opper_models_trimmed.json')
      .readAsStringSync();
  const openAiKey = 'sk-test-0123456789abcdef';

  Map<String, Object?> openAiList(List<String> ids) => {
    'object': 'list',
    'data': [
      for (final id in ids)
        {'id': id, 'object': 'model', 'created': 1, 'owned_by': 'system'},
    ],
  };

  late DateTime now;
  late InMemoryCatalogCacheStore store;

  setUp(() {
    now = DateTime(2026, 11, 21, 12);
    store = InMemoryCatalogCacheStore();
  });

  DefaultModelCatalog catalogFor(RecordingClient recording) =>
      DefaultModelCatalog(
        httpClient: recording.client,
        cacheStore: store,
        clock: () => now,
        delay: (_) async {},
      );

  RecordingClient opperServer() => RecordingClient((request, _) async {
    if (request.url.path == '/v3/models') {
      return http.Response(
        opperFixture,
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return jsonResponse({'error': 'not found'}, status: 404);
  });

  AiModelInfo byId(List<AiModelInfo> models, String id) =>
      models.firstWhere((m) => m.id == id);

  group('Opper', () {
    test('fetches the public list without a key', () async {
      final recording = opperServer();
      await catalogFor(recording)
          .listModels(AiProvider.opper, apiKey: 'ignored-key');
      final request = recording.requests.single;
      expect(request.url.host, 'api.opper.ai');
      expect(request.url.path, '/v3/models');
      expect(request.url.queryParameters, {'type': 'llm', 'limit': '0'});
      expect(request.headers['Authorization'], isNull);
    });

    test('maps capabilities, metadata and recommendations', () async {
      final models = await catalogFor(opperServer())
          .listModels(AiProvider.opper, apiKey: '');

      // Batch-only route left out.
      expect(models, hasLength(11));
      expect(models.any((m) => m.id.startsWith('openai-batch/')), isFalse);

      // Default first, then the other recommended models.
      expect(models.first.id, 'openai/gpt-5-mini');
      expect(models.where((m) => m.recommended).map((m) => m.id).toList(), [
        'openai/gpt-5-mini',
        'anthropic/claude-haiku-5-5',
        'gemini/gemini-3.8-flash',
      ]);

      final mini = byId(models, 'openai/gpt-5-mini');
      expect(mini.provider, AiProvider.opper);
      expect(mini.displayName, 'GPT-5 Mini');
      expect(mini.vendor, 'OpenAI');
      expect(mini.supportsStructuredOutput, isTrue);
      expect(mini.supportsVision, isTrue);
      expect(mini.speed, 'fast');
      expect(mini.quality, 'great');
      expect(mini.contextWindow, greaterThan(100000));

      final search = byId(models, 'openai/gpt-5-search-api');
      expect(search.supportsStructuredOutput, isFalse);
      expect(search.supportsVision, isFalse);
      expect(search.recommended, isFalse);

      // Featured but no vision / third-party host / tier / region route /
      // duplicate route of a recommended model.
      expect(byId(models, 'zai/glm-5.3').recommended, isFalse);
      expect(byId(models, 'deepinfra/zai-org/GLM-5.3').recommended, isFalse);
      expect(byId(models, 'openai:flex/gpt-6-luna').recommended, isFalse);
      expect(byId(models, 'mistral:eu/mistral-large-4').recommended, isFalse);
      expect(byId(models, 'vertexai/gemini-3.8-flash').recommended, isFalse);

      // Routes of the same model can be told apart.
      expect(
        byId(models, 'deepinfra/zai-org/GLM-5.3').displayName,
        'GLM-5.3 (DeepInfra)',
      );
      expect(
        byId(models, 'openai:flex/gpt-6-luna').displayName,
        'GPT-6 Luna (flex)',
      );
      expect(
        byId(models, 'mistral:eu/mistral-large-4').displayName,
        'Mistral Large 4 (EU)',
      );
    });

    test('derives request quirks from params', () async {
      final catalog = catalogFor(opperServer());
      await catalog.listModels(AiProvider.opper, apiKey: '');

      final mini = await catalog.resolveProfile(
        AiProvider.opper,
        'openai/gpt-5-mini',
        apiKey: '',
      );
      expect(mini.reasoningEfforts, ['minimal', 'low', 'medium', 'high']);
      expect(mini.reasoningEffortFor(const ['low']), 'low');
      expect(mini.acceptsTemperature, isFalse);

      final gpt41 = await catalog.resolveProfile(
        AiProvider.opper,
        'openai/gpt-4.1-mini',
        apiKey: '',
      );
      expect(gpt41.reasoningEfforts, isEmpty);
      expect(gpt41.acceptsTemperature, isTrue);
      expect(gpt41.temperatureFor(0.2, sendsReasoning: false), 0.2);

      final glm = await catalog.resolveProfile(
        AiProvider.opper,
        'zai/glm-5.3',
        apiKey: '',
      );
      expect(glm.reasoningEfforts, ['low', 'high', 'max']);
      expect(glm.maxTemperature, 1);
      expect(glm.supportsVision, isFalse);
    });

    test('caches in memory and on disk for 24 hours', () async {
      final recording = opperServer();
      final catalog = catalogFor(recording);
      final first = await catalog.listModels(AiProvider.opper, apiKey: '');
      await catalog.listModels(AiProvider.opper, apiKey: '');
      expect(recording.requests, hasLength(1));

      // A new instance (app restart) uses the persisted list.
      final restarted = catalogFor(recording);
      final cached = await restarted.listModels(AiProvider.opper, apiKey: '');
      expect(recording.requests, hasLength(1));
      expect(cached, first);

      // Expired.
      now = now.add(const Duration(hours: 25));
      final expired = catalogFor(recording);
      await expired.listModels(AiProvider.opper, apiKey: '');
      expect(recording.requests, hasLength(2));
    });

    test('forceRefresh always fetches', () async {
      final recording = opperServer();
      final catalog = catalogFor(recording);
      await catalog.listModels(AiProvider.opper, apiKey: '');
      await catalog.listModels(
        AiProvider.opper,
        apiKey: '',
        forceRefresh: true,
      );
      expect(recording.requests, hasLength(2));
    });

    test('concurrent requests share one fetch', () async {
      final recording = opperServer();
      final catalog = catalogFor(recording);
      await Future.wait([
        catalog.listModels(AiProvider.opper, apiKey: ''),
        catalog.listModels(AiProvider.opper, apiKey: ''),
      ]);
      expect(recording.requests, hasLength(1));
    });

    test('returns a stale list when offline, unless forced', () async {
      await catalogFor(opperServer()).listModels(AiProvider.opper, apiKey: '');
      now = now.add(const Duration(days: 3));
      final offline = RecordingClient(
        (_, _) async => throw http.ClientException('offline'),
      );
      final catalog = catalogFor(offline);
      final stale = await catalog.listModels(AiProvider.opper, apiKey: '');
      expect(stale, hasLength(11));
      await expectLater(
        catalog.listModels(AiProvider.opper, apiKey: '', forceRefresh: true),
        throwsA(
          isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.network),
        ),
      );
    });

    test('a corrupt persisted cache is ignored', () async {
      store.values['opper'] = '{not json';
      final recording = opperServer();
      final models = await catalogFor(recording)
          .listModels(AiProvider.opper, apiKey: '');
      expect(models, hasLength(11));
      expect(recording.requests, hasLength(1));
    });

    test('findModel falls back to the single-model endpoint', () async {
      final recording = RecordingClient((request, _) async {
        if (request.url.path == '/v3/models') {
          return http.Response(opperFixture, 200);
        }
        if (request.url.path == '/v3/models/acme:eu/new-model') {
          return jsonResponse({
            'data': {
              'id': 'acme:eu/new-model',
              'type': 'llm',
              'name': 'New Model',
              'capabilities': ['text', 'vision'],
              'maker': {'slug': 'acme', 'display_name': 'Acme'},
              'provider': {'slug': 'acme', 'display_name': 'Acme'},
            },
            'meta': {},
          });
        }
        return jsonResponse({'error': 'model not found'}, status: 404);
      });
      final catalog = catalogFor(recording);
      expect(
        (await catalog.findModel(
          AiProvider.opper,
          'anthropic/claude-haiku-5-5',
          apiKey: '',
        ))?.vendor,
        'Anthropic',
      );
      final found = await catalog.findModel(
        AiProvider.opper,
        'acme:eu/new-model',
        apiKey: '',
      );
      expect(found?.displayName, 'New Model (EU)');
      expect(found?.supportsStructuredOutput, isFalse);
      expect(found?.supportsVision, isTrue);
      expect(
        await catalog.findModel(AiProvider.opper, 'nope/missing', apiKey: ''),
        isNull,
      );
      expect(
        await catalog.findModel(AiProvider.opper, ' ', apiKey: ''),
        isNull,
      );
    });

    test('resolveProfile fetches one model when nothing is cached', () async {
      final recording = RecordingClient((request, _) async {
        expect(request.url.path, '/v3/models/openai/gpt-5-nano');
        return jsonResponse({
          'data': jsonDecode(opperFixture)['models'][1],
          'meta': {},
        });
      });
      final catalog = catalogFor(recording);
      final profile = await catalog.resolveProfile(
        AiProvider.opper,
        'openai/gpt-5-nano',
        apiKey: '',
      );
      expect(profile.reasoningEfforts, contains('minimal'));
      expect(profile.supportsVision, isTrue);
      // Remembered for the session.
      await catalog.resolveProfile(
        AiProvider.opper,
        'openai/gpt-5-nano',
        apiKey: '',
      );
      expect(recording.requests, hasLength(1));
    });

    test('resolveProfile never throws (heuristic fallback)', () async {
      final offline = RecordingClient(
        (_, _) async => throw http.ClientException('offline'),
      );
      final catalog = catalogFor(offline);
      final profile = await catalog.resolveProfile(
        AiProvider.opper,
        'openai/gpt-5-mini',
        apiKey: '',
      );
      expect(profile.supportsStructuredOutput, isTrue);
      expect(profile.reasoningEfforts, isEmpty);
      final unknown = await catalog.resolveProfile(
        AiProvider.opper,
        'acme/thing',
        apiKey: '',
      );
      expect(unknown.supportsVision, isNull);
    });

    test('verifyApiKey uses the free authenticated models request', () async {
      final recording = RecordingClient((request, _) async {
        final auth = request.headers['Authorization'];
        if (auth == 'Bearer good-key') {
          return jsonResponse({'models': [], 'has_more': true});
        }
        return http.Response(
          '?include=route requires an Opper API key — pass it as '
          'Authorization: Bearer',
          401,
          headers: {'content-type': 'text/plain; charset=utf-8'},
        );
      });
      final catalog = catalogFor(recording);
      await catalog.verifyApiKey(AiProvider.opper, ' good-key ');
      final request = recording.requests.single;
      expect(request.url.path, '/v3/models');
      expect(request.url.queryParameters, {'include': 'route', 'limit': '1'});

      await expectLater(
        catalog.verifyApiKey(AiProvider.opper, 'bad-key'),
        throwsA(
          isA<AiException>()
              .having((e) => e.kind, 'kind', AiErrorKind.auth)
              .having((e) => e.statusCode, 'status', 401),
        ),
      );
      await expectLater(
        catalog.verifyApiKey(AiProvider.opper, '  '),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.notConfigured,
          ),
        ),
      );
    });
  });

  group('OpenAI', () {
    const ids = [
      'gpt-4.1',
      'gpt-5-mini',
      'text-embedding-3-large',
      'tts-1-hd',
      'whisper-1',
      'dall-e-3',
      'gpt-4o-realtime-preview',
      'gpt-4o-mini-search-preview',
      'gpt-3.5-turbo-instruct',
      'o3-pro',
      'gpt-5-codex',
      'gpt-3.5-turbo',
      'o1-mini',
      'gpt-4o',
      'gpt-5-mini',
      'ft:gpt-4o-mini-2024-07-18:acme::abc',
    ];

    RecordingClient openAiServer({String validKey = openAiKey}) =>
        RecordingClient((request, _) async {
          if (request.headers['Authorization'] != 'Bearer $validKey') {
            return errorResponse(
              401,
              'Incorrect API key provided: sk-bad***',
              code: 'invalid_api_key',
            );
          }
          return jsonResponse(openAiList(ids));
        });

    test('requires a key', () async {
      await expectLater(
        catalogFor(openAiServer()).listModels(AiProvider.openai, apiKey: ' '),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.notConfigured,
          ),
        ),
      );
    });

    test('filters chat models and applies heuristics', () async {
      final recording = openAiServer();
      final models = await catalogFor(recording)
          .listModels(AiProvider.openai, apiKey: openAiKey);

      final request = recording.requests.single;
      expect(request.url.toString(), 'https://api.openai.com/v1/models');
      expect(request.headers['Authorization'], 'Bearer $openAiKey');

      expect(models.map((m) => m.id).toList(), [
        'gpt-5-mini',
        'gpt-4.1',
        'ft:gpt-4o-mini-2024-07-18:acme::abc',
        'gpt-3.5-turbo',
        'gpt-4o',
        'o1-mini',
      ]);
      expect(models.first.recommended, isTrue);
      expect(byId(models, 'gpt-4.1').recommended, isTrue);
      expect(byId(models, 'gpt-4o').recommended, isFalse);
      expect(byId(models, 'gpt-3.5-turbo').supportsStructuredOutput, isFalse);
      expect(byId(models, 'gpt-3.5-turbo').supportsVision, isFalse);
      expect(byId(models, 'o1-mini').supportsVision, isFalse);
      expect(
        byId(models, 'ft:gpt-4o-mini-2024-07-18:acme::abc').supportsVision,
        isTrue,
      );
      expect(models.every((m) => m.vendor == 'OpenAI'), isTrue);
      expect(models.every((m) => m.provider == AiProvider.openai), isTrue);
    });

    test('the cache is per key and never stores the key', () async {
      final recording = RecordingClient(
        (_, _) async => jsonResponse(openAiList(['gpt-5-mini'])),
      );
      final catalog = catalogFor(recording);
      await catalog.listModels(AiProvider.openai, apiKey: openAiKey);
      await catalog.listModels(AiProvider.openai, apiKey: openAiKey);
      expect(recording.requests, hasLength(1));
      await catalog.listModels(AiProvider.openai, apiKey: 'sk-other-key-999');
      expect(recording.requests, hasLength(2));
      expect(store.values['openai'], isNot(contains(openAiKey)));
      expect(store.values['openai'], isNot(contains('sk-other-key-999')));
    });

    test('verifyApiKey: valid key primes the cache; invalid is auth', () async {
      final recording = openAiServer();
      final catalog = catalogFor(recording);
      await catalog.verifyApiKey(AiProvider.openai, openAiKey);
      expect(
        recording.requests.single.url.toString(),
        'https://api.openai.com/v1/models',
      );
      await catalog.listModels(AiProvider.openai, apiKey: openAiKey);
      expect(recording.requests, hasLength(1));

      await expectLater(
        catalog.verifyApiKey(AiProvider.openai, 'sk-bad'),
        throwsA(
          isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.auth),
        ),
      );
    });

    test('findModel and resolveProfile', () async {
      final recording = openAiServer();
      final catalog = catalogFor(recording);
      expect(
        (await catalog.findModel(
          AiProvider.openai,
          'gpt-4o',
          apiKey: openAiKey,
        ))?.supportsVision,
        isTrue,
      );
      expect(
        await catalog.findModel(
          AiProvider.openai,
          'gpt-9000',
          apiKey: openAiKey,
        ),
        isNull,
      );
      // Profiles for OpenAI need no network.
      final before = recording.requests.length;
      final profile = await catalog.resolveProfile(
        AiProvider.openai,
        'o3',
        apiKey: openAiKey,
      );
      expect(profile.reasoningEfforts, isNotEmpty);
      expect(recording.requests, hasLength(before));
    });
  });

  group('helpers', () {
    test('keyFingerprint is stable, short and key-dependent', () {
      final a = DefaultModelCatalog.keyFingerprint('sk-abc');
      expect(a, DefaultModelCatalog.keyFingerprint('sk-abc'));
      expect(a, isNot(DefaultModelCatalog.keyFingerprint('sk-abd')));
      expect(a, isNot(contains('sk-abc')));
      expect(a.length, lessThanOrEqualTo(14));
    });

    test('FileCatalogCacheStore round trip and failures', () async {
      final dir = await Directory.systemTemp.createTemp('catalog_cache');
      addTearDown(() => dir.delete(recursive: true));
      final fileStore = FileCatalogCacheStore(
        directoryProvider: () async => dir,
      );
      expect(await fileStore.read('opper'), isNull);
      await fileStore.write('opper', '{"a":1}');
      expect(await fileStore.read('opper'), '{"a":1}');

      final broken = FileCatalogCacheStore(
        directoryProvider: () async => throw UnsupportedError('no fs'),
      );
      expect(await broken.read('opper'), isNull);
      await broken.write('opper', 'x'); // does not throw
    });

    test('CatalogEntry JSON is compact and round-trips', () async {
      final entries = DefaultModelCatalog.parseOpperModels(
        jsonDecode(opperFixture),
      );
      for (final entry in entries) {
        final restored = CatalogEntry.fromJson(
          jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>,
        );
        expect(restored.info, entry.info);
        expect(
          restored.profile.reasoningEfforts,
          entry.profile.reasoningEfforts,
        );
        expect(
          restored.profile.acceptsTemperature,
          entry.profile.acceptsTemperature,
        );
      }
      expect(entries.first.toJson().containsValue(null), isFalse);
      expect(entries.first.toJson().containsKey('recommended'), isTrue);
      final search = entries.firstWhere(
        (e) => e.info.id == 'openai/gpt-5-search-api',
      );
      expect(search.toJson()['supportsVision'], isFalse);
      expect(search.toJson().containsKey('recommended'), isFalse);
    });

    test('unexpected list formats are invalidResponse', () {
      expect(
        () => DefaultModelCatalog.parseOpperModels({'nope': 1}),
        throwsA(isA<AiException>()),
      );
      expect(
        () => DefaultModelCatalog.parseOpenAiModels('x'),
        throwsA(isA<AiException>()),
      );
    });
  });
}
