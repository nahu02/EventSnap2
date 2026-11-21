import 'dart:async';

import 'ai_exceptions.dart';

/// Cooperative cancellation for AI requests.
///
/// The UI creates a token per request and calls [cancel]; the AI layer checks
/// [isCancelled] / awaits [whenCancelled] and then throws
/// `AiException(AiErrorKind.cancelled)`.
class AiCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// Requests cancellation. Idempotent.
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _completer.future;

  /// Throws `AiException(AiErrorKind.cancelled)` if [cancel] was called.
  void throwIfCancelled() {
    if (isCancelled) {
      throw const AiException(AiErrorKind.cancelled, 'Request was cancelled');
    }
  }
}
