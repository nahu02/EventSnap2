import '../../models/ai_model_info.dart';
import '../../models/ai_provider.dart';

/// User-facing labels for providers and model metadata.
abstract final class ModelLabels {
  /// One-line description of what [provider] offers.
  static String providerDescription(AiProvider provider) => switch (provider) {
    AiProvider.openai => 'Use GPT models directly with an OpenAI key.',
    AiProvider.opper =>
      'One key, hundreds of models from many vendors, EU-hosted.',
  };

  /// Opper speed class (`very_fast|fast|medium|slow`) as a label.
  static String? speed(String? speed) => switch (speed) {
    null || '' => null,
    'very_fast' => 'Very fast',
    'fast' => 'Fast',
    'medium' => 'Medium speed',
    'slow' => 'Slow',
    _ => _humanize(speed),
  };

  /// Opper quality class (`good|great|high|best`) as a label.
  static String? quality(String? quality) => switch (quality) {
    null || '' => null,
    _ => '${_humanize(quality)} quality',
  };

  /// Secondary line for a model row: the id (when the display name differs),
  /// vendor, speed and quality, joined with ` · `.
  static String details(AiModelInfo model) {
    final vendor = model.vendor?.trim();
    return [
      if (model.displayName != model.id) model.id,
      if (vendor != null && vendor.isNotEmpty) vendor,
      ?speed(model.speed),
      ?quality(model.quality),
    ].join(' · ');
  }

  static String _humanize(String value) {
    final words = value.replaceAll('_', ' ').trim();
    if (words.isEmpty) return words;
    return words[0].toUpperCase() + words.substring(1);
  }
}
