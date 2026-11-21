import 'dart:convert';

/// The single JSON schema used for every extraction (one or many events).
///
/// Strict-mode compatible (OpenAI rules, also accepted through Opper): every
/// object has `additionalProperties: false` and lists all its properties in
/// `required`; optional values are nullable; no `$ref`/`$defs`.
///
/// `evidence` comes first in each event so the model writes the supporting
/// quote and reasoning (e.g. how "next Friday" was resolved) before it
/// commits to the values.
class ExtractionSchema {
  ExtractionSchema._();

  /// `json_schema.name` sent with `response_format`.
  static const String name = 'calendar_events';

  /// Fields that carry evidence, in output order.
  static const List<String> evidenceFields = [
    'title',
    'description',
    'location',
    'start',
    'end',
  ];

  static Map<String, dynamic> _evidence(String field) => {
    'type': 'object',
    'description': 'Why "$field" has its value.',
    'properties': {
      'quote': {
        'type': ['string', 'null'],
        'description':
            'Shortest verbatim span from the input (max ~8 words) that '
            'supports the value, copied exactly; null if inferred or '
            'defaulted.',
      },
      'reasoning': {
        'type': 'string',
        'description': 'One short English sentence: how the value was derived.',
      },
      'confidence': {
        'type': 'string',
        'enum': ['high', 'medium', 'low'],
      },
    },
    'required': ['quote', 'reasoning', 'confidence'],
    'additionalProperties': false,
  };

  /// The schema object (`json_schema.schema`).
  static Map<String, dynamic> get schema => {
    'type': 'object',
    'properties': {
      'events': {
        'type': 'array',
        'description': 'Every distinct event found; empty if there is none.',
        'items': {
          'type': 'object',
          'properties': {
            'evidence': {
              'type': 'object',
              'properties': {
                for (final field in evidenceFields) field: _evidence(field),
              },
              'required': evidenceFields,
              'additionalProperties': false,
            },
            'title': {
              'type': 'string',
              'description': 'Short, specific title in the source language.',
            },
            'description': {
              'type': ['string', 'null'],
              'description':
                  'Useful extra details in the source language, or null.',
            },
            'location': {
              'type': ['string', 'null'],
              'description': 'Location if stated, else null.',
            },
            'start': {
              'type': 'string',
              'description':
                  'Local start, YYYY-MM-DDTHH:MM:SS+HH:MM; for all-day '
                  'events the first day, YYYY-MM-DD.',
            },
            'end': {
              'type': 'string',
              'description':
                  'Local end, YYYY-MM-DDTHH:MM:SS+HH:MM; for all-day events '
                  'the last day (inclusive), YYYY-MM-DD.',
            },
            'all_day': {
              'type': 'boolean',
              'description': 'True for date-only events spanning whole days.',
            },
          },
          'required': [
            'evidence',
            'title',
            'description',
            'location',
            'start',
            'end',
            'all_day',
          ],
          'additionalProperties': false,
        },
      },
    },
    'required': ['events'],
    'additionalProperties': false,
  };

  /// `response_format` for strict structured output.
  static Map<String, dynamic> get jsonSchemaResponseFormat => {
    'type': 'json_schema',
    'json_schema': {'name': name, 'strict': true, 'schema': schema},
  };

  /// `response_format` for JSON mode.
  static const Map<String, dynamic> jsonObjectResponseFormat = {
    'type': 'json_object',
  };

  /// The schema as compact JSON text, for prompts in JSON / prompt-only mode.
  static String get schemaText => jsonEncode(schema);
}
