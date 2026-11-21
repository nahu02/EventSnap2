import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/extraction.dart';

/// Local image from an [InputImage] (`Image.file`), with a themed placeholder
/// when the file is missing or images from files are unsupported (web).
class InputImageView extends StatelessWidget {
  const InputImageView({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final InputImage image;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _placeholder(context);
    return Image.file(
      File(image.path),
      fit: fit,
      width: width,
      height: height,
      cacheWidth: width == null
          ? null
          : (width! * MediaQuery.devicePixelRatioOf(context)).round(),
      errorBuilder: (context, _, _) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        color: cs.onSurfaceVariant,
        semanticLabel: 'Image not available',
      ),
    );
  }
}

/// Full-screen, zoomable view of the input images (swipe between them).
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  final List<InputImage> images;
  final int initialIndex;

  /// Pushes the viewer as a full-screen dialog.
  static Future<void> open(
    BuildContext context,
    List<InputImage> images, {
    int initialIndex = 0,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            ImageViewerScreen(images: images, initialIndex: initialIndex),
      ),
    );
  }

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.images.length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(count > 1 ? 'Image ${_index + 1} of $count' : 'Image'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: count,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Semantics(
              image: true,
              label: 'Image ${i + 1} of $count',
              child: InputImageView(
                image: widget.images[i],
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
