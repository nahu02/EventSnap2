import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:material_ui/material_ui.dart';

import '../../models/extraction.dart';
import 'image_viewer.dart';
import 'quote_matcher.dart';

/// The quote to highlight in the source panel and what it belongs to.
class SourceHighlight {
  const SourceHighlight({required this.quote, required this.label});

  /// Evidence quote as returned by the AI.
  final String quote;

  /// What the quote justifies, e.g. `Start · Team meeting`.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is SourceHighlight && other.quote == quote && other.label == label;

  @override
  int get hashCode => Object.hash(quote, label);
}

/// Collapsible card with the original input: the text (selectable, with the
/// active evidence quote highlighted) and image thumbnails (tap → full
/// screen).
class SourceCard extends StatefulWidget {
  const SourceCard({
    super.key,
    required this.input,
    this.highlight,
    this.initiallyExpanded,
  });

  final ExtractionInput input;
  final SourceHighlight? highlight;

  /// Defaults to [shouldStartExpanded].
  final bool? initiallyExpanded;

  /// Longest text (characters) that still starts expanded.
  static const int maxExpandedChars = 280;

  /// Most lines a text may have and still start expanded.
  static const int maxExpandedLines = 5;

  /// Short inputs start expanded; long ones show a preview to keep the
  /// events in view.
  static bool shouldStartExpanded(ExtractionInput input) {
    if (!input.hasText) return true;
    final text = input.text.trim();
    final lines = '\n'.allMatches(text).length + 1;
    return text.length <= maxExpandedChars && lines <= maxExpandedLines;
  }

  @override
  State<SourceCard> createState() => SourceCardState();
}

class SourceCardState extends State<SourceCard> {
  late bool _expanded =
      widget.initiallyExpanded ?? SourceCard.shouldStartExpanded(widget.input);
  final GlobalKey _textKey = GlobalKey();

  String? _matchedQuote;
  QuoteMatch? _match;

  bool get isExpanded => _expanded;

  QuoteMatch? get _currentMatch {
    final quote = widget.highlight?.quote;
    if (quote != _matchedQuote) {
      _matchedQuote = quote;
      _match = QuoteMatcher.find(widget.input.text, quote);
    }
    return _match;
  }

  @override
  void didUpdateWidget(SourceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.input.text != widget.input.text) _matchedQuote = null;
  }

  /// Expands the card and scrolls the highlighted quote (or the card) into
  /// view.
  void reveal() {
    if (!_expanded) setState(() => _expanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlight());
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  void _scrollToHighlight() {
    if (!mounted) return;
    RenderObject? target = context.findRenderObject();
    Rect? rect;
    final match = _currentMatch;
    final textObject = _textKey.currentContext?.findRenderObject();
    if (match != null && textObject != null) {
      final paragraph = _findParagraph(textObject);
      if (paragraph != null) {
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: match.start, extentOffset: match.end),
        );
        if (boxes.isNotEmpty) {
          rect = boxes
              .map((b) => b.toRect())
              .reduce((a, b) => a.expandToInclude(b))
              .inflate(48);
          target = paragraph;
        }
      }
    }
    target?.showOnScreen(
      rect: rect,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  static RenderParagraph? _findParagraph(RenderObject object) {
    if (object is RenderParagraph) return object;
    RenderParagraph? found;
    object.visitChildren((child) => found ??= _findParagraph(child));
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final input = widget.input;
    final images = input.images;

    final summary = [
      if (input.hasText) 'Your text',
      if (images.length == 1) '1 image',
      if (images.length > 1) '${images.length} images',
    ].join(' · ');

    final header = InkWell(
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 8),
        child: Row(
          children: [
            Icon(Icons.notes_outlined, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Source',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.primary,
                    ),
                  ),
                  if (summary.isNotEmpty)
                    Text(
                      summary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: _toggle,
              tooltip: _expanded ? 'Hide source' : 'Show source',
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            ),
          ],
        ),
      ),
    );

    final body = _expanded ? _buildExpanded(context) : _buildCollapsed(context);

    return Card.filled(
      key: const ValueKey('source_card'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (body != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: body,
            ),
        ],
      ),
    );
  }

  TextStyle _highlightStyle(ColorScheme cs) => TextStyle(
    backgroundColor: cs.primaryContainer,
    color: cs.onPrimaryContainer,
    fontWeight: FontWeight.w600,
  );

  Widget? _buildCollapsed(BuildContext context) {
    if (!widget.input.hasText) return null;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = widget.input.text;
    final match = _currentMatch;
    final InlineSpan span;
    if (match != null) {
      final snippet = QuoteMatcher.snippet(text, match);
      span = TextSpan(
        children: [
          TextSpan(text: snippet.before),
          TextSpan(text: snippet.match, style: _highlightStyle(cs)),
          TextSpan(text: snippet.after),
        ],
      );
    } else {
      span = TextSpan(text: text.trim().replaceAll(RegExp(r'\s+'), ' '));
    }
    return Text.rich(
      span,
      key: const ValueKey('source_preview'),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
    );
  }

  Widget _buildExpanded(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final input = widget.input;
    final text = input.text;
    final highlight = widget.highlight;
    final match = _currentMatch;

    final children = <Widget>[];

    if (highlight != null && input.hasText) {
      final captionStyle = theme.textTheme.bodySmall?.copyWith(
        color: cs.onSurfaceVariant,
      );
      children.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              match != null ? Icons.format_quote : Icons.search_off,
              size: 16,
              color: match != null ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: match != null
                  ? Text(
                      'Highlighted: ${highlight.label}',
                      key: const ValueKey('source_highlight_caption'),
                      style: captionStyle,
                    )
                  : Text.rich(
                      key: const ValueKey('source_highlight_caption'),
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '“${highlight.quote.trim()}”',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                          TextSpan(
                            text: input.hasImages
                                ? ' is not word-for-word in your text; it may '
                                      'come from an image.'
                                : ' is not word-for-word in your text.',
                          ),
                        ],
                      ),
                      style: captionStyle,
                    ),
            ),
          ],
        ),
      );
    }

    if (input.hasText) {
      final spans = match == null
          ? [TextSpan(text: text)]
          : [
              TextSpan(text: text.substring(0, match.start)),
              TextSpan(
                text: text.substring(match.start, match.end),
                style: _highlightStyle(cs),
              ),
              TextSpan(text: text.substring(match.end)),
            ];
      children.add(
        SelectionArea(
          child: Text.rich(
            TextSpan(children: spans),
            key: _textKey,
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          ),
        ),
      );
    }

    if (input.hasImages) {
      final images = input.images;
      children.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < images.length; i++)
              _Thumbnail(
                image: images[i],
                index: i,
                count: images.length,
                onTap: () =>
                    ImageViewerScreen.open(context, images, initialIndex: i),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          children[i],
        ],
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.image,
    required this.index,
    required this.count,
    required this.onTap,
  });

  final InputImage image;
  final int index;
  final int count;
  final VoidCallback onTap;

  static const double size = 80;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Open image ${index + 1}',
      child: Semantics(
        button: true,
        label: 'Image ${index + 1} of $count',
        child: Material(
          color: cs.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: cs.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('source_image_$index'),
            onTap: onTap,
            child: InputImageView(image: image, width: size, height: size),
          ),
        ),
      ),
    );
  }
}
