import 'dart:async';
import 'dart:io' show HttpDate;
import 'dart:math';

import 'package:event_snap_2/services/ai/ai_cancellation_token.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/services/ai/openai_compatible_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'ai_test_helpers.dart';

void main() {
  final url = Uri.parse('https://api.example.com/v1/chat/completions');
  late List<Duration> delays;

  setUp(() => delays = []);

  OpenAiCompatibleClient clientFor(
    RecordingClient recording, {
    int maxRetries = 2,
    Duration timeout = const Duration(seconds: 5),
    DelayFunction? delay,
  }) => OpenAiCompatibleClient(
    httpClient: recording.client,
    maxRetries: maxRetries,
    timeout: timeout,
    delay: delay ?? (d) async => delays.add(d),
    random: Random(7),
  );

  Future<AiException> failure(Future<Object?> future) async {
    try {
      await future;
    } on AiException catch (e) {
      return e;
    }
    fail('expected an AiException');
  }

  group('request', () {
    test('POSTs JSON with bearer auth and parses the completion', () async {
      final recording = RecordingClient((_, _) async => chatResponse('{}'));
      final completion = await clientFor(recording).createChatCompletion(
        url: url,
        apiKey: '  secret-key  ',
        body: {'model': 'm', 'messages': []},
      );

      final request = recording.requests.single;
      expect(request.method, 'POST');
      expect(request.url, url);
      expect(request.headers['Authorization'], 'Bearer secret-key');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(recording.body(0), {'model': 'm', 'messages': []});
      expect(completion.content, '{}');
      expect(completion.finishReason, 'stop');
      expect(completion.cost, 0.0001);
      expect(completion.usage?['prompt_tokens'], 10);
    });

    test('GET without a key sends no Authorization header', () async {
      final recording = RecordingClient(
        (_, _) async => jsonResponse({'ok': true}),
      );
      final json = await clientFor(recording).getJson(url);
      expect(json, {'ok': true});
      expect(recording.requests.single.method, 'GET');
      expect(recording.requests.single.headers['Authorization'], isNull);
    });

    test('joins text content parts and reads refusals', () async {
      final recording = RecordingClient(
        (_, _) async => jsonResponse({
          'choices': [
            {
              'message': {
                'content': [
                  {'type': 'text', 'text': '{"events":'},
                  {'type': 'text', 'text': '[]}'},
                ],
                'refusal': 'nope',
              },
              'finish_reason': 'stop',
            },
          ],
        }),
      );
      final completion = await clientFor(recording)
          .createChatCompletion(url: url, apiKey: 'k', body: {});
      expect(completion.content, '{"events":[]}');
      expect(completion.refusal, 'nope');
    });

    test('a response without choices is invalidResponse', () async {
      final recording = RecordingClient(
        (_, _) async => jsonResponse({'choices': []}),
      );
      final e = await failure(
        clientFor(recording)
            .createChatCompletion(url: url, apiKey: 'k', body: {}),
      );
      expect(e.kind, AiErrorKind.invalidResponse);
    });

    test('a 200 body carrying an error is mapped', () async {
      final recording = RecordingClient(
        (_, _) async => jsonResponse({
          'error': {'message': 'The model `x` does not exist'},
        }),
      );
      final e = await failure(
        clientFor(recording)
            .createChatCompletion(url: url, apiKey: 'k', body: {}),
      );
      expect(e.kind, AiErrorKind.modelNotFound);
    });

    test('a non-JSON success body is invalidResponse', () async {
      final recording = RecordingClient(
        (_, _) async => http.Response('<html>oops</html>', 200),
      );
      final e = await failure(clientFor(recording).getJson(url));
      expect(e.kind, AiErrorKind.invalidResponse);
    });
  });

  group('mapHttpError', () {
    AiErrorKind kindOf(
      int status,
      String message, {
      String? code,
    }) => OpenAiCompatibleClient.mapHttpError(
      statusCode: status,
      body:
          '{"error":{"message":${_quote(message)},"code":${code == null ? 'null' : _quote(code)}}}',
    ).kind;

    test('maps status codes and bodies to kinds', () {
      expect(kindOf(401, 'Incorrect API key provided'), AiErrorKind.auth);
      expect(kindOf(403, 'Forbidden'), AiErrorKind.auth);
      expect(kindOf(402, 'Budget exhausted'), AiErrorKind.quotaExceeded);
      expect(kindOf(404, 'Not found'), AiErrorKind.modelNotFound);
      expect(
        kindOf(400, 'The model `gpt-9` does not exist'),
        AiErrorKind.modelNotFound,
      );
      expect(
        kindOf(400, 'bad', code: 'model_not_found'),
        AiErrorKind.modelNotFound,
      );
      expect(kindOf(429, 'Rate limit reached'), AiErrorKind.rateLimited);
      expect(
        kindOf(429, 'You exceeded your current quota, check billing'),
        AiErrorKind.quotaExceeded,
      );
      expect(
        kindOf(429, 'x', code: 'insufficient_quota'),
        AiErrorKind.quotaExceeded,
      );
      expect(
        kindOf(
          400,
          'Invalid content type. image_url is only supported by certain '
          'models.',
        ),
        AiErrorKind.unsupportedInput,
      );
      expect(
        kindOf(400, 'This model does not support vision input'),
        AiErrorKind.unsupportedInput,
      );
      expect(
        kindOf(400, "This model's maximum context length is 8192 tokens"),
        AiErrorKind.unsupportedInput,
      );
      expect(kindOf(413, 'Payload too large'), AiErrorKind.unsupportedInput);
      expect(kindOf(408, 'Request timeout'), AiErrorKind.timeout);
      expect(kindOf(500, 'Internal error'), AiErrorKind.server);
      expect(kindOf(503, 'Overloaded'), AiErrorKind.server);
      expect(kindOf(400, "Invalid 'messages'"), AiErrorKind.unknown);
    });

    test('handles plain-text and alternative error bodies', () {
      expect(
        OpenAiCompatibleClient.mapHttpError(
          statusCode: 404,
          body: '{"error":"model \\"x/y\\" not found"}',
        ).message,
        contains('model "x/y" not found'),
      );
      final plain = OpenAiCompatibleClient.mapHttpError(
        statusCode: 502,
        body: 'Bad gateway',
        url: url,
      );
      expect(plain.kind, AiErrorKind.server);
      expect(plain.statusCode, 502);
      expect(plain.message, contains('HTTP 502'));
      expect(plain.message, contains('api.example.com'));
      expect(plain.message, contains('Bad gateway'));
    });

    test('includes the error code/param for callers to inspect', () {
      final e = OpenAiCompatibleClient.mapHttpError(
        statusCode: 400,
        body: '{"error":{"message":"Unsupported","param":"response_format","type":"invalid_request_error"}}',
      );
      expect(e.message, contains('response_format'));
    });
  });

  group('retries', () {
    test('retries 5xx with exponential backoff and jitter', () async {
      final recording = RecordingClient(
        (_, i) async => i < 2 ? errorResponse(503, 'busy') : chatResponse('ok'),
      );
      final completion = await clientFor(recording)
          .createChatCompletion(url: url, apiKey: 'k', body: {});

      expect(completion.content, 'ok');
      expect(recording.requests, hasLength(3));
      expect(delays, hasLength(2));
      const base = RetryPolicy();
      expect(delays[0], greaterThanOrEqualTo(base.baseDelay * 0.5));
      expect(delays[0], lessThanOrEqualTo(base.baseDelay));
      expect(delays[1], greaterThanOrEqualTo(base.baseDelay));
      expect(delays[1], lessThanOrEqualTo(base.baseDelay * 2));
    });

    test('gives up after maxRetries and reports the last error', () async {
      final recording = RecordingClient(
        (_, _) async => errorResponse(500, 'boom'),
      );
      final e = await failure(
        clientFor(
          recording,
          maxRetries: 2,
        ).createChatCompletion(url: url, apiKey: 'k', body: {}),
      );
      expect(e.kind, AiErrorKind.server);
      expect(e.statusCode, 500);
      expect(recording.requests, hasLength(3));
    });

    test('maxRetries 0 makes a single attempt', () async {
      final recording = RecordingClient(
        (_, _) async => errorResponse(500, 'boom'),
      );
      await failure(clientFor(recording, maxRetries: 0).getJson(url));
      expect(recording.requests, hasLength(1));
      expect(delays, isEmpty);
    });

    test('honours Retry-After (seconds) on 429', () async {
      final recording = RecordingClient(
        (_, i) async => i == 0
            ? errorResponse(
                429,
                'Rate limit reached',
                headers: {'retry-after': '3'},
              )
            : chatResponse('ok'),
      );
      await clientFor(recording).getJson(url);
      expect(delays, [const Duration(seconds: 3)]);
    });

    test('honours retry-after-ms', () async {
      final recording = RecordingClient(
        (_, i) async => i == 0
            ? errorResponse(
                429,
                'slow down',
                headers: {'retry-after-ms': '250'},
              )
            : chatResponse('ok'),
      );
      await clientFor(recording).getJson(url);
      expect(delays, [const Duration(milliseconds: 250)]);
    });

    test('does not wait for a very long Retry-After', () async {
      final recording = RecordingClient(
        (_, _) async =>
            errorResponse(429, 'Rate limit', headers: {'retry-after': '600'}),
      );
      final e = await failure(clientFor(recording).getJson(url));
      expect(e.kind, AiErrorKind.rateLimited);
      expect(recording.requests, hasLength(1));
    });

    test('does not retry quota, auth or bad requests', () async {
      for (final response in [
        errorResponse(429, 'You exceeded your current quota'),
        errorResponse(401, 'Invalid key'),
        errorResponse(400, 'Bad request'),
      ]) {
        final recording = RecordingClient((_, _) async => response);
        await failure(clientFor(recording).getJson(url));
        expect(recording.requests, hasLength(1));
      }
      expect(delays, isEmpty);
    });

    test('retries network errors', () async {
      final recording = RecordingClient((_, i) async {
        if (i == 0) throw http.ClientException('Connection reset', url);
        return chatResponse('ok');
      });
      final completion = await clientFor(recording)
          .createChatCompletion(url: url, apiKey: 'k', body: {});
      expect(completion.content, 'ok');
      expect(recording.requests, hasLength(2));
    });

    test('maps persistent network errors to network', () async {
      final recording = RecordingClient(
        (_, _) async => throw http.ClientException('Failed host lookup', url),
      );
      final e = await failure(clientFor(recording, maxRetries: 1).getJson(url));
      expect(e.kind, AiErrorKind.network);
      expect(recording.requests, hasLength(2));
    });
  });

  group('timeout and cancellation', () {
    test('times out a hanging request and retries it', () async {
      final recording = RecordingClient(
        (_, _) => Completer<http.Response>().future,
      );
      final stopwatch = Stopwatch()..start();
      final e = await failure(
        clientFor(
          recording,
          maxRetries: 1,
          timeout: const Duration(milliseconds: 50),
        ).getJson(url),
      );
      expect(e.kind, AiErrorKind.timeout);
      expect(recording.requests, hasLength(2));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('a cancelled token prevents the request', () async {
      final recording = RecordingClient((_, _) async => chatResponse('ok'));
      final token = AiCancellationToken()..cancel();
      final e = await failure(
        clientFor(recording).getJson(url, cancellationToken: token),
      );
      expect(e.kind, AiErrorKind.cancelled);
      expect(recording.requests, isEmpty);
    });

    test('cancelling aborts an in-flight request', () async {
      final started = Completer<void>();
      final recording = RecordingClient((_, _) {
        started.complete();
        return Completer<http.Response>().future;
      });
      final token = AiCancellationToken();
      final future = clientFor(recording)
          .getJson(url, cancellationToken: token);
      await started.future;
      token.cancel();
      final e = await failure(future);
      expect(e.kind, AiErrorKind.cancelled);
      expect(recording.requests, hasLength(1));
    });

    test('cancelling during backoff stops retrying', () async {
      final recording = RecordingClient(
        (_, _) async => errorResponse(503, 'busy'),
      );
      final token = AiCancellationToken();
      final waiting = Completer<void>();
      final future = clientFor(
        recording,
        delay: (d) {
          waiting.complete();
          return Completer<void>().future; // never elapses
        },
      ).getJson(url, cancellationToken: token);
      await waiting.future;
      token.cancel();
      final e = await failure(future);
      expect(e.kind, AiErrorKind.cancelled);
      expect(recording.requests, hasLength(1));
    });
  });

  group('parseRetryAfter', () {
    test('reads seconds, milliseconds and HTTP dates', () {
      expect(
        OpenAiCompatibleClient.parseRetryAfter({'Retry-After': '2'}),
        const Duration(seconds: 2),
      );
      expect(
        OpenAiCompatibleClient.parseRetryAfter({'retry-after': '1.5'}),
        const Duration(milliseconds: 1500),
      );
      expect(
        OpenAiCompatibleClient.parseRetryAfter({
          'retry-after-ms': '120',
          'retry-after': '9',
        }),
        const Duration(milliseconds: 120),
      );
      final now = DateTime.utc(2026, 11, 21, 12);
      expect(
        OpenAiCompatibleClient.parseRetryAfter({
          'retry-after': HttpDate.format(now.add(const Duration(seconds: 7))),
        }, now: now),
        const Duration(seconds: 7),
      );
      expect(OpenAiCompatibleClient.parseRetryAfter({}), isNull);
      expect(
        OpenAiCompatibleClient.parseRetryAfter({'retry-after': 'soon'}),
        isNull,
      );
    });
  });

  group('RetryPolicy', () {
    test('backoff doubles, stays within jitter bounds and is capped', () {
      const policy = RetryPolicy(
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 5),
      );
      final random = Random(3);
      for (var retry = 0; retry < 6; retry++) {
        final full = Duration(
          microseconds: min(
            1000000 * pow(2, retry).toInt(),
            policy.maxDelay.inMicroseconds,
          ),
        );
        final delay = policy.backoff(retry, random);
        expect(delay, greaterThanOrEqualTo(full * 0.5));
        expect(delay, lessThanOrEqualTo(full));
      }
    });
  });
}

String _quote(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
