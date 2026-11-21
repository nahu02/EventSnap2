import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate, SocketException;
import 'dart:math';

import 'package:http/http.dart' as http;

import 'ai_cancellation_token.dart';
import 'ai_exceptions.dart';

/// Waits for [duration] (injectable so tests do not sleep).
typedef DelayFunction = Future<void> Function(Duration duration);

Future<void> _realDelay(Duration duration) => Future<void>.delayed(duration);

/// Exponential backoff with jitter for transient failures.
class RetryPolicy {
  const RetryPolicy({
    this.baseDelay = const Duration(milliseconds: 800),
    this.maxDelay = const Duration(seconds: 10),
    this.maxRetryAfter = const Duration(seconds: 30),
  });

  /// Delay before the first retry (doubled for every further retry).
  final Duration baseDelay;

  /// Upper bound for a computed backoff delay.
  final Duration maxDelay;

  /// A server-requested `Retry-After` longer than this is not waited for;
  /// the error is reported instead (the user can retry later).
  final Duration maxRetryAfter;

  /// Delay before retry number [retry] (0-based): `base * 2^retry`, capped at
  /// [maxDelay], scaled by a random factor in `[0.5, 1.0)` ("equal jitter").
  Duration backoff(int retry, Random random) {
    final exponential = baseDelay.inMicroseconds * pow(2, retry);
    final capped = min(exponential.toDouble(), maxDelay.inMicroseconds * 1.0);
    final jittered = capped * (0.5 + random.nextDouble() * 0.5);
    return Duration(microseconds: jittered.round());
  }
}

/// The parts of a Chat Completions response the app uses.
class ChatCompletion {
  const ChatCompletion({
    required this.content,
    required this.json,
    this.finishReason,
    this.refusal,
  });

  /// `choices[0].message.content` (text parts joined), or `null`.
  final String? content;

  /// `choices[0].finish_reason`, e.g. `stop` or `length`.
  final String? finishReason;

  /// `choices[0].message.refusal`, set when the model refused.
  final String? refusal;

  /// The whole decoded response body.
  final Map<String, dynamic> json;

  /// `usage` block, if any.
  Map<String, dynamic>? get usage {
    final usage = json['usage'];
    return usage is Map ? Map<String, dynamic>.from(usage) : null;
  }

  /// Cost in USD as reported by Opper (`usage.cost` or top-level `cost`).
  double? get cost {
    final value = usage?['cost'] ?? json['cost'];
    return value is num ? value.toDouble() : null;
  }
}

/// Minimal OpenAI-compatible HTTP client (`package:http`): bearer auth,
/// per-attempt timeout, cooperative cancellation, retries with exponential
/// backoff + jitter for network errors, timeouts, 429 (honouring
/// `Retry-After`) and 5xx, and HTTP status/body → [AiErrorKind] mapping.
///
/// Every failure surfaces as an [AiException].
class OpenAiCompatibleClient {
  OpenAiCompatibleClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
    this.maxRetries = 2,
    this.retryPolicy = const RetryPolicy(),
    DelayFunction? delay,
    Random? random,
    DateTime Function()? clock,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _delay = delay ?? _realDelay,
       _random = random ?? Random(),
       _clock = clock ?? DateTime.now;

  final http.Client _httpClient;
  final bool _ownsClient;
  final DelayFunction _delay;
  final Random _random;
  final DateTime Function() _clock;

  /// Timeout of one attempt (connect + full response).
  final Duration timeout;

  /// Retries after the first attempt for transient failures.
  final int maxRetries;

  final RetryPolicy retryPolicy;

  /// `POST {url}` with a Chat Completions [body].
  Future<ChatCompletion> createChatCompletion({
    required Uri url,
    required String apiKey,
    required Map<String, dynamic> body,
    AiCancellationToken? cancellationToken,
  }) async {
    final decoded = await sendJson(
      'POST',
      url,
      apiKey: apiKey,
      body: body,
      cancellationToken: cancellationToken,
    );
    if (decoded is! Map) {
      throw AiException(
        AiErrorKind.invalidResponse,
        'Chat completion response is not a JSON object',
      );
    }
    final json = Map<String, dynamic>.from(decoded);
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) {
      final error = json['error'];
      if (error != null) {
        throw mapHttpError(statusCode: 200, body: jsonEncode(json), url: url);
      }
      throw const AiException(
        AiErrorKind.invalidResponse,
        'Chat completion response has no choices',
      );
    }
    final choice = choices.first;
    final message = choice is Map ? choice['message'] : null;
    return ChatCompletion(
      content: message is Map ? _contentText(message['content']) : null,
      refusal: message is Map && message['refusal'] is String
          ? message['refusal'] as String
          : null,
      finishReason: choice is Map ? choice['finish_reason'] as String? : null,
      json: json,
    );
  }

  /// `GET {url}` returning decoded JSON.
  Future<Object?> getJson(
    Uri url, {
    String? apiKey,
    AiCancellationToken? cancellationToken,
  }) => sendJson(
    'GET',
    url,
    apiKey: apiKey,
    cancellationToken: cancellationToken,
  );

  /// Sends a JSON request with retries and returns the decoded JSON body of a
  /// 2xx response. Throws [AiException] otherwise.
  Future<Object?> sendJson(
    String method,
    Uri url, {
    String? apiKey,
    Map<String, dynamic>? body,
    AiCancellationToken? cancellationToken,
  }) async {
    final encodedBody = body == null ? null : jsonEncode(body);
    for (var attempt = 0; ; attempt++) {
      cancellationToken?.throwIfCancelled();
      AiException failure;
      Duration? retryAfter;
      try {
        final response = await _sendOnce(
          method,
          url,
          apiKey: apiKey,
          body: encodedBody,
          cancellationToken: cancellationToken,
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return _decode(response.body, url);
        }
        failure = mapHttpError(
          statusCode: response.statusCode,
          body: response.body,
          url: url,
        );
        retryAfter = parseRetryAfter(response.headers, now: _clock());
      } on AiException catch (e) {
        if (e.kind == AiErrorKind.cancelled) rethrow;
        failure = e;
      }

      if (!isRetryable(failure.kind) || attempt >= maxRetries) throw failure;
      if (retryAfter != null && retryAfter > retryPolicy.maxRetryAfter) {
        throw failure;
      }
      final wait = retryAfter ?? retryPolicy.backoff(attempt, _random);
      await _wait(wait, cancellationToken);
    }
  }

  /// Closes the underlying HTTP client if this instance created it.
  void close() {
    if (_ownsClient) _httpClient.close();
  }

  /// Kinds worth retrying automatically.
  static bool isRetryable(AiErrorKind kind) =>
      kind == AiErrorKind.network ||
      kind == AiErrorKind.timeout ||
      kind == AiErrorKind.rateLimited ||
      kind == AiErrorKind.server;

  Future<void> _wait(Duration duration, AiCancellationToken? token) async {
    if (token == null) return _delay(duration);
    await Future.any([_delay(duration), token.whenCancelled]);
    token.throwIfCancelled();
  }

  Future<_RawResponse> _sendOnce(
    String method,
    Uri url, {
    String? apiKey,
    String? body,
    AiCancellationToken? cancellationToken,
  }) async {
    final abort = Completer<void>();
    void triggerAbort() {
      if (!abort.isCompleted) abort.complete();
    }

    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      triggerAbort();
    });
    cancellationToken?.whenCancelled.then((_) => triggerAbort());

    final request = http.AbortableRequest(
      method,
      url,
      abortTrigger: abort.future,
    );
    request.headers['Accept'] = 'application/json';
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = utf8.encode(body);
    }

    Future<_RawResponse> send() async {
      final streamed = await _httpClient.send(request);
      final bytes = await streamed.stream.toBytes();
      return _RawResponse(
        streamed.statusCode,
        utf8.decode(bytes, allowMalformed: true),
        streamed.headers,
      );
    }

    AiException aborted(Object? cause) {
      if (cancellationToken?.isCancelled ?? false) {
        return AiException(
          AiErrorKind.cancelled,
          'Request was cancelled',
          cause: cause,
        );
      }
      if (timedOut) {
        return AiException(
          AiErrorKind.timeout,
          'No response from ${url.host} within ${timeout.inSeconds}s',
          cause: cause,
        );
      }
      return AiException(
        AiErrorKind.network,
        'Request to ${url.host} was aborted',
        cause: cause,
      );
    }

    try {
      // Racing with the abort trigger also covers clients that ignore it.
      return await Future.any([
        send(),
        abort.future.then<_RawResponse>((_) => throw const _Aborted()),
      ]);
    } on _Aborted catch (e) {
      throw aborted(e);
    } on http.RequestAbortedException catch (e) {
      throw aborted(e);
    } on TimeoutException catch (e) {
      throw AiException(
        AiErrorKind.timeout,
        'Request to ${url.host} timed out',
        cause: e,
      );
    } on SocketException catch (e) {
      throw AiException(
        AiErrorKind.network,
        'Network error talking to ${url.host}: ${e.message}',
        cause: e,
      );
    } on http.ClientException catch (e) {
      if (abort.isCompleted) throw aborted(e);
      throw AiException(
        AiErrorKind.network,
        'Network error talking to ${url.host}: ${e.message}',
        cause: e,
      );
    } catch (e) {
      if (abort.isCompleted) throw aborted(e);
      throw AiException(
        AiErrorKind.network,
        'Request to ${url.host} failed: $e',
        cause: e,
      );
    } finally {
      timer.cancel();
    }
  }

  static Object? _decode(String body, Uri url) {
    try {
      return jsonDecode(body);
    } on FormatException catch (e) {
      throw AiException(
        AiErrorKind.invalidResponse,
        'Response from ${url.host} is not valid JSON: ${e.message}',
        cause: e,
      );
    }
  }

  static String? _contentText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final parts = [
        for (final part in content)
          if (part is Map && part['text'] is String) part['text'] as String,
      ];
      return parts.isEmpty ? null : parts.join();
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Error mapping

  /// Maps a non-2xx response (or a 2xx body carrying an `error`) to an
  /// [AiException].
  static AiException mapHttpError({
    required int statusCode,
    required String body,
    Uri? url,
  }) {
    final detail = errorDetail(body);
    final lower = '${detail.message} ${detail.code}'.toLowerCase();
    final kind = _kindFor(statusCode, lower);
    final where = url == null ? '' : ' from ${url.host}${url.path}';
    final code = detail.code.isEmpty ? '' : ' [${detail.code}]';
    return AiException(
      kind,
      'HTTP $statusCode$where: ${detail.message}$code',
      statusCode: statusCode == 200 ? null : statusCode,
    );
  }

  static AiErrorKind _kindFor(int status, String lower) {
    if (status == 401 || status == 403) return AiErrorKind.auth;
    if (status == 402) return AiErrorKind.quotaExceeded;
    if (status == 429) {
      return _mentionsQuota(lower)
          ? AiErrorKind.quotaExceeded
          : AiErrorKind.rateLimited;
    }
    if (status == 408) return AiErrorKind.timeout;
    if (status >= 500) return AiErrorKind.server;
    if (status == 404 || lower.contains('model_not_found')) {
      return AiErrorKind.modelNotFound;
    }
    if (status == 413) return AiErrorKind.unsupportedInput;
    if (_mentionsImage(lower) || _mentionsContextLength(lower)) {
      return AiErrorKind.unsupportedInput;
    }
    if (_mentionsMissingModel(lower)) return AiErrorKind.modelNotFound;
    if (_mentionsQuota(lower)) return AiErrorKind.quotaExceeded;
    if (lower.contains('invalid_api_key') ||
        lower.contains('incorrect api key')) {
      return AiErrorKind.auth;
    }
    return AiErrorKind.unknown;
  }

  static bool _mentionsQuota(String lower) =>
      lower.contains('quota') ||
      lower.contains('billing') ||
      lower.contains('insufficient') ||
      lower.contains('credit') ||
      lower.contains('budget') ||
      lower.contains('payment');

  static bool _mentionsMissingModel(String lower) =>
      lower.contains('unknown model') ||
      (lower.contains('model') &&
          (lower.contains('not found') ||
              lower.contains('does not exist') ||
              lower.contains('not exist') ||
              lower.contains('not available')));

  static bool _mentionsImage(String lower) =>
      lower.contains('image') || lower.contains('vision');

  static bool _mentionsContextLength(String lower) =>
      lower.contains('context length') ||
      lower.contains('context_length') ||
      lower.contains('maximum context') ||
      lower.contains('too many tokens');

  /// Extracts a readable message and an error code/type/param string from
  /// common error body shapes (`{"error":{"message":…}}`, `{"error":"…"}`,
  /// `{"message":…}`, `{"detail":…}`, plain text).
  static ({String message, String code}) errorDetail(String body) {
    String message = body.trim();
    var code = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          message = (error['message'] ?? error['detail'] ?? '').toString();
          code = [
            error['code'],
            error['type'],
            error['param'],
          ].whereType<Object>().join(' ');
        } else if (error is String) {
          message = error;
        } else if (decoded['message'] is String) {
          message = decoded['message'] as String;
        } else if (decoded['detail'] != null) {
          message = decoded['detail'].toString();
        }
        if (decoded['code'] != null) code = '$code ${decoded['code']}'.trim();
      }
    } on FormatException {
      // Plain-text body.
    }
    if (message.isEmpty) message = 'no details';
    if (message.length > 500) message = '${message.substring(0, 500)}…';
    return (message: message, code: code);
  }

  /// Parses `retry-after-ms` / `retry-after` (seconds or HTTP date).
  static Duration? parseRetryAfter(
    Map<String, String> headers, {
    DateTime? now,
  }) {
    String? header(String name) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == name) return entry.value.trim();
      }
      return null;
    }

    final ms = num.tryParse(header('retry-after-ms') ?? '');
    if (ms != null && ms >= 0) return Duration(milliseconds: ms.round());

    final value = header('retry-after');
    if (value == null || value.isEmpty) return null;
    final seconds = num.tryParse(value);
    if (seconds != null) {
      return seconds < 0
          ? Duration.zero
          : Duration(milliseconds: (seconds * 1000).round());
    }
    try {
      final date = HttpDate.parse(value);
      final diff = date.difference(now ?? DateTime.now());
      return diff.isNegative ? Duration.zero : diff;
    } catch (_) {
      return null;
    }
  }
}

class _RawResponse {
  const _RawResponse(this.statusCode, this.body, this.headers);
  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

class _Aborted implements Exception {
  const _Aborted();
}
