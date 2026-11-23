import 'dart:io';

import 'package:crop_image/crop_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/extraction.dart';
import '../services/platform/snap_file_store.dart';
import '../services/platform/snap_service.dart';
import '../ui/bottom_action_bar.dart';

/// Full-screen crop of a screen snap ("Snap & crop", docs/v3_plan.md §9).
///
/// A free-form rectangle with draggable handles over the screenshot. Pops with
/// the cropped (ephemeral) [InputImage] on "Use selection" — the full
/// screenshot is deleted right after cropping — or with null on Cancel / back,
/// in which case the caller deletes the screenshot.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.image});

  final InputImage image;

  static const cancelKey = Key('crop_cancel_button');
  static const useSelectionKey = Key('crop_use_selection_button');

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final _controller = CropController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _useSelection() async {
    if (_busy) return;
    setState(() => _busy = true);
    final snapService = context.read<SnapService>();
    final store = context.read<SnapFileStore>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final cropped = await snapService.cropImage(
        widget.image,
        _controller.value.crop,
      );
      // The full screenshot is not needed any more.
      await store.delete([widget.image]);
      if (mounted) Navigator.of(context).pop(cropped);
    } on SnapException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    if (!_busy) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLowest,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: _busy ? null : _cancel,
          ),
          title: const Text('Crop screenshot'),
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: CropImage(
              key: const Key('crop_image'),
              controller: _controller,
              image: Image.file(File(widget.image.path)),
              gridColor: cs.primary,
              gridCornerColor: cs.primary,
              gridInnerColor: cs.primary.withValues(alpha: 0.5),
              scrimColor: cs.scrim.withValues(alpha: 0.55),
              minimumImageSize: 48,
              alwaysShowThirdLines: true,
            ),
          ),
        ),
        bottomNavigationBar: BottomActionBar(
          showProgress: _busy,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: CropScreen.cancelKey,
                  onPressed: _busy ? null : _cancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: CropScreen.useSelectionKey,
                  onPressed: _busy ? null : _useSelection,
                  icon: const Icon(Icons.crop),
                  label: const Text('Use selection'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
