import 'ai_provider.dart';

/// Metadata about a model offered by an [AiProvider].
///
/// Capability flags are tri-state: `true`/`false` when known, `null` when the
/// provider does not report them and no heuristic applies.
class AiModelInfo {
  /// Exact id to send in API requests (e.g. `gpt-5-mini`, `openai/gpt-5-mini`).
  final String id;

  /// Name shown in the UI. Falls back to [id].
  final String displayName;

  final AiProvider provider;

  /// Whether `response_format: json_schema` is supported. `null` = unknown.
  final bool? supportsStructuredOutput;

  /// Whether image inputs are supported. `null` = unknown.
  final bool? supportsVision;

  final String? description;

  /// Model maker, e.g. `OpenAI`, `Anthropic`.
  final String? vendor;

  /// Opper speed class: `very_fast` | `fast` | `medium` | `slow`.
  final String? speed;

  /// Opper quality class: `good` | `great` | `high` | `best`.
  final String? quality;

  final int? contextWindow;

  /// Curated / featured model, shown first in pickers.
  final bool recommended;

  const AiModelInfo({
    required this.id,
    String? displayName,
    required this.provider,
    this.supportsStructuredOutput,
    this.supportsVision,
    this.description,
    this.vendor,
    this.speed,
    this.quality,
    this.contextWindow,
    this.recommended = false,
  }) : displayName = displayName ?? id;

  /// Deserializes the format written by [toJson] (used for caching).
  factory AiModelInfo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final displayName = json['displayName'] as String?;
    return AiModelInfo(
      id: id,
      displayName: (displayName == null || displayName.trim().isEmpty)
          ? id
          : displayName,
      provider: AiProvider.fromId(json['provider'] as String?),
      supportsStructuredOutput: json['supportsStructuredOutput'] as bool?,
      supportsVision: json['supportsVision'] as bool?,
      description: json['description'] as String?,
      vendor: json['vendor'] as String?,
      speed: json['speed'] as String?,
      quality: json['quality'] as String?,
      contextWindow: (json['contextWindow'] as num?)?.toInt(),
      recommended: json['recommended'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'provider': provider.id,
    'supportsStructuredOutput': supportsStructuredOutput,
    'supportsVision': supportsVision,
    'description': description,
    'vendor': vendor,
    'speed': speed,
    'quality': quality,
    'contextWindow': contextWindow,
    'recommended': recommended,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AiModelInfo &&
        other.id == id &&
        other.displayName == displayName &&
        other.provider == provider &&
        other.supportsStructuredOutput == supportsStructuredOutput &&
        other.supportsVision == supportsVision &&
        other.description == description &&
        other.vendor == vendor &&
        other.speed == speed &&
        other.quality == quality &&
        other.contextWindow == contextWindow &&
        other.recommended == recommended;
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    provider,
    supportsStructuredOutput,
    supportsVision,
    description,
    vendor,
    speed,
    quality,
    contextWindow,
    recommended,
  );

  @override
  String toString() =>
      'AiModelInfo(id: $id, provider: ${provider.id}, '
      'structuredOutput: $supportsStructuredOutput, vision: $supportsVision, '
      'recommended: $recommended)';
}
