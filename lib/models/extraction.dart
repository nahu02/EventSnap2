import 'ai_provider.dart';
import 'event_model.dart';

/// A local image file used as AI input, already downscaled
/// (≤ ~2048 px long edge).
class InputImage {
  /// Absolute path of the local file.
  final String path;

  /// MIME type, e.g. `image/jpeg`.
  final String mimeType;

  /// True for screen snaps: private files in `cacheDir/snaps/` that the app
  /// deletes as soon as they are no longer needed (see `SnapFileStore`).
  /// Gallery picks and shared images are never ephemeral.
  final bool isEphemeral;

  const InputImage({
    required this.path,
    this.mimeType = 'image/jpeg',
    this.isEphemeral = false,
  });

  /// Parses `{path, mimeType, ephemeral?}` (the platform channel / storage
  /// format).
  factory InputImage.fromJson(Map<String, dynamic> json) => InputImage(
    path: json['path'] as String,
    mimeType: (json['mimeType'] as String?) ?? 'image/jpeg',
    isEphemeral: json['ephemeral'] == true,
  );

  Map<String, dynamic> toJson() => {
    'path': path,
    'mimeType': mimeType,
    if (isEphemeral) 'ephemeral': true,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InputImage &&
          other.path == path &&
          other.mimeType == mimeType &&
          other.isEphemeral == isEphemeral;

  @override
  int get hashCode => Object.hash(path, mimeType, isEphemeral);

  @override
  String toString() =>
      'InputImage(path: $path, mimeType: $mimeType'
      '${isEphemeral ? ', ephemeral' : ''})';
}

/// What the user asked the AI to extract events from.
class ExtractionInput {
  final String text;
  final List<InputImage> images;

  const ExtractionInput({this.text = '', this.images = const []});

  bool get hasText => text.trim().isNotEmpty;
  bool get hasImages => images.isNotEmpty;
  bool get isEmpty => !hasText && !hasImages;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExtractionInput &&
        other.text == text &&
        _listEquals(other.images, images);
  }

  @override
  int get hashCode => Object.hash(text, Object.hashAll(images));

  @override
  String toString() =>
      'ExtractionInput(text: ${text.length} chars, images: ${images.length})';
}

/// Result of one extraction run.
class ExtractionResult {
  /// Extracted events; may be empty.
  final List<EventModel> events;

  /// The original input, for the source/context panel.
  final ExtractionInput input;

  final AiProvider provider;
  final String model;

  /// Whether `response_format: json_schema` was used for this result.
  final bool usedStructuredOutput;

  /// User-presentable notes (e.g. "Model lacks structured output; used JSON
  /// mode").
  final List<String> warnings;

  /// Raw model content, shown only in debug mode.
  final String? rawResponse;

  const ExtractionResult({
    required this.events,
    required this.input,
    required this.provider,
    required this.model,
    this.usedStructuredOutput = false,
    this.warnings = const [],
    this.rawResponse,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExtractionResult &&
        _listEquals(other.events, events) &&
        other.input == input &&
        other.provider == provider &&
        other.model == model &&
        other.usedStructuredOutput == usedStructuredOutput &&
        _listEquals(other.warnings, warnings) &&
        other.rawResponse == rawResponse;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(events),
    input,
    provider,
    model,
    usedStructuredOutput,
    Object.hashAll(warnings),
    rawResponse,
  );

  @override
  String toString() =>
      'ExtractionResult(events: ${events.length}, provider: ${provider.id}, '
      'model: $model, structured: $usedStructuredOutput, '
      'warnings: ${warnings.length})';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
