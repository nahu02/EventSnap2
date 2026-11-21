import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/extraction.dart';

/// Subtle banner listing non-blocking notes from the extraction
/// (e.g. "Model lacks structured output; used JSON mode").
class ReviewWarningsBanner extends StatelessWidget {
  const ReviewWarningsBanner({super.key, required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return DecoratedBox(
      key: const ValueKey('review_warnings'),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 20, color: cs.tertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final warning in warnings)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(warning, style: style),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline error banner shown above the primary action when handing the
/// events to a calendar app failed.
class ExportProblemBanner extends StatelessWidget {
  const ExportProblemBanner({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Card.filled(
        key: const ValueKey('export_problem'),
        margin: EdgeInsets.zero,
        color: cs.errorContainer,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.error_outline,
                      color: cs.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onErrorContainer,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onDismiss != null)
                    IconButton(
                      onPressed: onDismiss,
                      tooltip: 'Dismiss',
                      color: cs.onErrorContainer,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              if (actionLabel != null && onAction != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onErrorContainer,
                    ),
                    child: Text(actionLabel!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Debug-mode panel with the raw model output and how it was produced.
class RawResponsePanel extends StatelessWidget {
  const RawResponsePanel({super.key, required this.result});

  final ExtractionResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final raw = result.rawResponse;
    final mode = result.usedStructuredOutput
        ? 'structured output'
        : 'no structured output';
    return Card.outlined(
      key: const ValueKey('raw_response_panel'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.code, color: cs.onSurfaceVariant),
        title: const Text('Raw AI response'),
        subtitle: Text(
          '${result.provider.displayName} · ${result.model} · $mode',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 16),
        children: [
          if (raw == null || raw.isEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'No raw response was recorded.',
                style: theme.textTheme.bodySmall,
              ),
            )
          else ...[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: 'Copy raw response',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: raw));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      behavior: SnackBarBehavior.floating,
                      content: Text('Raw response copied'),
                    ),
                  );
                },
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: SizedBox(
                  width: double.infinity,
                  child: SelectableText(
                    raw,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown when there are no events (none found, or all removed).
class ReviewEmptyState extends StatelessWidget {
  const ReviewEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.onEditText,
  });

  final String title;
  final String message;
  final VoidCallback onEditText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(Icons.event_busy_outlined, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onEditText,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit text'),
          ),
        ],
      ),
    );
  }
}
