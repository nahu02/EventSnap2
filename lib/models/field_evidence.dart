/// Event fields the AI can provide evidence for.
enum EventField { title, description, location, start, end }

/// How sure the model is about an extracted value.
enum EvidenceConfidence { high, medium, low }

/// Why the AI filled a field the way it did (shown on the review screen).
class FieldEvidence {
  /// Verbatim excerpt from the source text (or text read from an image).
  /// `null` if the value was inferred or defaulted.
  final String? quote;

  /// One short sentence: how the value was derived.
  final String reasoning;

  final EvidenceConfidence confidence;

  const FieldEvidence({
    this.quote,
    required this.reasoning,
    required this.confidence,
  });

  /// Lenient parser for the snake_case wire/storage format
  /// (`quote`, `reasoning`, `confidence`).
  ///
  /// Blank quotes become `null`; a missing reasoning becomes `''`; an unknown
  /// or missing confidence becomes [EvidenceConfidence.low] so the UI asks the
  /// user to double-check.
  factory FieldEvidence.fromJson(Map<String, dynamic> json) {
    final rawQuote = json['quote'];
    final quote = rawQuote is String && rawQuote.trim().isNotEmpty
        ? rawQuote
        : null;
    final rawReasoning = json['reasoning'];
    return FieldEvidence(
      quote: quote,
      reasoning: rawReasoning is String ? rawReasoning : '',
      confidence: _parseConfidence(json['confidence']),
    );
  }

  Map<String, dynamic> toJson() => {
    'quote': quote,
    'reasoning': reasoning,
    'confidence': confidence.name,
  };

  static EvidenceConfidence _parseConfidence(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final confidence in EvidenceConfidence.values) {
        if (confidence.name == normalized) return confidence;
      }
    }
    return EvidenceConfidence.low;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FieldEvidence &&
        other.quote == quote &&
        other.reasoning == reasoning &&
        other.confidence == confidence;
  }

  @override
  int get hashCode => Object.hash(quote, reasoning, confidence);

  @override
  String toString() =>
      'FieldEvidence(quote: $quote, reasoning: $reasoning, '
      'confidence: ${confidence.name})';
}
