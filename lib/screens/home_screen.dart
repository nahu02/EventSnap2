import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/shared_content.dart';
import '../navigation/app_router.dart';
import '../providers/app_state_provider.dart';
import '../services/platform/shared_content_source.dart';
import 'event_text_input_screen.dart';

/// Home screen - main entry point of the application
///
/// Displays a welcome message, configuration status and quick actions.
/// Opens the text input screen when content is shared into the app.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<SharedContent>? _sharedSubscription;

  @override
  void initState() {
    super.initState();
    final source = context.read<SharedContentSource>();
    _sharedSubscription = source.sharedContentStream.listen(_openShared);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await source.takeInitialSharedContent();
      if (initial != null) _openShared(initial);
    });
  }

  @override
  void dispose() {
    _sharedSubscription?.cancel();
    super.dispose();
  }

  void _openShared(SharedContent content) {
    if (!mounted || content.isEmpty) return;
    _openTextInput(initialText: content.text);
  }

  void _openTextInput({String? initialText}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventTextInputScreen(initialText: initialText),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EventSnap'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => AppRouter.openSettings(context),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Consumer<AppStateProvider>(
        builder: (context, appState, child) {
          if (!appState.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }
          if (appState.errorMessage != null) {
            return _buildErrorView(context, appState);
          }
          return _buildMainContent(context, appState);
        },
      ),
    );
  }

  /// Build error view when something goes wrong
  Widget _buildErrorView(BuildContext context, AppStateProvider appState) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              appState.errorMessage!,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildWelcomeSection(context),
          const SizedBox(height: 16),
          _buildConfigurationStatus(context, appState),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _openTextInput(),
            icon: const Icon(Icons.text_fields),
            label: const Text('Create events from text'),
          ),
        ],
      ),
    );
  }

  /// Build welcome section
  Widget _buildWelcomeSection(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text(
              'Welcome to EventSnap!',
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Convert any text into calendar events using AI. '
              'Simply paste your text and let EventSnap extract the event details.\n'
              'You can also share any text from other apps with EventSnap, to automagically create events.',
              style: theme.textTheme.bodyLarge,
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
    final theme = Theme.of(context);
    final isConfigured = appState.isConfigured;
    final settings = appState.settings;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              isConfigured ? Icons.check_circle : Icons.warning,
              color: isConfigured
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConfigured ? 'Ready to go!' : 'Setup required',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isConfigured
                        ? '${settings.provider.displayName} · ${settings.activeModel}'
                        : 'Add your ${settings.provider.displayName} API key in settings.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (!isConfigured)
              TextButton(
                onPressed: () => AppRouter.openSettings(context),
                child: const Text('Setup'),
              ),
          ],
        ),
      ),
    );
  }
}
