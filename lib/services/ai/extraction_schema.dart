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
    'recurrence',
  ];

  /// Weekday codes used by `recurrence.weekdays`.
  static const List<String> weekdayCodes = [
    'MO',
    'TU',
    'WE',
    'TH',
    'FR',
    'SA',
    'SU',
  ];

  static Map<String, dynamic> get _recurrence => {
    'type': ['object', 'null'],
    'description':
        'How the event repeats, or null for a one-off event. The event '
        'start/end are the FIRST occurrence.',
    'properties': {
      'frequency': {
        'type': 'string',
        'enum': ['daily', 'weekly', 'monthly', 'yearly'],
      },
      'interval': {
        'type': ['integer', 'null'],
        'description': 'Every N periods (2 = every other); null means 1.',
      },
      'weekdays': {
        'type': ['array', 'null'],
        'description':
            'Weekly: the days of the week. Monthly "nth weekday": exactly '
            'one day. Otherwise null.',
        'items': {'type': 'string', 'enum': weekdayCodes},
      },
      'month_day': {
        'type': ['integer', 'null'],
        'description': 'Monthly on a day number (1-31), else null.',
      },
      'weekday_ordinal': {
        'type': ['integer', 'null'],
        'description':
            'Monthly "nth weekday": 1-4, or -1 for the last (with one '
            'weekday in weekdays), else null.',
      },
      'count': {
        'type': ['integer', 'null'],
        'description': 'Total number of occurrences, else null.',
      },
      'until': {
        'type': ['string', 'null'],
        'description': 'Last possible date, YYYY-MM-DD (inclusive), else null.',
      },
    },
    'required': [
      'frequency',
      'interval',
      'weekdays',
      'month_day',
      'weekday_ordinal',
      'count',
      'until',
    ],
    'additionalProperties': false,
  };

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
            'recurrence': _recurrence,
          },
          'required': [
            'evidence',
            'title',
            'description',
            'location',
            'start',
            'end',
            'all_day',
            'recurrence',
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
