import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/ai_provider.dart';
import '../../models/extraction.dart';
import '../../models/settings.dart';
import 'ai_cancellation_token.dart';
import 'ai_exceptions.dart';
import 'calendar_event_interpreter.dart';
import 'default_model_catalog.dart';
import 'extraction_prompt.dart';
import 'extraction_response_parser.dart';
import 'extraction_schema.dart';
import 'model_profile.dart';
import 'openai_compatible_client.dart';
import 'provider_config.dart';

/// Reads the bytes of a local image file (injectable for tests).
typedef ImageBytesReader = Future<List<int>> Function(String path);

Future<List<int>> _readFile(String path) => File(path).readAsBytes();

/// How the response format is requested, from most to least reliable.
enum StructuredOutputLevel {
  /// `response_format: {type: json_schema, strict: true}`.
  jsonSchema,

  /// `response_format: {type: json_object}`, schema in the prompt.
  jsonObject,

  /// No `response_format`; schema in the prompt only.
  promptOnly,
}

/// Per-model request adjustments learned during this app session (shared by
/// all interpreters a factory creates): downgraded structured output level
/// and request parameters the model rejected.
class AiSessionState {
  final Map<String, StructuredOutputLevel> _levels = {};
  final Map<String, Set<String>> _droppedParams = {};

  static String _key(AiProvider provider, String model) =>
      '${provider.id}|$model';

  /// The remembered (downgraded) level, if any.
  StructuredOutputLevel? levelFor(AiProvider provider, String model) =>
      _levels[_key(provider, model)];

  void rememberLevel(
    AiProvider provider,
    String model,
    StructuredOutputLevel level,
  ) {
    final key = _key(provider, model);
    final current = _levels[key];
    if (current == null || level.index > current.index) _levels[key] = level;
  }

  /// Request parameters the model rejected (e.g. `temperature`).
  Set<String> droppedParams(AiProvider provider, String model) =>
      Set.unmodifiable(_droppedParams[_key(provider, model)] ?? const {});

  void dropParam(AiProvider provider, String model, String param) =>
      (_droppedParams[_key(provider, model)] ??= {}).add(param);
}

/// [CalendarEventInterpreter] over an OpenAI-compatible Chat Completions API
/// (OpenAI, Opper).
///
/// Structured output ladder: (1) strict `json_schema` when
/// `Settings.structuredOutputMode == auto` and the model supports it (or
/// support is unknown); (2) on a 400 about the response format, JSON mode with
/// the schema in the prompt; (3) on a further 400, prompt only. Downgrades and
/// rejected parameters (`reasoning_effort`, `temperature`) are remembered per
/// model in [AiSessionState].
class OpenAiCompatibleInterpreter implements CalendarEventInterpreter {
  OpenAiCompatibleInterpreter({
    required this.settings,
    required this._client,
    this._profileResolver,
    AiSessionState? sessionState,
    DateTime Function()? clock,
    ImageBytesReader? imageReader,
    this.reasoningEffortPreference = defaultReasoningEffortPreference,
    this.temperature = 0.2,
    this.maxImagePayloadBytes = defaultMaxImagePayloadBytes,
  }) : _sessionState = sessionState ?? AiSessionState(),
       _clock = clock ?? DateTime.now,
       _imageReader = imageReader ?? _readFile;

  /// Fast but still careful: `low` where supported.
  static const List<String> defaultReasoningEffortPreference = [
    'low',
    'minimal',
    'none',
  ];

  /// Limit for all base64-encoded images of one request.
  static const int defaultMaxImagePayloadBytes = 8 * 1024 * 1024;

  /// Maximum attempts through the downgrade/parameter ladder.
  static const int _maxLadderSteps = 5;

  final Settings settings;
  final OpenAiCompatibleClient _client;
  final ModelProfileResolver? _profileResolver;
  final AiSessionState _sessionState;
  final DateTime Function() _clock;
  final ImageBytesReader _imageReader;

  /// `reasoning_effort` values in order of preference.
  final List<String> reasoningEffortPreference;

  /// Sent to models that accept a temperature and get no reasoning effort.
  final double temperature;

  final int maxImagePayloadBytes;

  AiProvider get _provider => settings.provider;
  String get _model => settings.activeModel.trim();

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
      if (!settings.isConfigured) {
        throw AiException(
          AiErrorKind.notConfigured,
          '${_provider.displayName} API key or model is missing',
        );
      }

      final profile = await _race(_resolveProfile(), cancellationToken);
      if (input.hasImages && profile.supportsVision == false) {
        throw AiException(
          AiErrorKind.unsupportedInput,
          'Model $_model does not accept images',
        );
      }
      final imageParts = input.hasImages
          ? await _race(_imageParts(input.images), cancellationToken)
          : const <Map<String, dynamic>>[];

      final now = _clock();
      var level = _initialLevel(profile);
      final dropped = {..._sessionState.droppedParams(_provider, _model)};
      final url = ProviderConfig.of(_provider).chatCompletionsUrl;

      late ChatCompletion completion;
      for (var step = 0; ; step++) {
        final body = buildRequestBody(
          input: input,
          imageParts: imageParts,
          level: level,
          profile: profile,
          droppedParams: dropped,
          now: now,
        );
        try {
          completion = await _client.createChatCompletion(
            url: url,
            apiKey: settings.activeApiKey.trim(),
            body: body,
            cancellationToken: cancellationToken,
          );
          break;
        } on AiException catch (e) {
          if (step + 1 >= _maxLadderSteps ||
              (e.statusCode != 400 && e.statusCode != 422)) {
            rethrow;
          }
          final message = e.message.toLowerCase();
          if (body.containsKey('response_format') &&
              isResponseFormatError(message)) {
            level = StructuredOutputLevel.values[level.index + 1];
            _sessionState.rememberLevel(_provider, _model, level);
            continue;
          }
          final param = rejectedParam(message, body);
          if (param != null) {
            dropped.add(param);
            _sessionState.dropParam(_provider, _model, param);
            continue;
          }
          rethrow;
        }
      }
      cancellationToken?.throwIfCancelled();

      final content = completion.content;
      if (content == null || content.trim().isEmpty) {
        if (completion.refusal != null) {
          throw AiException(
            AiErrorKind.invalidResponse,
            'The model refused: ${completion.refusal}',
          );
        }
        throw AiException(
          AiErrorKind.invalidResponse,
          completion.finishReason == 'length'
              ? 'The response was cut off before any content'
              : 'The model returned an empty response',
        );
      }

      final parsed = ExtractionResponseParser(
        referenceOffset: now.timeZoneOffset,
      ).parse(content);
      final warnings = <String>[
        if (settings.structuredOutputMode == StructuredOutputMode.auto)
          ?_downgradeWarning(level),
        ...parsed.warnings,
      ];
      return ExtractionResult(
        events: parsed.events,
        input: input,
        provider: _provider,
        model: _model,
        usedStructuredOutput: level == StructuredOutputLevel.jsonSchema,
        warnings: warnings,
        rawResponse: content,
      );
    } on AiException {
      rethrow;
    } catch (e) {
      throw AiException(AiErrorKind.unknown, e.toString(), cause: e);
    }
  }

  /// The Chat Completions request body (public for tests).
  Map<String, dynamic> buildRequestBody({
    required ExtractionInput input,
    required List<Map<String, dynamic>> imageParts,
    required StructuredOutputLevel level,
    required ModelProfile profile,
    required Set<String> droppedParams,
    required DateTime now,
  }) {
    final userText = ExtractionPrompt.user(input);
    final effort = droppedParams.contains('reasoning_effort')
        ? null
        : profile.reasoningEffortFor(reasoningEffortPreference);
    final temperature = droppedParams.contains('temperature')
        ? null
        : profile.temperatureFor(
            this.temperature,
            sendsReasoning: effort != null,
          );
    return {
      'model': _model,
      'messages': [
        {
          'role': 'system',
          'content': ExtractionPrompt.system(
            now: now,
            includeSchema: level != StructuredOutputLevel.jsonSchema,
          ),
        },
        {
          'role': 'user',
          'content': imageParts.isEmpty
              ? userText
              : [
                  {'type': 'text', 'text': userText},
                  ...imageParts,
                ],
        },
      ],
      if (level == StructuredOutputLevel.jsonSchema)
        'response_format': ExtractionSchema.jsonSchemaResponseFormat,
      if (level == StructuredOutputLevel.jsonObject)
        'response_format': ExtractionSchema.jsonObjectResponseFormat,
      'reasoning_effort': ?effort,
      'temperature': ?temperature,
    };
  }

  /// Whether a 400 [lowerMessage] complains about `response_format`.
  static bool isResponseFormatError(String lowerMessage) => const [
    'response_format',
    'json_schema',
    'json schema',
    'json_object',
    'json mode',
    'structured output',
    'structured_output',
    'strict',
    'schema',
  ].any(lowerMessage.contains);

  /// The optional parameter a 400 [lowerMessage] rejects, if it is one we
  /// sent in [body].
  static String? rejectedParam(String lowerMessage, Map<String, dynamic> body) {
    if (body.containsKey('reasoning_effort') &&
        lowerMessage.contains('reasoning')) {
      return 'reasoning_effort';
    }
    if (body.containsKey('temperature') &&
        lowerMessage.contains('temperature')) {
      return 'temperature';
    }
    return null;
  }

  StructuredOutputLevel _initialLevel(ModelProfile profile) {
    final base =
        settings.structuredOutputMode == StructuredOutputMode.off ||
            profile.supportsStructuredOutput == false
        ? StructuredOutputLevel.jsonObject
        : StructuredOutputLevel.jsonSchema;
    final remembered = _sessionState.levelFor(_provider, _model);
    return remembered != null && remembered.index > base.index
        ? remembered
        : base;
  }

  static String? _downgradeWarning(StructuredOutputLevel level) =>
      switch (level) {
        StructuredOutputLevel.jsonSchema => null,
        StructuredOutputLevel.jsonObject =>
          "This model doesn't support structured output, so JSON mode was "
              'used. Check the results carefully.',
        StructuredOutputLevel.promptOnly =>
          "This model doesn't support structured output or JSON mode, so the "
              'results may be less reliable.',
      };

  Future<ModelProfile> _resolveProfile() async {
    final resolver = _profileResolver;
    if (resolver != null) {
      try {
        return await resolver.resolveProfile(
          _provider,
          _model,
          apiKey: settings.activeApiKey,
        );
      } catch (_) {
        // Fall back to heuristics.
      }
    }
    return ModelHeuristics.guessProfile(_provider, _model);
  }

  Future<List<Map<String, dynamic>>> _imageParts(
    List<InputImage> images,
  ) async {
    final parts = <Map<String, dynamic>>[];
    var total = 0;
    for (final image in images) {
      final List<int> bytes;
      try {
        bytes = await _imageReader(image.path);
      } catch (e) {
        throw AiException(
          AiErrorKind.unsupportedInput,
          'Could not read the image ${image.path}',
          cause: e,
        );
      }
      if (bytes.isEmpty) {
        throw AiException(
          AiErrorKind.unsupportedInput,
          'The image ${image.path} is empty',
        );
      }
      total += (bytes.length + 2) ~/ 3 * 4;
      if (total > maxImagePayloadBytes) {
        throw AiException(
          AiErrorKind.unsupportedInput,
          'The images are too large to send '
          '(limit ${(maxImagePayloadBytes / (1024 * 1024)).toStringAsFixed(0)} '
          'MB). Use fewer or smaller images.',
        );
      }
      final mimeType = image.mimeType.startsWith('image/')
          ? image.mimeType
          : 'image/jpeg';
      parts.add({
        'type': 'image_url',
        'image_url': {'url': 'data:$mimeType;base64,${base64Encode(bytes)}'},
      });
    }
    return parts;
  }

  static Future<T> _race<T>(Future<T> future, AiCancellationToken? token) {
    if (token == null) return future;
    return Future.any([
      future,
      token.whenCancelled.then<T>(
        (_) => throw const AiException(
          AiErrorKind.cancelled,
          'Request was cancelled',
        ),
      ),
    ]);
  }
}
