import '../../models/ai_provider.dart';

/// What the AI layer knows about one model: capabilities (tri-state, `null`
/// = unknown) and the request parameters it accepts.
class ModelProfile {
  const ModelProfile({
    required this.modelId,
    this.supportsStructuredOutput,
    this.supportsVision,
    this.reasoningEfforts = const [],
    this.acceptsTemperature = false,
    this.minTemperature,
    this.maxTemperature,
  });

  /// Profile for a model nothing is known about: try everything, send no
  /// optional parameters.
  const ModelProfile.unknown(this.modelId)
    : supportsStructuredOutput = null,
      supportsVision = null,
      reasoningEfforts = const [],
      acceptsTemperature = false,
      minTemperature = null,
      maxTemperature = null;

  final String modelId;
  final bool? supportsStructuredOutput;
  final bool? supportsVision;

  /// Accepted `reasoning_effort` values, lowest first. Empty: do not send
  /// `reasoning_effort`.
  final List<String> reasoningEfforts;

  /// Whether a non-default `temperature` is accepted.
  final bool acceptsTemperature;
  final double? minTemperature;
  final double? maxTemperature;

  /// The `reasoning_effort` to send: the first of [preference] the model
  /// accepts, otherwise its lowest effort other than `none`. `null` when the
  /// model takes no reasoning parameter.
  String? reasoningEffortFor(List<String> preference) {
    if (reasoningEfforts.isEmpty) return null;
    for (final effort in preference) {
      if (reasoningEfforts.contains(effort)) return effort;
    }
    return reasoningEfforts.firstWhere(
      (e) => e != 'none',
      orElse: () => reasoningEfforts.first,
    );
  }

  /// The `temperature` to send (clamped to the model's range), or `null` to
  /// omit it. Never sent together with a reasoning effort: several reasoning
  /// models reject a non-default temperature.
  double? temperatureFor(double desired, {required bool sendsReasoning}) {
    if (!acceptsTemperature || sendsReasoning) return null;
    var value = desired;
    if (minTemperature != null && value < minTemperature!) {
      value = minTemperature!;
    }
    if (maxTemperature != null && value > maxTemperature!) {
      value = maxTemperature!;
    }
    return value;
  }

  /// Compact JSON for the persisted catalogue cache.
  Map<String, dynamic> toJson() => {
    if (reasoningEfforts.isNotEmpty) 're': reasoningEfforts,
    if (acceptsTemperature) 't': [minTemperature, maxTemperature],
  };

  /// Reads the [toJson] keys from a cached catalogue entry.
  factory ModelProfile.fromCache(
    String modelId,
    Map<String, dynamic> json, {
    bool? supportsStructuredOutput,
    bool? supportsVision,
  }) {
    final efforts = json['re'];
    final temperature = json['t'];
    return ModelProfile(
      modelId: modelId,
      supportsStructuredOutput: supportsStructuredOutput,
      supportsVision: supportsVision,
      reasoningEfforts: efforts is List
          ? efforts.whereType<String>().toList(growable: false)
          : const [],
      acceptsTemperature: temperature is List,
      minTemperature: temperature is List && temperature.isNotEmpty
          ? (temperature[0] as num?)?.toDouble()
          : null,
      maxTemperature: temperature is List && temperature.length > 1
          ? (temperature[1] as num?)?.toDouble()
          : null,
    );
  }

  @override
  String toString() =>
      'ModelProfile($modelId, structured: $supportsStructuredOutput, '
      'vision: $supportsVision, reasoning: $reasoningEfforts, '
      'temperature: $acceptsTemperature)';
}

/// Id-based capability guesses (OpenAI's model list has no capability data).
/// See docs/v3_plan.md section 2.
class ModelHeuristics {
  ModelHeuristics._();

  static final RegExp _oSeries = RegExp(r'^o(\d+)');
  static final RegExp _gptMajor = RegExp(r'^gpt-(\d+)');

  /// Keywords of OpenAI models that are not usable for chat completions with
  /// text/image input (or only via other APIs).
  static const List<String> excludedOpenAiKeywords = [
    'embedding',
    'tts',
    'whisper',
    'dall-e',
    'image',
    'audio',
    'realtime',
    'transcribe',
    'moderation',
    'search',
    'computer-use',
    'instruct',
    'codex',
    'deep-research',
    'babbage',
    'davinci',
  ];

  /// Lower-cased base model id: strips an Opper route prefix
  /// (`openai/gpt-5-mini` → `gpt-5-mini`) and fine-tune decorations
  /// (`ft:gpt-4o-mini:org::id` → `gpt-4o-mini`).
  static String baseId(String id) {
    var base = id.trim().toLowerCase();
    final slash = base.lastIndexOf('/');
    if (slash >= 0) base = base.substring(slash + 1);
    if (base.startsWith('ft:')) {
      base = base.substring(3);
      final colon = base.indexOf(':');
      if (colon >= 0) base = base.substring(0, colon);
    }
    return base;
  }

  /// Whether [id] looks like an OpenAI model usable with Chat Completions.
  static bool isOpenAiChatModel(String id) {
    final base = baseId(id);
    final family =
        base.startsWith('gpt-') ||
        base.startsWith('chatgpt-') ||
        _oSeries.hasMatch(base);
    if (!family) return false;
    if (excludedOpenAiKeywords.any(base.contains)) return false;
    // `*-pro` models (o1-pro, o3-pro, gpt-5-pro, …) are Responses-API only.
    if (RegExp(r'-pro($|-)').hasMatch(base)) return false;
    return true;
  }

  static bool _isLegacyGpt4(String base) =>
      base == 'gpt-4' ||
      RegExp(r'^gpt-4-\d').hasMatch(base) ||
      base.startsWith('gpt-4-turbo') ||
      base.startsWith('gpt-4-vision');

  static int? _gptMajorVersion(String base) {
    final match = _gptMajor.firstMatch(base);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// `response_format: json_schema` (strict) support of an OpenAI model id.
  static bool? openAiStructuredOutput(String id) {
    final base = baseId(id);
    if (base.startsWith('gpt-3.5') ||
        _isLegacyGpt4(base) ||
        base.contains('instruct') ||
        base.contains('search') ||
        base.contains('audio') ||
        base.contains('realtime') ||
        base == 'gpt-4o-2024-05-13' ||
        base.startsWith('o1-mini') ||
        base.startsWith('o1-preview')) {
      return false;
    }
    if (base.startsWith('gpt-4o') ||
        base.startsWith('gpt-4.1') ||
        base.startsWith('gpt-4.5')) {
      return true;
    }
    final major = _gptMajorVersion(base);
    if (major != null && major >= 5) return true;
    if (_oSeries.hasMatch(base)) return true;
    return null;
  }

  /// Image input support of an OpenAI model id.
  static bool? openAiVision(String id) {
    final base = baseId(id);
    if (base.startsWith('gpt-3.5') ||
        base.contains('instruct') ||
        base.contains('codex') ||
        base.contains('search') ||
        base.contains('audio') ||
        base.contains('realtime') ||
        base.startsWith('o1-mini') ||
        base.startsWith('o1-preview') ||
        base.startsWith('o3-mini') ||
        base == 'gpt-4' ||
        RegExp(r'^gpt-4-\d').hasMatch(base) ||
        base.startsWith('gpt-4-turbo-preview')) {
      return false;
    }
    if (base.startsWith('gpt-4o') ||
        base.startsWith('gpt-4-turbo') ||
        base.startsWith('gpt-4-vision') ||
        base.startsWith('gpt-4.1') ||
        base.startsWith('gpt-4.5') ||
        base.startsWith('chatgpt-4o')) {
      return true;
    }
    final major = _gptMajorVersion(base);
    if (major != null && major >= 5) return true;
    if (base == 'o1' ||
        base.startsWith('o1-2') ||
        base.startsWith('o3') ||
        base.startsWith('o4')) {
      return true;
    }
    return null;
  }

  /// Reasoning models reject a non-default `temperature` and accept
  /// `reasoning_effort`.
  static bool isOpenAiReasoningModel(String id) {
    final base = baseId(id);
    if (base.contains('-chat')) return false;
    if (_oSeries.hasMatch(base)) return true;
    final major = _gptMajorVersion(base);
    return major != null && major >= 5;
  }

  /// Request profile for an OpenAI model id.
  static ModelProfile openAiProfile(String id) {
    final base = baseId(id);
    final reasoning = isOpenAiReasoningModel(id);
    List<String> efforts = const [];
    if (reasoning && !RegExp(r'-pro($|-)').hasMatch(base)) {
      // The original GPT-5 family also accepts `minimal`; everything newer
      // and the o-series accept low/medium/high.
      efforts =
          RegExp(r'^gpt-5(-mini|-nano)?(-\d{4}-\d{2}-\d{2})?$').hasMatch(base)
          ? const ['minimal', 'low', 'medium', 'high']
          : const ['low', 'medium', 'high'];
    }
    final knownTemperatureFamily =
        base.startsWith('gpt-4') ||
        base.startsWith('gpt-3.5') ||
        base.startsWith('chatgpt-');
    return ModelProfile(
      modelId: id,
      supportsStructuredOutput: openAiStructuredOutput(id),
      supportsVision: openAiVision(id),
      reasoningEfforts: efforts,
      acceptsTemperature: !reasoning && knownTemperatureFamily,
      minTemperature: 0,
      maxTemperature: 2,
    );
  }

  /// Best guess without catalogue data. Opper ids routed to OpenAI
  /// (`openai/gpt-5-mini`) use the OpenAI heuristics; others are unknown.
  static ModelProfile guessProfile(AiProvider provider, String modelId) {
    switch (provider) {
      case AiProvider.openai:
        return openAiProfile(modelId);
      case AiProvider.opper:
        final route = modelId.contains('/')
            ? modelId.substring(0, modelId.indexOf('/')).toLowerCase()
            : '';
        if (route.startsWith('openai') || route.startsWith('azure')) {
          final base = baseId(modelId);
          if (base.startsWith('gpt-') || _oSeries.hasMatch(base)) {
            final guess = openAiProfile(modelId);
            // Request quirks behind Opper are unknown: send nothing optional.
            return ModelProfile(
              modelId: modelId,
              supportsStructuredOutput: guess.supportsStructuredOutput,
              supportsVision: guess.supportsVision,
            );
          }
        }
        return ModelProfile.unknown(modelId);
    }
  }
}
