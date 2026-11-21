import 'extraction.dart';

/// Content shared into the app from another app (Android share sheet).
class SharedContent {
  final String? text;
  final List<InputImage> images;

  const SharedContent({this.text, this.images = const []});

  bool get isEmpty => (text == null || text!.trim().isEmpty) && images.isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SharedContent ||
        other.text != text ||
        other.images.length != images.length) {
      return false;
    }
    for (var i = 0; i < images.length; i++) {
      if (other.images[i] != images[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(text, Object.hashAll(images));

  @override
  String toString() =>
      'SharedContent(text: ${text?.length ?? 0} chars, images: ${images.length})';
}
