import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a URL outside the app; returns false when nothing could handle it.
typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

/// Opens web links (API key pages, source code) in the browser.
abstract final class ExternalLinks {
  /// Replaceable in tests to observe launches without platform channels.
  @visibleForTesting
  static ExternalUrlLauncher launcher = _launchExternally;

  static Future<bool> _launchExternally(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// Opens [uri]; shows a snackbar when no app could open it.
  static Future<void> open(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    bool opened;
    try {
      opened = await launcher(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text("Couldn't open ${uri.host}${uri.path}"),
        ),
      );
    }
  }
}
