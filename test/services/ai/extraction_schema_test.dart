import 'dart:convert';

import 'package:event_snap_2/services/ai/extraction_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Visits every schema object node.
  void visit(Object? node, void Function(Map<String, dynamic>) visitor) {
    if (node is Map<String, dynamic>) {
      visitor(node);
      for (final value in node.values) {
        visit(value, visitor);
      }
    } else if (node is List) {
      for (final v in node) {
        visit(v, visitor);
      }
    }
  }

  test('is strict-mode compatible', () {
    var objects = 0;
    visit(ExtractionSchema.schema, (node) {
      if (node['type'] == 'object') {
        objects++;
        expect(node['additionalProperties'], isFalse, reason: '$node');
        final properties = (node['properties'] as Map).keys.toSet();
        expect((node['required'] as List).toSet(), properties);
      }
    });
    // root, event, evidence, 5 × field evidence
    expect(objects, 8);
    final text = ExtractionSchema.schemaText;
    expect(text, isNot(contains(r'$ref')));
    expect(text, isNot(contains(r'$defs')));
  });

  test('describes events with per-field evidence', () {
    final item =
        (ExtractionSchema.schema['properties'] as Map)['events']['items']
            as Map<String, dynamic>;
    final properties = item['properties'] as Map<String, dynamic>;
    expect(properties.keys, [
      'evidence',
      'title',
      'description',
      'location',
      'start',
      'end',
      'all_day',
    ]);
    expect(properties['description']['type'], ['string', 'null']);
    expect(properties['all_day']['type'], 'boolean');
    final evidence = properties['evidence']['properties'] as Map;
    expect(evidence.keys, ExtractionSchema.evidenceFields);
    final e = evidence['start'] as Map;
    expect(e['properties']['quote']['type'], ['string', 'null']);
    expect(e['properties']['confidence']['enum'], ['high', 'medium', 'low']);
  });

  test('response formats', () {
    final strict = ExtractionSchema.jsonSchemaResponseFormat;
    expect(strict['type'], 'json_schema');
    expect(strict['json_schema']['name'], 'calendar_events');
    expect(strict['json_schema']['strict'], isTrue);
    expect(strict['json_schema']['schema'], ExtractionSchema.schema);
    expect(ExtractionSchema.jsonObjectResponseFormat, {'type': 'json_object'});
    expect(jsonDecode(ExtractionSchema.schemaText), ExtractionSchema.schema);
  });
}
