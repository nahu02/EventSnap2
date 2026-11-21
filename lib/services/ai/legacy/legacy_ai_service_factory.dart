import 'dart:async';
import 'dart:io';

import 'package:dart_openai/dart_openai.dart';

import '../../../models/ai_model_info.dart';
import '../../../models/ai_provider.dart';
import '../../../models/extraction.dart';
import '../../../models/settings.dart';
import '../../openai_calendar_event_interpreter.dart';
import '../ai_cancellation_token.dart';
import '../ai_exceptions.dart';
import '../ai_service_factory.dart';
import '../calendar_event_interpreter.dart';
import '../model_catalog.dart';

/// Signature of the text extraction call wrapped by
/// [LegacyCalendarEventInterpreter] (injectable for tests).
typedef LegacyTextExtractor = Future<LegacyOpenAiExtraction> Function(
  Settings settings,
  String text,
);

/// TEMPORARY [AiServiceFactory] over the v2 OpenAI interpreter (text only,
/// OpenAI only, JSON mode). Workstream B replaces it with
/// `DefaultAiServiceFactory` and deletes `services/ai/legacy/`.
class LegacyAiServiceFactory implements AiServiceFactory {
  LegacyAiServiceFactory({ModelCatalog? modelCatalog, this.extractor})
    : modelCatalog = modelCatalog ?? LegacyModelCatalog();

  @override
  final ModelCatalog modelCatalog;

  /// Overrides the OpenAI call (tests).
  final LegacyTextExtractor? extractor;

  @override
  CalendarEventInterpreter createInterpreter(Settings settings) =>
      LegacyCalendarEventInterpreter(settings, extractor: extractor);
}

/// Adapts [OpenAiCalendarEventInterpreter] to [CalendarEventInterpreter].
class LegacyCalendarEventInterpreter implements CalendarEventInterpreter {
  LegacyCalendarEventInterpreter(
    this.settings, {
    LegacyTextExtractor? extractor,
  }) : _extractor = extractor ?? _defaultExtractor;

  final Settings settings;
  final LegacyTextExtractor _extractor;

  static Future<LegacyOpenAiExtraction> _defaultExtractor(
    Settings settings,
    String text,
  ) => OpenAiCalendarEventInterpreter(settings).extractEventsFromText(text);

  @override
  Future<ExtractionResult> extractEvents(
    ExtractionInput input, {
    AiCancellationToken? cancellationToken,
  }) async {
    try {
      cancellationToken?.throwIfCancelled();
      if (input.isEmpty) {
        throw const AiException(
          AiErrorKind.unsupportedInput,
          'Nothing to extract: the input is empty',
        );
      }
      if (input.hasImages) {
        throw const AiException(
          AiErrorKind.unsupportedInput,
          'Image input is not supported by the legacy interpreter yet',
        );
      }
      if (settings.provider != AiProvider.openai) {
        throw AiException(
          AiErrorKind.notConfigured,
          '${settings.provider.displayName} is not supported by the legacy '
          'interpreter yet; switch to OpenAI in Settings',
        );
      }
      if (!settings.isConfigured) {
        throw const AiException(
          AiErrorKind.notConfigured,
          'OpenAI API key or model is missing',
        );
      }

      final request = _extractor(settings, input.text);
      final LegacyOpenAiExtraction extraction;
      if (cancellationToken == null) {
        extraction = await request;
      } else {
        extraction = await Future.any([
          request,
          cancellationToken.whenCancelled.then<LegacyOpenAiExtraction>(
            (_) => throw const AiException(
              AiErrorKind.cancelled,
              'Request was cancelled',
            ),
          ),
        ]);
      }
      cancellationToken?.throwIfCancelled();

      return ExtractionResult(
        events: extraction.events,
        input: input,
        provider: settings.provider,
        model: settings.activeModel,
        usedStructuredOutput: false,
        warnings: extraction.warnings,
        rawResponse: extraction.rawResponse,
      );
    } on AiException {
      rethrow;
    } catch (e) {
      throw AiException(AiErrorKind.unknown, e.toString(), cause: e);
    }
  }
}

/// Minimal TEMPORARY [ModelCatalog]: OpenAI via `GET /v1/models` (no
/// capability data), Opper as a static list with the default model.
class LegacyModelCatalog implements ModelCatalog {
  final Map<String, List<AiModelInfo>> _cache = {};

  static const Set<String> _recommendedOpenAi = {
    'gpt-5-mini',
    'gpt-5',
    'gpt-4.1-mini',
  };

  static const List<String> _excludedOpenAiKeywords = [
    'audio',
    'realtime',
    'embedding',
    'tts',
    'whisper',
    'dall-e',
    'image',
    'transcribe',
    'moderation',
    'search',
    'computer-use',
    'instruct',
  ];

  static const List<AiModelInfo> _opperModels = [
    AiModelInfo(
      id: 'openai/gpt-5-mini',
      displayName: 'GPT-5 mini',
      provider: AiProvider.opper,
      vendor: 'OpenAI',
      supportsStructuredOutput: true,
      supportsVision: true,
      recommended: true,
    ),
  ];

  @override
  Future<List<AiModelInfo>> listModels(
    AiProvider provider, {
    required String apiKey,
    bool forceRefresh = false,
  }) async {
    switch (provider) {
      case AiProvider.opper:
        return _opperModels;
      case AiProvider.openai:
        final key = apiKey.trim();
        if (key.isEmpty) {
          throw const AiException(
            AiErrorKind.notConfigured,
            'An OpenAI API key is required to list models',
          );
        }
        final cached = _cache[key];
        if (!forceRefresh && cached != null) return cached;
        final models = await _listOpenAiModels(key);
        _cache[key] = models;
        return models;
    }
  }

  @override
  Future<AiModelInfo?> findModel(
    AiProvider provider,
    String modelId, {
    required String apiKey,
  }) async {
    final models = await listModels(provider, apiKey: apiKey);
    for (final model in models) {
      if (model.id == modelId) return model;
    }
    return null;
  }

  @override
  Future<void> verifyApiKey(AiProvider provider, String apiKey) async {
    if (apiKey.trim().isEmpty) {
      throw AiException(
        AiErrorKind.notConfigured,
        'No ${provider.displayName} API key entered',
      );
    }
    if (provider == AiProvider.openai) {
      await listModels(provider, apiKey: apiKey, forceRefresh: true);
    }
    // Opper keys cannot be verified by the legacy catalog.
  }

  Future<List<AiModelInfo>> _listOpenAiModels(String apiKey) async {
    try {
      OpenAI.apiKey = apiKey;
      final models = await OpenAI.instance.model.list().timeout(
        const Duration(seconds: 30),
      );
      final infos = models
          .map((m) => m.id)
          .where((id) {
            final lower = id.toLowerCase();
            final isChat =
                lower.startsWith('gpt-') || RegExp(r'^o\d').hasMatch(lower);
            return isChat &&
                !_excludedOpenAiKeywords.any((k) => lower.contains(k));
          })
          .map(
            (id) => AiModelInfo(
              id: id,
              provider: AiProvider.openai,
              vendor: 'OpenAI',
              recommended: _recommendedOpenAi.contains(id),
            ),
          )
          .toList();
      infos.sort((a, b) {
        if (a.recommended != b.recommended) return a.recommended ? -1 : 1;
        return a.id.compareTo(b.id);
      });
      return infos;
    } on RequestFailedException catch (e) {
      throw OpenAiCalendarEventInterpreter.mapRequestFailure(e);
    } on TimeoutException catch (e) {
      throw AiException(
        AiErrorKind.timeout,
        'Listing models timed out',
        cause: e,
      );
    } on SocketException catch (e) {
      throw AiException(AiErrorKind.network, e.message, cause: e);
    } catch (e) {
      throw AiException(AiErrorKind.unknown, e.toString(), cause: e);
    }
  }
}
