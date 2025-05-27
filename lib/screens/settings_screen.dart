import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../navigation/app_router.dart';

/// Placeholder screen for settings
///
/// This will be fully implemented in Step 11.
/// For now, provides basic structure, navigation, and theme toggle.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => AppRouter.goBack(context),
        ),
      ),
      body: Consumer<AppStateProvider>(
        builder: (context, appState, child) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Theme section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appearance',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        leading: const Icon(Icons.brightness_6),
                        title: const Text('Theme'),
                        subtitle: Text(_getThemeModeText(appState.themeMode)),
                        trailing: IconButton(
                          icon: const Icon(Icons.brightness_4),
                          onPressed: () => appState.toggleTheme(),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Configuration status
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configuration',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        leading: Icon(
                          appState.isConfigured
                              ? Icons.check_circle
                              : Icons.warning,
                          color: appState.isConfigured
                              ? Colors.green
                              : Colors.orange,
                        ),
                        title: Text(
                          appState.isConfigured
                              ? 'App Configured'
                              : 'Setup Required',
                        ),
                        subtitle: Text(
                          appState.isConfigured
                              ? 'API key is configured'
                              : 'OpenAI API key needed',
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Placeholder notice
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Icon(Icons.settings, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'Full Settings Implementation',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Complete settings interface will be implemented in Step 11.',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // About section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'About EventSnap',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      _buildFeatureItem(
                        context,
                        icon: Icons.psychology,
                        title: 'AI-Powered Extraction',
                        description:
                            'Advanced AI understands natural language and extracts event details.',
                      ),
                      _buildFeatureItem(
                        context,
                        icon: Icons.calendar_today,
                        title: 'Calendar Integration',
                        description:
                            'Generated events can be added to any calendar app.',
                      ),
                      _buildFeatureItem(
                        context,
                        icon: Icons.security,
                        title: 'Secure & Private',
                        description:
                            'Your API keys are encrypted and stored securely.',
                      ),
                      _buildFeatureItem(
                        context,
                        icon: Icons.speed,
                        title: 'Fast & Efficient',
                        description:
                            'Quick processing with smart caching for better performance.',
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getThemeModeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  /// Build individual feature item for About section
  Widget _buildFeatureItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0.0 : 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
