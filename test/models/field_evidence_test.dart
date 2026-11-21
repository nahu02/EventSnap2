import 'package:event_snap_2/models/field_evidence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FieldEvidence', () {
    const evidence = FieldEvidence(
      quote: 'tomorrow at 2pm',
      reasoning: 'Resolved "tomorrow" relative to today.',
      confidence: EvidenceConfidence.high,
    );

    test('toJson uses snake_case keys and enum names', () {
      expect(evidence.toJson(), {
        'quote': 'tomorrow at 2pm',
        'reasoning': 'Resolved "tomorrow" relative to today.',
        'confidence': 'high',
      });
    });

    test('fromJson round-trip', () {
      expect(FieldEvidence.fromJson(evidence.toJson()), evidence);
    });

    test('null quote means inferred', () {
      final parsed = FieldEvidence.fromJson({
        'quote': null,
        'reasoning': 'Defaulted to one hour.',
        'confidence': 'low',
      });
      expect(parsed.quote, isNull);
      expect(parsed.confidence, EvidenceConfidence.low);
    });

    test('fromJson is lenient', () {
      final parsed = FieldEvidence.fromJson({
        'quote': '   ',
        'confidence': 'MEDIUM',
      });
      expect(parsed.quote, isNull);
      expect(parsed.reasoning, '');
      expect(parsed.confidence, EvidenceConfidence.medium);

      expect(
        FieldEvidence.fromJson({'reasoning': 'x', 'confidence': 'sure'})
            .confidence,
        EvidenceConfidence.low,
      );
      expect(FieldEvidence.fromJson({}).confidence, EvidenceConfidence.low);
    });

    test('equality and hashCode', () {
      const same = FieldEvidence(
        quote: 'tomorrow at 2pm',
        reasoning: 'Resolved "tomorrow" relative to today.',
        confidence: EvidenceConfidence.high,
      );
      expect(evidence, same);
      expect(evidence.hashCode, same.hashCode);
      expect(
        evidence,
        isNot(
          const FieldEvidence(
            quote: 'tomorrow at 2pm',
            reasoning: 'Resolved "tomorrow" relative to today.',
            confidence: EvidenceConfidence.low,
          ),
        ),
      );
    });

    test('EventField names match the schema keys', () {
      expect(EventField.values.map((f) => f.name), [
        'title',
        'description',
        'location',
        'start',
        'end',
      ]);
    });
  });
}
