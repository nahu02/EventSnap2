import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../services/shared_text_handler.dart';
import '../navigation/app_router.dart';

/// Home screen - main entry point of the application
///
/// Displays welcome message, navigation options, and app status.
/// Provides quick access to main features.
/// Handles shared text navigation when the app is launched via sharing.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasCheckedSharedText = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasCheckedSharedText) {
      _hasCheckedSharedText = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SharedTextHandler.instance.checkAndHandleSharedTextNavigation(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EventSnap'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => AppRouter.navigateToSettings(context),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Consumer<AppStateProvider>(
        builder: (context, appState, child) {
          // Show loading indicator during initialization
          if (appState.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // Show error if initialization failed
          if (appState.errorMessage != null) {
            return _buildErrorView(context, appState);
          }

          // Show main content
          return _buildMainContent(context, appState);
        },
      ),
    );
  }

  /// Build error view when something goes wrong
  Widget _buildErrorView(BuildContext context, AppStateProvider appState) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              appState.errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                appState.clearError();
                appState.initialize();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build main content of the home screen
  Widget _buildMainContent(BuildContext context, AppStateProvider appState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome section
          _buildWelcomeSection(context),
          const SizedBox(height: 24),

          // Configuration status
          _buildConfigurationStatus(context, appState),
          const SizedBox(height: 24),

          // Quick actions
          _buildQuickActions(context),
        ],
      ),
    );
  }

  /// Build welcome section
  Widget _buildWelcomeSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome to EventSnap!',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Convert any text into calendar events using AI. '
              'Simply paste your text and let EventSnap extract the event details.\n'
              'You can also share any text from other apps with EventSnap, to automagically create events.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Build configuration status section
  Widget _buildConfigurationStatus(
    BuildContext context,
    AppStateProvider appState,
  ) {
    final isConfigured = appState.isConfigured;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              isConfigured ? Icons.check_circle : Icons.warning,
              color: isConfigured ? Colors.green : Colors.orange,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConfigured ? 'Ready to Go!' : 'Setup Required',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isConfigured
                        ? 'Your app is properly configured and ready to use.'
                        : 'Please configure your OpenAI API key in settings.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (!isConfigured)
              ElevatedButton(
                onPressed: () => AppRouter.navigateToSettings(context),
                child: const Text('Setup'),
              ),
          ],
        ),
      ),
    );
  }

  /// Build quick actions section
  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.text_fields,
                title: 'From text',
                subtitle: 'Convert natural text to events',
                onTap: () => AppRouter.navigateToEventTextInput(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.settings,
                title: 'Settings',
                subtitle: 'Configure the app',
                onTap: () => AppRouter.navigateToSettings(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build individual action card
  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 180, // Fixed height for consistent sizing
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
