import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/event_text_input_screen.dart';
import '../screens/event_details_screen.dart';
import '../screens/settings_screen.dart';

/// Application routing configuration
///
/// Defines all named routes and their corresponding screens.
/// Uses Navigator 1.0 for simplicity and compatibility.
class AppRouter {
  // Route names
  static const String home = '/';
  static const String eventTextInput = '/event-text-input';
  static const String eventDetails = '/event-details';
  static const String settings = '/settings';

  /// Generate routes for the application
  static Route<dynamic>? generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );

      case eventTextInput:
        return MaterialPageRoute(
          builder: (_) => const EventTextInputScreen(),
          settings: settings,
        );

      case eventDetails:
        final args = settings.arguments;
        return MaterialPageRoute(
          builder: (_) => EventDetailsScreen(
            initialEvent:
                args as dynamic, // Will be EventModel when implemented
          ),
          settings: settings,
        );

      case AppRouter.settings:
        return MaterialPageRoute(
          builder: (_) => const SettingsScreen(),
          settings: settings,
        );

      default:
        return MaterialPageRoute(
          builder: (_) => const _RouteNotFoundScreen(),
          settings: settings,
        );
    }
  }

  /// Navigate to home screen
  static void navigateToHome(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(context, home, (route) => false);
  }

  /// Navigate to event text input screen
  static void navigateToEventTextInput(BuildContext context) {
    Navigator.pushNamed(context, eventTextInput);
  }

  /// Navigate to event details screen with optional event data
  static void navigateToEventDetails(BuildContext context, {dynamic event}) {
    Navigator.pushNamed(context, eventDetails, arguments: event);
  }

  /// Navigate to settings screen
  static void navigateToSettings(BuildContext context) {
    Navigator.pushNamed(context, settings);
  }

  /// Go back to previous screen
  static void goBack(BuildContext context) {
    Navigator.pop(context);
  }

  /// Replace current screen with new route
  static void replaceWith(
    BuildContext context,
    String routeName, {
    Object? arguments,
  }) {
    Navigator.pushReplacementNamed(context, routeName, arguments: arguments);
  }
}

/// Screen shown when a route is not found
class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page Not Found')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Page Not Found',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'The requested page could not be found.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
