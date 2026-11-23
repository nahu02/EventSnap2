import 'dart:convert';

import 'package:event_snap_2/models/ai_provider.dart';
import 'package:event_snap_2/services/ai/default_model_catalog.dart';
import 'package:event_snap_2/services/ai/model_profile.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A JSON HTTP response.
http.Response jsonResponse(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

/// A Chat Completions response carrying [content].
http.Response chatResponse(String? content, {double cost = 0.0001}) =>
    jsonResponse({
      'id': 'chatcmpl-test',
      'object': 'chat.completion',
      'model': 'test-model',
      'choices': [
        {
          'index': 0,
          'message': {'role': 'assistant', 'content': content},
          'finish_reason': 'stop',
        },
      ],
      'usage': {'prompt_tokens': 10, 'completion_tokens': 20, 'cost': cost},
    });

/// An OpenAI-style error response.
http.Response errorResponse(
  int status,
  String message, {
  String? param,
  String? code,
  Map<String, String> headers = const {},
}) => jsonResponse(
  {
    'error': {
      'message': message,
      'type': 'invalid_request_error',
      'param': param,
      'code': code,
    },
  },
  status: status,
  headers: headers,
);

/// Evidence object in the wire format.
Map<String, dynamic> wireEvidence(
  String? quote, {
  String reasoning = 'Stated in the text.',
  String confidence = 'high',
}) => {'quote': quote, 'reasoning': reasoning, 'confidence': confidence};

/// One event in the strict schema format.
Map<String, dynamic> wireEvent({
  String title = 'Dinner with Anna',
  String? description,
  String? location = "Luigi's",
  String start = '2026-11-27T19:00:00+00:00',
  String end = '2026-11-27T20:00:00+00:00',
  bool allDay = false,
  Object? recurrence,
  Map<String, dynamic>? recurrenceEvidence,
}) => {
  'evidence': {
    'title': wireEvidence('Dinner with Anna'),
    'description': wireEvidence(null, confidence: 'low'),
    'location': wireEvidence("at Luigi's"),
    'start': wireEvidence(
      'next Friday at 7pm',
      reasoning: "'next Friday' is Friday 2026-11-27 in the lookup table.",
    ),
    'end': wireEvidence(
      null,
      reasoning: 'No end given; 1 hour.',
      confidence: 'low',
    ),
    'recurrence':
        recurrenceEvidence ??
        wireEvidence(
          null,
          reasoning: 'No repeat mentioned.',
          confidence: 'high',
        ),
  },
  'title': title,
  'description': description,
  'location': location,
  'start': start,
  'end': end,
  'all_day': allDay,
  'recurrence': recurrence,
};

/// `{"events": [...]}` as a JSON string.
String eventsJson(List<Map<String, dynamic>> events) =>
    jsonEncode({'events': events});

/// Records requests and answers them with [handler].
class RecordingClient {
  RecordingClient(this.handler);

  final Future<http.Response> Function(http.Request request, int index) handler;
  final List<http.Request> requests = [];

  late final MockClient client = MockClient((request) {
    requests.add(request);
    return handler(request, requests.length - 1);
  });

  /// Decoded JSON body of request [index].
  Map<String, dynamic> body(int index) =>
      jsonDecode(requests[index].body) as Map<String, dynamic>;
}

/// [ModelProfileResolver] returning a fixed profile.
class FixedProfileResolver implements ModelProfileResolver {
  FixedProfileResolver(this.profile);

  final ModelProfile profile;
  int calls = 0;

  @override
  Future<ModelProfile> resolveProfile(
    AiProvider provider,
    String modelId, {
    required String apiKey,
  }) async {
    calls++;
    return profile;
  }
}
