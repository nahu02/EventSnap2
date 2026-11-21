import 'package:material_ui/material_ui.dart';

import '../../ui/bottom_action_bar.dart';

/// The home screen's bottom bar: the primary "Find events" button, or, while
/// extracting, the current stage with a Cancel button.
class HomeActionBar extends StatelessWidget {
  const HomeActionBar({
    super.key,
    required this.isProcessing,
    required this.onCancel,
    this.onFindEvents,
    this.stageText = '',
    this.detailText,
  });

  static const findEventsKey = Key('find_events_button');
  static const cancelKey = Key('cancel_button');

  final bool isProcessing;

  /// Disabled when null.
  final VoidCallback? onFindEvents;
  final VoidCallback onCancel;

  /// What is happening, e.g. "Reading your text…" (while processing).
  final String stageText;

  /// Secondary line, e.g. "OpenAI · gpt-5-mini" (while processing).
  final String? detailText;

  @override
  Widget build(BuildContext context) {
    return BottomActionBar(
      showProgress: isProcessing,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: isProcessing
            ? _ProcessingRow(
                key: const ValueKey('processing'),
                stageText: stageText,
                detailText: detailText,
                onCancel: onCancel,
              )
            : SizedBox(
                key: const ValueKey('idle'),
                width: double.infinity,
                child: FilledButton.icon(
                  key: findEventsKey,
                  onPressed: onFindEvents,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Find events'),
                ),
              ),
      ),
    );
  }
}

class _ProcessingRow extends StatelessWidget {
  const _ProcessingRow({
    super.key,
    required this.stageText,
    required this.detailText,
    required this.onCancel,
  });

  final String stageText;
  final String? detailText;
  final VoidCallback onCancel;

  static const _cancelLabel = 'Cancel';
  static const _spacing = 12.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stageStyle = theme.textTheme.titleMedium;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Side by side when the stage text fits on one line next to the
        // button; stacked otherwise (narrow screens, large text).
        final cancelWidth =
            _measure(context, _cancelLabel, theme.textTheme.labelLarge) +
            2 * 24 + // OutlinedButton horizontal padding (theme)
            2; // border
        final inRow =
            _measure(context, stageText, stageStyle) + _spacing + cancelWidth <=
            constraints.maxWidth;
        final cancel = OutlinedButton(
          key: HomeActionBar.cancelKey,
          onPressed: onCancel,
          child: const Text(_cancelLabel),
        );
        final status = _status(
          theme,
          stageStyle,
          detailMaxLines: inRow ? 1 : 2,
        );
        if (inRow) {
          return Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: _spacing),
              cancel,
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            status,
            const SizedBox(height: 8),
            Align(alignment: AlignmentDirectional.centerEnd, child: cancel),
          ],
        );
      },
    );
  }

  Widget _status(
    ThemeData theme,
    TextStyle? stageStyle, {
    required int detailMaxLines,
  }) {
    final detailText = this.detailText;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(stageText, style: stageStyle),
          if (detailText != null)
            Text(
              detailText,
              maxLines: detailMaxLines,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// Width of [text] on one line, honouring the text scale.
  static double _measure(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}
