import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'themes/app_theme.dart';
import 'providers/app_state_provider.dart';
import 'services/settings_service.dart';
import 'navigation/app_router.dart';

void main() {
  runApp(const EventSnapApp());
}

/// Main application widget
///
/// Sets up the app with state management, theming, and navigation.
class EventSnapApp extends StatelessWidget {
  const EventSnapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Settings service
        Provider<SettingsService>(create: (_) => SecureSettingsService()),

        // App state provider
        ChangeNotifierProvider<AppStateProvider>(
          create: (context) =>
              AppStateProvider(settingsService: context.read<SettingsService>())
                ..initialize(), // Initialize app state on startup
        ),
      ],
      child: Consumer<AppStateProvider>(
        builder: (context, appState, child) {
          return MaterialApp(
            title: 'EventSnap',
            debugShowCheckedModeBanner: false,

            // Theme configuration
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: appState.themeMode,

            // Navigation configuration
            initialRoute: AppRouter.home,
            onGenerateRoute: AppRouter.generateRoute,

            // Error handling
            builder: (context, child) {
              // Handle any global errors or loading states here if needed
              return child ?? const SizedBox.shrink();
            },
          );
        },
      ),
    );
  }
}
