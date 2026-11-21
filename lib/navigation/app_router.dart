import 'package:material_ui/material_ui.dart';

import '../models/extraction.dart';
import '../screens/home_screen.dart';
import '../screens/review_screen.dart';
import '../screens/settings_screen.dart';

/// How the review screen was left.
enum ReviewOutcome {
  /// The events were handed to a calendar app.
  exported,

  /// The user went back without exporting.
  discarded,
}

/// Named routes (Navigator 1.0).
class AppRouter {
  static const home = '/', review = '/review', settings = '/settings';

  /// `review` expects an [ExtractionResult] as `RouteSettings.arguments`.
  static Route<dynamic>? generateRoute(RouteSettings s) {
    switch (s.name) {
      case home:
        return MaterialPageRoute<void>(
          builder: (_) => const HomeScreen(),
          settings: s,
        );
      case review:
        final result = s.arguments;
        if (result is! ExtractionResult) {
          return MaterialPageRoute<void>(
            builder: (_) => const _RouteNotFoundScreen(),
            settings: s,
          );
        }
        return MaterialPageRoute<ReviewOutcome>(
          builder: (_) => ReviewScreen(result: result),
          settings: s,
        );
      case settings:
        return MaterialPageRoute<void>(
          builder: (_) => const SettingsScreen(),
          settings: s,
        );
      default:
        return MaterialPageRoute<void>(
          builder: (_) => const _RouteNotFoundScreen(),
          settings: s,
        );
    }
  }

  /// Opens the review screen. Completes with the outcome, or null if the route
  /// was popped without one (treat as [ReviewOutcome.discarded]).
  static Future<ReviewOutcome?> openReview(
    BuildContext c,
    ExtractionResult result,
  ) {
    return Navigator.of(c).pushNamed<ReviewOutcome>(review, arguments: result);
  }

  static Future<void> openSettings(BuildContext c) async {
    await Navigator.of(c).pushNamed<void>(settings);
  }
}

/// Screen shown when a route is not found
class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text('Page not found', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'The requested page could not be found.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
