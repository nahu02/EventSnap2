import 'extraction.dart';

/// Why a "Snap screen" shortcut produced no screenshot.
enum SnapError {
  /// The accessibility service is not enabled (or has no screenshot rights).
  serviceDisabled,

  /// Android older than 11 (API 30): no screenshot API for accessibility.
  unsupported,

  /// The screen is protected (FLAG_SECURE) or the capture came back blank.
  secure,

  /// Anything else (rate limit, internal error, I/O).
  failed;

  /// Parses the platform channel code; unknown/absent codes → [failed].
  static SnapError fromCode(Object? code) {
    for (final e in values) {
      if (e.name == code) return e;
    }
    return failed;
  }
}

/// Content shared into the app from another app (Android share sheet).
class SharedContent {
  final String? text;
  final List<InputImage> images;

  /// Number of offered images that could not be read natively.
  final int failedImageCount;

  /// True when this comes from a "Snap screen" / "Snap & crop" shortcut (the
  /// [images] are then ephemeral screenshots) rather than the share sheet.
  final bool isSnap;

  /// Snap only: the user asked to crop the screenshot before use.
  final bool crop;

  /// Snap only: set when no screenshot could be taken ([images] is empty).
  final SnapError? snapError;

  const SharedContent({
    this.text,
    this.images = const [],
    this.failedImageCount = 0,
    this.isSnap = false,
    this.crop = false,
    this.snapError,
  });

  /// True when there is nothing to put in the composer (a share with only
  /// failed images is "empty" here but still worth reporting).

  bool get isEmpty => (text == null || text!.trim().isEmpty) && images.isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SharedContent ||
        other.text != text ||
        other.failedImageCount != failedImageCount ||
        other.isSnap != isSnap ||
        other.crop != crop ||
        other.snapError != snapError ||
        other.images.length != images.length) {
      return false;
    }
    for (var i = 0; i < images.length; i++) {
      if (other.images[i] != images[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    text,
    failedImageCount,
    isSnap,
    crop,
    snapError,
    Object.hashAll(images),
  );

  @override
  String toString() =>
      'SharedContent(text: ${text?.length ?? 0} chars, images: ${images.length}, '
      'failed: $failedImageCount${isSnap ? ', snap${crop ? '+crop' : ''}' : ''}'
      '${snapError != null ? ', error: ${snapError!.name}' : ''})';
}
