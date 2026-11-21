/// Categories of AI failures. UI maps these to a message + next action.
enum AiErrorKind {
  notConfigured,
  auth,
  rateLimited,
  quotaExceeded,
  network,
  timeout,
  modelNotFound,
  unsupportedInput,
  invalidResponse,
  server,
  cancelled,
  unknown,
}

/// The only exception type thrown by the AI layer
/// (`CalendarEventInterpreter`, `ModelCatalog`).
class AiException implements Exception {
  final AiErrorKind kind;

  /// Technical detail for logs / debug mode. Not shown to users as-is.
  final String message;

  /// HTTP status code, when the failure came from an HTTP response.
  final int? statusCode;

  /// The underlying error, if any.
  final Object? cause;

  const AiException(this.kind, this.message, {this.statusCode, this.cause});

  /// Friendly, provider-agnostic sentence describing [kind].
  String get userMessage => userMessageFor(kind);

  /// Friendly, provider-agnostic sentence for [kind].
  static String userMessageFor(AiErrorKind kind) => switch (kind) {
    AiErrorKind.notConfigured =>
      'Add an API key and choose a model in Settings to get started.',
    AiErrorKind.auth => 'The API key was rejected. Check it in Settings.',
    AiErrorKind.rateLimited =>
      'Too many requests right now. Wait a moment and try again.',
    AiErrorKind.quotaExceeded =>
      'Your AI account has run out of credit or quota. Check your billing.',
    AiErrorKind.network =>
      'Could not reach the AI service. Check your internet connection.',
    AiErrorKind.timeout =>
      'The AI service took too long to respond. Try again.',
    AiErrorKind.modelNotFound =>
      'The selected model is not available. Choose another model in Settings.',
    AiErrorKind.unsupportedInput =>
      'The selected model cannot handle this input. Try a different model.',
    AiErrorKind.invalidResponse =>
      'The AI returned a response EventSnap could not understand. Try again.',
    AiErrorKind.server =>
      'The AI service had a problem. Try again in a moment.',
    AiErrorKind.cancelled => 'Cancelled.',
    AiErrorKind.unknown => 'Something went wrong. Try again.',
  };

  @override
  String toString() {
    final status = statusCode != null ? ', status: $statusCode' : '';
    return 'AiException(${kind.name}$status): $message';
  }
}
