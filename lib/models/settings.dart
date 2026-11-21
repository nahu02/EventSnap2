import 'ai_provider.dart';

/// App theme preference.
enum AppThemeMode { system, light, dark }

/// Whether to request `response_format: json_schema` from capable models.
enum StructuredOutputMode { auto, off }

/// Immutable application settings (storage format v2).
///
/// API keys are kept for both providers; only the [provider]'s key and model
/// are used for requests ([activeApiKey], [activeModel]).
class Settings {
  static const int minRetries = 0;
  static const int maxRetriesLimit = 10;
  static const int minTimeoutSeconds = 5;
  static const int maxTimeoutSeconds = 300;

  static const int defaultMaxRetries = 2;
  static const int defaultTimeoutSeconds = 60;

  final AiProvider provider;
  final String openAiApiKey;
  final String opperApiKey;
  final String openAiModel;
  final String opperModel;

  /// Retries for transient failures, `0..10`.
  final int maxRetries;

  /// Request timeout, `5..300` seconds.
  final int timeoutSeconds;

  final AppThemeMode themeMode;

  /// Start extraction automatically when content is shared into the app.
  final bool autoProcessShared;

  final StructuredOutputMode structuredOutputMode;

  /// Shows the raw AI response on the review screen.
  final bool debugMode;

  const Settings({
    this.provider = AiProvider.openai,
    this.openAiApiKey = '',
    this.opperApiKey = '',
    // Literals must match AiProvider.<p>.defaultModel (asserted in tests);
    // enum members cannot be read in a const default value.
    this.openAiModel = 'gpt-5-mini',
    this.opperModel = 'openai/gpt-5-mini',
    this.maxRetries = defaultMaxRetries,
    this.timeoutSeconds = defaultTimeoutSeconds,
    this.themeMode = AppThemeMode.system,
    this.autoProcessShared = true,
    this.structuredOutputMode = StructuredOutputMode.auto,
    this.debugMode = false,
  });

  /// Default settings (no API keys).
  factory Settings.defaults() => const Settings();

  /// API key stored for [p] (may be empty).
  String apiKeyFor(AiProvider p) => switch (p) {
    AiProvider.openai => openAiApiKey,
    AiProvider.opper => opperApiKey,
  };

  /// Model id stored for [p] (may be empty).
  String modelFor(AiProvider p) => switch (p) {
    AiProvider.openai => openAiModel,
    AiProvider.opper => opperModel,
  };

  String get activeApiKey => apiKeyFor(provider);
  String get activeModel => modelFor(provider);

  /// True when the active provider has a non-blank key and model.
  bool get isConfigured =>
      activeApiKey.trim().isNotEmpty && activeModel.trim().isNotEmpty;

  /// Blocking problems: missing key/model of the **active** provider and
  /// out-of-range numeric values. Empty when the settings are usable.
  List<String> validate() {
    final errors = <String>[];
    if (activeApiKey.trim().isEmpty) {
      errors.add('${provider.displayName} API key is required');
    }
    if (activeModel.trim().isEmpty) {
      errors.add('${provider.displayName} model is required');
    }
    errors.addAll(validateRanges());
    return errors;
  }

  /// Only the numeric range checks of [validate] (what persistence enforces).
  List<String> validateRanges() {
    final errors = <String>[];
    if (maxRetries < minRetries || maxRetries > maxRetriesLimit) {
      errors.add(
        'Max retries must be between $minRetries and $maxRetriesLimit',
      );
    }
    if (timeoutSeconds < minTimeoutSeconds ||
        timeoutSeconds > maxTimeoutSeconds) {
      errors.add(
        'Timeout must be between $minTimeoutSeconds and $maxTimeoutSeconds seconds',
      );
    }
    return errors;
  }

  /// Non-blocking hints, e.g. an OpenAI key that does not start with `sk-`.
  List<String> warnings() {
    final warnings = <String>[];
    final openAiKey = openAiApiKey.trim();
    if (openAiKey.isNotEmpty && !openAiKey.startsWith('sk-')) {
      warnings.add('OpenAI API keys usually start with "sk-"');
    }
    for (final p in AiProvider.values) {
      final key = apiKeyFor(p);
      if (key.isNotEmpty && key.trim() != key) {
        warnings.add(
          '${p.displayName} API key has leading or trailing whitespace',
        );
      }
    }
    return warnings;
  }

  Duration get timeoutDuration => Duration(seconds: timeoutSeconds);

  /// The key for [p] masked for display, e.g. `sk-*********abcd`.
  String maskedKeyFor(AiProvider p) {
    final key = apiKeyFor(p);
    if (key.length <= 8) {
      return '*' * key.length;
    }
    final prefix = key.substring(0, 3);
    final suffix = key.substring(key.length - 4);
    // Fixed number of asterisks so the length of the key is not revealed.
    const masked = '*********';
    return '$prefix$masked$suffix';
  }

  Settings copyWith({
    AiProvider? provider,
    String? openAiApiKey,
    String? opperApiKey,
    String? openAiModel,
    String? opperModel,
    int? maxRetries,
    int? timeoutSeconds,
    AppThemeMode? themeMode,
    bool? autoProcessShared,
    StructuredOutputMode? structuredOutputMode,
    bool? debugMode,
  }) {
    return Settings(
      provider: provider ?? this.provider,
      openAiApiKey: openAiApiKey ?? this.openAiApiKey,
      opperApiKey: opperApiKey ?? this.opperApiKey,
      openAiModel: openAiModel ?? this.openAiModel,
      opperModel: opperModel ?? this.opperModel,
      maxRetries: maxRetries ?? this.maxRetries,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      themeMode: themeMode ?? this.themeMode,
      autoProcessShared: autoProcessShared ?? this.autoProcessShared,
      structuredOutputMode: structuredOutputMode ?? this.structuredOutputMode,
      debugMode: debugMode ?? this.debugMode,
    );
  }

  /// Returns a copy with the API key for [p] replaced.
  Settings copyWithApiKey(AiProvider p, String apiKey) => switch (p) {
    AiProvider.openai => copyWith(openAiApiKey: apiKey),
    AiProvider.opper => copyWith(opperApiKey: apiKey),
  };

  /// Returns a copy with the model for [p] replaced.
  Settings copyWithModel(AiProvider p, String model) => switch (p) {
    AiProvider.openai => copyWith(openAiModel: model),
    AiProvider.opper => copyWith(opperModel: model),
  };

  Map<String, dynamic> toJson() => {
    'provider': provider.id,
    'openAiApiKey': openAiApiKey,
    'opperApiKey': opperApiKey,
    'openAiModel': openAiModel,
    'opperModel': opperModel,
    'maxRetries': maxRetries,
    'timeoutSeconds': timeoutSeconds,
    'themeMode': themeMode.name,
    'autoProcessShared': autoProcessShared,
    'structuredOutputMode': structuredOutputMode.name,
    'debugMode': debugMode,
  };

  /// Lenient: missing or malformed values fall back to the defaults.
  factory Settings.fromJson(Map<String, dynamic> json) {
    const d = Settings();
    return Settings(
      provider: AiProvider.fromId(_string(json['provider'])),
      openAiApiKey: _string(json['openAiApiKey']) ?? d.openAiApiKey,
      opperApiKey: _string(json['opperApiKey']) ?? d.opperApiKey,
      openAiModel: _string(json['openAiModel']) ?? d.openAiModel,
      opperModel: _string(json['opperModel']) ?? d.opperModel,
      maxRetries: _int(json['maxRetries']) ?? d.maxRetries,
      timeoutSeconds: _int(json['timeoutSeconds']) ?? d.timeoutSeconds,
      themeMode: themeModeFromName(_string(json['themeMode'])),
      autoProcessShared:
          _bool(json['autoProcessShared']) ?? d.autoProcessShared,
      structuredOutputMode: structuredOutputModeFromName(
        _string(json['structuredOutputMode']),
      ),
      debugMode: _bool(json['debugMode']) ?? d.debugMode,
    );
  }

  /// Parses an [AppThemeMode] name; unknown → [AppThemeMode.system].
  static AppThemeMode themeModeFromName(String? name) {
    for (final mode in AppThemeMode.values) {
      if (mode.name == name) return mode;
    }
    return AppThemeMode.system;
  }

  /// Parses a [StructuredOutputMode] name; unknown → [StructuredOutputMode.auto].
  static StructuredOutputMode structuredOutputModeFromName(String? name) {
    for (final mode in StructuredOutputMode.values) {
      if (mode.name == name) return mode;
    }
    return StructuredOutputMode.auto;
  }

  static String? _string(Object? value) => value is String ? value : null;
  static int? _int(Object? value) => value is num ? value.toInt() : null;
  static bool? _bool(Object? value) => value is bool ? value : null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Settings &&
        other.provider == provider &&
        other.openAiApiKey == openAiApiKey &&
        other.opperApiKey == opperApiKey &&
        other.openAiModel == openAiModel &&
        other.opperModel == opperModel &&
        other.maxRetries == maxRetries &&
        other.timeoutSeconds == timeoutSeconds &&
        other.themeMode == themeMode &&
        other.autoProcessShared == autoProcessShared &&
        other.structuredOutputMode == structuredOutputMode &&
        other.debugMode == debugMode;
  }

  @override
  int get hashCode => Object.hash(
    provider,
    openAiApiKey,
    opperApiKey,
    openAiModel,
    opperModel,
    maxRetries,
    timeoutSeconds,
    themeMode,
    autoProcessShared,
    structuredOutputMode,
    debugMode,
  );

  /// Never includes API keys.
  @override
  String toString() {
    return 'Settings(provider: ${provider.id}, openAiModel: $openAiModel, '
        'opperModel: $opperModel, maxRetries: $maxRetries, '
        'timeoutSeconds: $timeoutSeconds, themeMode: ${themeMode.name}, '
        'autoProcessShared: $autoProcessShared, '
        'structuredOutputMode: ${structuredOutputMode.name}, '
        'debugMode: $debugMode, '
        'hasOpenAiKey: ${openAiApiKey.isNotEmpty}, '
        'hasOpperKey: ${opperApiKey.isNotEmpty})';
  }
}
