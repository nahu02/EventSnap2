import 'package:material_ui/material_ui.dart';

import '../../models/extraction.dart';
import 'attachment_thumbnail.dart';

/// The home screen's input: a multi-line text field, attached image
/// thumbnails and a toolbar (paste, gallery, camera, clear).
///
/// Stateless: the home screen owns the controller, the images and the
/// callbacks. The card's outline turns primary while the field has focus.
class ComposerCard extends StatelessWidget {
  const ComposerCard({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.images,
    required this.enabled,
    required this.canAddImages,
    required this.onPaste,
    required this.onPickFromGallery,
    required this.onRemoveImage,
    this.onCaptureWithCamera,
    this.onClear,
  });

  static const textFieldKey = Key('composer_text_field');
  static const hintText =
      'Paste or type anything with a date or time: an email, a chat '
      'message, an invitation…';

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<InputImage> images;

  /// False while events are being extracted.
  final bool enabled;

  /// False once the maximum number of images is attached.
  final bool canAddImages;

  final VoidCallback onPaste;
  final VoidCallback onPickFromGallery;
  final ValueChanged<int> onRemoveImage;

  /// Hidden when null (camera not supported).
  final VoidCallback? onCaptureWithCamera;

  /// Hidden when null (nothing to clear).
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final imageTooltip = canAddImages ? null : 'You can add up to 4 images';

    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) {
        final focused = focusNode.hasFocus && enabled;
        return Card.outlined(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            side: BorderSide(
              color: focused ? cs.primary : cs.outlineVariant,
              width: focused ? 2 : 1,
            ),
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: textFieldKey,
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            minLines: 5,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: hintText,
              hintMaxLines: 4,
              contentPadding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            ),
          ),
          if (images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < images.length; i++)
                    AttachmentThumbnail(
                      key: ValueKey('attachment_$i'),
                      image: images[i],
                      label: 'Image ${i + 1}',
                      onRemove: enabled ? () => onRemoveImage(i) : null,
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.content_paste),
                  tooltip: 'Paste',
                  onPressed: enabled ? onPaste : null,
                ),
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  tooltip: imageTooltip ?? 'Add image from gallery',
                  onPressed: enabled && canAddImages ? onPickFromGallery : null,
                ),
                if (onCaptureWithCamera != null)
                  IconButton(
                    icon: const Icon(Icons.photo_camera_outlined),
                    tooltip: imageTooltip ?? 'Take a photo',
                    onPressed: enabled && canAddImages
                        ? onCaptureWithCamera
                        : null,
                  ),
                if (onClear != null)
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        key: const Key('composer_clear_button'),
                        onPressed: enabled ? onClear : null,
                        child: const Text(
                          'Clear',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
