import 'package:material_ui/material_ui.dart';

import '../../models/event_model.dart';
import 'evidence_line.dart';
import 'event_formatting.dart';

/// Card for one extracted event: a summary header (title when collapsed,
/// locale-aware time range, all-day chip, "N to check" badge, remove and
/// expand actions) and the [child] form.
///
/// The form stays mounted while collapsed so no edits are lost.
class ReviewEventCard extends StatelessWidget {
  const ReviewEventCard({
    super.key,
    required this.event,
    required this.expanded,
    required this.child,
    this.checkCount = 0,
    this.edited = false,
    this.onToggleExpanded,
    this.onRemove,
  });

  /// Current values (for the header).
  final EventModel event;

  final bool expanded;

  /// Number of low-confidence fields the user has not changed yet.
  final int checkCount;

  /// Whether the user changed this event.
  final bool edited;

  /// Null hides the expand/collapse action (e.g. for a single event).
  final VoidCallback? onToggleExpanded;

  final VoidCallback? onRemove;

  /// The event form.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fmt = EventFormatter.of(context);
    final range = fmt.range(event);

    final chips = <Widget>[
      if (event.isAllDay)
        const _Pill(icon: Icons.wb_sunny_outlined, label: 'All day'),
      if (edited) const _Pill(icon: Icons.edit_outlined, label: 'Edited'),
      if (checkCount > 0)
        CheckBadge(
          label: '$checkCount to check',
          tooltip: checkCount == 1
              ? 'One value has low confidence'
              : '$checkCount values have low confidence',
        ),
    ];

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The title is the first form field when expanded; avoid repeating it.
        if (!expanded)
          Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
        Text(
          range,
          key: const ValueKey('event_card_range'),
          style: expanded
              ? theme.textTheme.titleSmall
              : theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: chips),
        ],
      ],
    );

    final header = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: summary,
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove event',
              color: cs.error,
              icon: const Icon(Icons.delete_outline),
            ),
          if (onToggleExpanded != null)
            IconButton(
              onPressed: onToggleExpanded,
              tooltip: expanded ? 'Collapse event' : 'Expand event',
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            ),
        ],
      ),
    );

    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      // Explicit so a theme-wide card shape cannot drop the outline.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onToggleExpanded != null)
            InkWell(onTap: onToggleExpanded, child: header)
          else
            header,
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: Visibility(
              visible: expanded,
              maintainState: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: cs.secondaryContainer,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: cs.onSecondaryContainer),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: cs.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
