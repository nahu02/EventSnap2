import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/extraction.dart';

/// A square thumbnail of an attached image with a remove (×) button.
class AttachmentThumbnail extends StatelessWidget {
  const AttachmentThumbnail({
    super.key,
    required this.image,
    required this.label,
    this.onRemove,
  });

  /// Edge length of the image.
  static const double size = 72;

  final InputImage image;

  /// Accessible name, e.g. "Image 1".
  final String label;

  /// Removes the image; the button is disabled when null.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // The remove button overlaps the image's top-end corner but stays inside
    // the widget's bounds so the whole button is tappable.
    const buttonSize = 32.0;
    const overlap = 20.0;
    return SizedBox(
      width: size + buttonSize - overlap,
      height: size + buttonSize - overlap,
      child: Stack(
        children: [
          PositionedDirectional(
            start: 0,
            bottom: 0,
            width: size,
            height: size,
            child: Semantics(
              image: true,
              label: label,
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  child: _ThumbnailImage(image: image),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            child: IconButton.filled(
              tooltip: 'Remove ${label.toLowerCase()}',
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: cs.inverseSurface,
                foregroundColor: cs.onInverseSurface,
                minimumSize: const Size.square(buttonSize),
                fixedSize: const Size.square(buttonSize),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbnailImage extends StatelessWidget {
  const _ThumbnailImage({required this.image});

  final InputImage image;

  @override
  Widget build(BuildContext context) {
    // Image files are not available on the web (no dart:io file system).
    if (kIsWeb) return const _Placeholder();
    final cacheSize =
        (AttachmentThumbnail.size * MediaQuery.devicePixelRatioOf(context))
            .round();
    return Image.file(
      File(image.path),
      fit: BoxFit.cover,
      cacheWidth: cacheSize,
      excludeFromSemantics: true,
      // Placeholder while decoding and when the file cannot be read.
      frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
          frame == null && !wasSynchronouslyLoaded
          ? const _Placeholder()
          : child,
      errorBuilder: (_, _, _) => const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant),
      ),
    );
  }
}
