import 'dart:math' as math;

/// Where an evidence quote was found in the source text (`[start, end)` in
/// UTF-16 code units of the original string).
class QuoteMatch {
  const QuoteMatch(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is QuoteMatch && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'QuoteMatch($start, $end)';
}

/// A short excerpt of the source around a [QuoteMatch], for inline context.
class QuoteSnippet {
  const QuoteSnippet({
    required this.before,
    required this.match,
    required this.after,
  });

  /// Text before the quote (with a leading `…` when truncated).
  final String before;

  /// The matched source text (whitespace collapsed).
  final String match;

  /// Text after the quote (with a trailing `…` when truncated).
  final String after;
}

/// Locates AI evidence quotes in the user's original text.
///
/// Models are asked to quote verbatim, but they often change case, collapse
/// line breaks, straighten typographic quotes or wrap the quote in quotation
/// marks. Matching is therefore case- and whitespace-insensitive and treats
/// typographic variants as equal; a second pass ignores punctuation, and a
/// quote elided with `...` falls back to its longest segment.
abstract final class QuoteMatcher {
  /// Finds [quote] in [source]. Returns `null` when it cannot be found.
  static QuoteMatch? find(String source, String? quote) {
    if (quote == null || source.trim().isEmpty) return null;
    final cleaned = _stripWrapping(quote);
    if (cleaned.isEmpty) return null;

    final match =
        _find(source, cleaned, ignorePunctuation: false) ??
        _find(source, cleaned, ignorePunctuation: true);
    if (match != null) return match;

    // "Meeting ... at 10" → try the longest elided segment.
    final segments = cleaned
        .split(RegExp(r'\.{3}|…'))
        .map((s) => s.trim())
        .where((s) => s.length >= 3)
        .toList();
    if (segments.length > 1) {
      segments.sort((a, b) => b.length.compareTo(a.length));
      for (final segment in segments) {
        final m =
            _find(source, segment, ignorePunctuation: false) ??
            _find(source, segment, ignorePunctuation: true);
        if (m != null) return m;
      }
    }
    return null;
  }

  /// Builds an excerpt of [source] around [match] with roughly [context]
  /// characters on each side, cut at word boundaries.
  static QuoteSnippet snippet(
    String source,
    QuoteMatch match, {
    int context = 48,
  }) {
    // Before: start at a sentence boundary inside the window if there is one,
    // otherwise at a word boundary with a leading ellipsis.
    final beforeStart = math.max(0, match.start - context);
    var before = source.substring(beforeStart, match.start);
    var ellipsisBefore = false;
    final sentenceStart = _lastSentenceBoundary(before);
    if (sentenceStart >= 0) {
      before = before.substring(sentenceStart);
    } else if (beforeStart > 0) {
      ellipsisBefore = true;
      final firstSpace = before.indexOf(RegExp(r'\s'));
      if (firstSpace >= 0 && firstSpace < before.length - 1) {
        before = before.substring(firstSpace + 1);
      }
    }

    // After: end at the first sentence end inside the window if there is one,
    // otherwise at a word boundary with a trailing ellipsis.
    final afterEnd = math.min(source.length, match.end + context);
    var after = source.substring(match.end, afterEnd);
    var ellipsisAfter = false;
    final sentenceEnd = _firstSentenceEnd(after);
    if (sentenceEnd >= 0) {
      after = after.substring(0, sentenceEnd);
    } else if (afterEnd < source.length) {
      ellipsisAfter = true;
      final lastSpace = after.lastIndexOf(RegExp(r'\s'));
      if (lastSpace > 0) after = after.substring(0, lastSpace);
    }

    String collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
    before = collapse(before).trimLeft();
    after = collapse(after).trimRight();
    if (ellipsisBefore) before = '…$before';
    if (ellipsisAfter) after = '$after…';
    return QuoteSnippet(
      before: before,
      match: collapse(source.substring(match.start, match.end)),
      after: after,
    );
  }

  static final _sentenceBreak = RegExp(r'[.!?…]\s+|\n\s*\n');

  /// Index just after the last sentence break in [s], or -1.
  static int _lastSentenceBoundary(String s) {
    var result = -1;
    for (final m in _sentenceBreak.allMatches(s)) {
      result = m.end;
    }
    return result;
  }

  /// Index just after the punctuation ending the first sentence in [s]
  /// (or at a blank line), or -1. Single line breaks (hard-wrapped text) do
  /// not end a sentence.
  static int _firstSentenceEnd(String s) {
    final m = RegExp(r'[.!?…](?=\s|$)|\n\s*\n').firstMatch(s);
    if (m == null) return -1;
    return s[m.start] == '\n' ? m.start : m.end;
  }

  // ---------------------------------------------------------------------------

  static const _wrappingChars = '"\'“”‘’«»„‚`';
  static const _punctuation = '.,;:!?\'"()[]{}<>-_/\\|*&^%\$#@~`+=…·';

  static String _stripWrapping(String quote) {
    var q = quote.trim();
    var changed = true;
    while (changed && q.isNotEmpty) {
      changed = false;
      if (_wrappingChars.contains(q[0])) {
        q = q.substring(1).trimLeft();
        changed = true;
      }
      if (q.isNotEmpty && _wrappingChars.contains(q[q.length - 1])) {
        q = q.substring(0, q.length - 1).trimRight();
        changed = true;
      }
    }
    if (q.endsWith('...')) q = q.substring(0, q.length - 3).trimRight();
    if (q.endsWith('…')) q = q.substring(0, q.length - 1).trimRight();
    if (q.startsWith('...')) q = q.substring(3).trimLeft();
    if (q.startsWith('…')) q = q.substring(1).trimLeft();
    return q;
  }

  static QuoteMatch? _find(
    String source,
    String quote, {
    required bool ignorePunctuation,
  }) {
    final q = _normalize(quote, ignorePunctuation: ignorePunctuation);
    final needle = q.text.trim();
    if (needle.isEmpty) return null;
    final s = _normalize(source, ignorePunctuation: ignorePunctuation);
    final at = s.text.indexOf(needle);
    if (at < 0) return null;
    final start = s.indices[at];
    final end = s.indices[at + needle.length - 1] + 1;
    return QuoteMatch(start, end);
  }

  static _Normalized _normalize(String s, {required bool ignorePunctuation}) {
    final buffer = StringBuffer();
    final indices = <int>[];
    var pendingSpaceAt = -1;
    for (var i = 0; i < s.length; i++) {
      final unit = s.codeUnitAt(i);
      if (_isWhitespace(unit)) {
        if (pendingSpaceAt < 0 && indices.isNotEmpty) pendingSpaceAt = i;
        continue;
      }
      final folded = _fold(s[i]);
      if (ignorePunctuation && _punctuation.contains(folded)) continue;
      if (pendingSpaceAt >= 0) {
        buffer.write(' ');
        indices.add(pendingSpaceAt);
        pendingSpaceAt = -1;
      }
      buffer.write(folded);
      for (var k = 0; k < folded.length; k++) {
        indices.add(i);
      }
    }
    return _Normalized(buffer.toString(), indices);
  }

  static String _fold(String ch) {
    switch (ch) {
      case '‘' || '’' || '‚' || '‛' || '`' || '´':
        return "'";
      case '“' || '”' || '„' || '‟' || '«' || '»':
        return '"';
      case '–' || '—' || '‐' || '‑' || '−':
        return '-';
    }
    return ch.toLowerCase();
  }

  static bool _isWhitespace(int unit) =>
      unit == 0x20 ||
      (unit >= 0x09 && unit <= 0x0D) ||
      unit == 0xA0 ||
      unit == 0x1680 ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      unit == 0x2028 ||
      unit == 0x2029 ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000 ||
      unit == 0xFEFF;
}

class _Normalized {
  const _Normalized(this.text, this.indices);

  /// Normalised text.
  final String text;

  /// For every code unit of [text], the index of the original code unit.
  final List<int> indices;
}
