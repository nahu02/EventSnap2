import 'package:material_ui/material_ui.dart';

import '../../models/field_evidence.dart';
import 'quote_matcher.dart';

/// Human-readable names of the evidence fields.
extension EventFieldLabel on EventField {
  String get label => switch (this) {
    EventField.title => 'Title',
    EventField.description => 'Description',
    EventField.location => 'Location',
    EventField.start => 'Start',
    EventField.end => 'End',
  };
}

/// Small pill flagging values that deserve a second look (tertiary roles).
class CheckBadge extends StatelessWidget {
  const CheckBadge({
    super.key,
    this.label = 'Check',
    this.tooltip = 'Low confidence: double-check this value',
  });

  final String label;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: cs.onTertiaryContainer);
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: cs.tertiaryContainer,
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 14,
                color: cs.onTertiaryContainer,
              ),
              const SizedBox(width: 4),
              Flexible(child: Text(label, style: textStyle)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line under a form field explaining where its value came from.
///
/// Collapsed: a quote icon with the verbatim “quote” and the AI's reasoning
/// (or "Inferred" when nothing was quoted, or "Edited by you" once the user
/// changed the value). Low-confidence values get a [CheckBadge].
///
/// Tapping expands it — the quote in the context of the original text, the
/// full reasoning, the confidence and a "Show in source" action — and calls
/// [onActivate] so the screen can highlight the quote in the source panel.
class EvidenceLine extends StatefulWidget {
  const EvidenceLine({
    super.key,
    required this.field,
    required this.evidence,
    this.edited = false,
    this.sourceText = '',
    this.hasImages = false,
    this.suggestedValue,
    this.onActivate,
    this.onShowInSource,
  });

  final EventField field;
  final FieldEvidence evidence;

  /// The user changed this field: show "Edited by you" instead of the AI
  /// reasoning (the reasoning stays available when expanded).
  final bool edited;

  /// The original text, used to show the quote in context.
  final String sourceText;

  /// Whether the input had images (unmatched quotes probably come from them).
  final bool hasImages;

  /// The AI's original value, shown as "Suggested: …" when [edited].
  final String? suggestedValue;

  /// Called whenever the line is tapped (highlight the quote in the source).
  final VoidCallback? onActivate;

  /// Called by the "Show in source" action; hidden when null or when the
  /// quote is not part of [sourceText].
  final VoidCallback? onShowInSource;

  @override
  State<EvidenceLine> createState() => _EvidenceLineState();
}

class _EvidenceLineState extends State<EvidenceLine> {
  bool _expanded = false;

  void _handleTap() {
    setState(() => _expanded = !_expanded);
    widget.onActivate?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final evidence = widget.evidence;
    final quote = evidence.quote;
    final needsCheck =
        !widget.edited && evidence.confidence == EvidenceConfidence.low;
    final match = _expanded
        ? QuoteMatcher.find(widget.sourceText, quote)
        : null;

    final IconData icon;
    if (widget.edited) {
      icon = Icons.edit_outlined;
    } else if (quote != null) {
      icon = Icons.format_quote;
    } else {
      icon = Icons.auto_awesome_outlined;
    }

    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final strongStyle = TextStyle(
      color: cs.onSurface,
      fontWeight: FontWeight.w500,
    );

    final InlineSpan summary;
    if (widget.edited) {
      summary = TextSpan(text: 'Edited by you', style: strongStyle);
    } else if (_expanded) {
      summary = TextSpan(
        text: quote == null
            ? 'Inferred'
            : match != null
            ? 'From your text'
            : widget.hasImages
            ? 'Read from your image'
            : 'Quoted by the AI',
        style: strongStyle,
      );
    } else {
      summary = TextSpan(
        children: [
          if (quote != null)
            TextSpan(
              text: '“${quote.trim()}”',
              style: strongStyle.copyWith(fontStyle: FontStyle.italic),
            )
          else
            TextSpan(text: 'Inferred', style: strongStyle),
          if (evidence.reasoning.trim().isNotEmpty)
            TextSpan(text: ' · ${evidence.reasoning.trim()}'),
        ],
      );
    }

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            icon,
            size: 16,
            color: widget.edited ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            summary,
            style: baseStyle,
            maxLines: _expanded ? null : 2,
            overflow: _expanded ? null : TextOverflow.ellipsis,
          ),
        ),
        if (needsCheck) ...[const SizedBox(width: 8), const CheckBadge()],
        const SizedBox(width: 4),
        AnimatedRotation(
          turns: _expanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(Icons.expand_more, size: 18, color: cs.onSurfaceVariant),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Semantics(
            button: true,
            expanded: _expanded,
            label: 'Why this ${widget.field.label.toLowerCase()}',
            child: InkWell(
              key: ValueKey('evidence_${widget.field.name}'),
              borderRadius: BorderRadius.circular(8),
              onTap: _handleTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: header,
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? _EvidenceDetails(
                  evidence: evidence,
                  match: match,
                  sourceText: widget.sourceText,
                  edited: widget.edited,
                  suggestedValue: widget.suggestedValue,
                  onShowInSource: match == null ? null : widget.onShowInSource,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _EvidenceDetails extends StatelessWidget {
  const _EvidenceDetails({
    required this.evidence,
    required this.match,
    required this.sourceText,
    required this.edited,
    required this.suggestedValue,
    required this.onShowInSource,
  });

  final FieldEvidence evidence;
  final QuoteMatch? match;
  final String sourceText;
  final bool edited;
  final String? suggestedValue;
  final VoidCallback? onShowInSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final small = theme.textTheme.bodySmall;
    final quote = evidence.quote;
    final match = this.match;

    Widget? quoteBox;
    if (quote != null) {
      final InlineSpan span;
      if (match != null) {
        final snippet = QuoteMatcher.snippet(sourceText, match);
        span = TextSpan(
          children: [
            TextSpan(text: snippet.before),
            TextSpan(
              text: snippet.match,
              style: TextStyle(
                backgroundColor: cs.primaryContainer,
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: snippet.after),
          ],
        );
      } else {
        span = TextSpan(
          text: '“${quote.trim()}”',
          style: const TextStyle(fontStyle: FontStyle.italic),
        );
      }
      quoteBox = DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: cs.primary, width: 3)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Text.rich(
            span,
            key: const ValueKey('evidence_quote_context'),
            style: small?.copyWith(color: cs.onSurface),
          ),
        ),
      );
    }

    final (
      IconData confidenceIcon,
      String confidenceText,
      Color color,
    ) = switch (evidence.confidence) {
      EvidenceConfidence.high => (
        Icons.verified_outlined,
        'High confidence',
        cs.primary,
      ),
      EvidenceConfidence.medium => (
        Icons.info_outline,
        'Medium confidence',
        cs.onSurfaceVariant,
      ),
      EvidenceConfidence.low => (
        Icons.error_outline,
        'Low confidence: check this value',
        cs.tertiary,
      ),
    };

    final children = <Widget>[
      if (edited && suggestedValue != null)
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Suggested: ',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: suggestedValue),
            ],
          ),
          style: small?.copyWith(color: cs.onSurface),
        ),
      ?quoteBox,
      if (evidence.reasoning.trim().isNotEmpty)
        Text(
          evidence.reasoning.trim(),
          style: small?.copyWith(color: cs.onSurface),
        ),
      Row(
        children: [
          Icon(confidenceIcon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(confidenceText, style: small?.copyWith(color: color)),
          ),
        ],
      ),
      if (onShowInSource != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onShowInSource,
            icon: const Icon(Icons.find_in_page_outlined, size: 18),
            label: const Text('Show in source'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(28, 2, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}
