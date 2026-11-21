import 'package:material_ui/material_ui.dart';

import '../services/ai/ai_exceptions.dart';
import 'inline_banner.dart';

/// The next step offered to the user for an AI error.
enum ErrorAction {
  /// Open settings (API key missing or rejected).
  openSettings('Open settings', Icons.settings_outlined),

  /// The configured model does not exist.
  chooseModel('Choose model', Icons.tune),

  /// The configured model cannot read the input (e.g. images).
  chooseVisionModel('Choose a vision model', Icons.image_search_outlined),

  /// Transient failure: run the same request again.
  retry('Retry', Icons.refresh);

  const ErrorAction(this.label, this.icon);

  /// Sentence-case button label.
  final String label;
  final IconData icon;

  /// Whether the action is handled by opening the settings screen.
  bool get opensSettings => this != ErrorAction.retry;
}

/// How an [AiErrorKind] is shown: icon, short title, friendly message and the
/// suggested [action] (null when there is nothing useful to offer).
@immutable
class ErrorPresentation {
  const ErrorPresentation({
    required this.kind,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final AiErrorKind kind;
  final IconData icon;
  final String title;

  /// Friendly, provider-agnostic sentence ([AiException.userMessageFor]).
  final String message;
  final ErrorAction? action;

  /// The presentation for [kind].
  factory ErrorPresentation.forKind(AiErrorKind kind) {
    final (icon, title, action) = switch (kind) {
      AiErrorKind.notConfigured => (
        Icons.key_outlined,
        'Finish setting up',
        ErrorAction.openSettings,
      ),
      AiErrorKind.auth => (
        Icons.key_off_outlined,
        'API key not accepted',
        ErrorAction.openSettings,
      ),
      AiErrorKind.rateLimited => (
        Icons.hourglass_empty,
        'Too many requests',
        ErrorAction.retry,
      ),
      AiErrorKind.quotaExceeded => (
        Icons.account_balance_wallet_outlined,
        'Out of credit',
        null,
      ),
      AiErrorKind.network => (
        Icons.wifi_off,
        'No connection',
        ErrorAction.retry,
      ),
      AiErrorKind.timeout => (
        Icons.timer_off_outlined,
        'Took too long',
        ErrorAction.retry,
      ),
      AiErrorKind.modelNotFound => (
        Icons.search_off,
        'Model not available',
        ErrorAction.chooseModel,
      ),
      AiErrorKind.unsupportedInput => (
        Icons.hide_image_outlined,
        "This model can't read that",
        ErrorAction.chooseVisionModel,
      ),
      AiErrorKind.invalidResponse => (
        Icons.help_outline,
        'Unexpected answer',
        ErrorAction.retry,
      ),
      AiErrorKind.server => (
        Icons.cloud_off_outlined,
        'Service problem',
        ErrorAction.retry,
      ),
      AiErrorKind.cancelled => (Icons.cancel_outlined, 'Cancelled', null),
      AiErrorKind.unknown => (
        Icons.error_outline,
        'Something went wrong',
        ErrorAction.retry,
      ),
    };
    return ErrorPresentation(
      kind: kind,
      icon: icon,
      title: title,
      message: AiException.userMessageFor(kind),
      action: action,
    );
  }

  /// The presentation for any error: [AiException]s by kind, everything else
  /// as [AiErrorKind.unknown].
  factory ErrorPresentation.forError(Object error) => ErrorPresentation.forKind(
    error is AiException ? error.kind : AiErrorKind.unknown,
  );
}

/// Inline error banner for an [ErrorPresentation] with its action button and
/// an optional dismiss button.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.presentation,
    this.onAction,
    this.onDismiss,
  });

  final ErrorPresentation presentation;

  /// Called with the presentation's action; the button is hidden when null.
  final ValueChanged<ErrorAction>? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final action = presentation.action;
    final onAction = this.onAction;
    return InlineBanner(
      tone: BannerTone.error,
      icon: presentation.icon,
      title: presentation.title,
      message: presentation.message,
      onDismiss: onDismiss,
      actions: [
        if (action != null && onAction != null)
          TextButton.icon(
            key: ValueKey('error_action_${action.name}'),
            icon: Icon(action.icon),
            label: Text(action.label),
            onPressed: () => onAction(action),
          ),
      ],
    );
  }
}
