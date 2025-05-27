import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../navigation/app_router.dart';
import '../providers/app_state_provider.dart';
import '../services/services.dart';
import '../models/calendar_event_properties.dart';

/// Screen for inputting event text and processing it with AI
///
/// Allows users to enter natural language text describing an event,
/// processes it through the OpenAI service, and navigates to the event details screen.
class EventTextInputScreen extends StatefulWidget {
  final String? initialText;

  const EventTextInputScreen({super.key, this.initialText});

  @override
  State<EventTextInputScreen> createState() => _EventTextInputScreenState();
}

class _EventTextInputScreenState extends State<EventTextInputScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Set initial text if provided (e.g., from sharing)
    if (widget.initialText != null) {
      _textController.text = widget.initialText!;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Event from Text'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => AppRouter.goBack(context),
        ),
      ),
      body: Consumer<AppStateProvider>(
        builder: (context, appState, child) {
          // Check if app is configured
          if (!appState.isConfigured) {
            return _buildConfigurationRequired(context);
          }

          return _buildMainContent(context, appState);
        },
      ),
    );
  }

  /// Build configuration required view
  Widget _buildConfigurationRequired(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'Setup Required',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please configure your OpenAI API key in settings before creating events.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => AppRouter.navigateToSettings(context),
              icon: const Icon(Icons.settings),
              label: const Text('Go to Settings'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build main content when app is configured
  Widget _buildMainContent(BuildContext context, AppStateProvider appState) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Instructions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'How it works',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Paste or type any text that describes an event. For example:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• "Meeting with John tomorrow at 2 PM in the conference room"\n'
                    '• "Dentist appointment next Friday at 10:30 AM"\n'
                    '• "Birthday party on Saturday from 6 to 10 PM at Sarah\'s house"',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Text input
          Text(
            'Event Description',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _textController,
            focusNode: _textFocusNode,
            maxLines: 6,
            enabled: !_isProcessing,
            decoration: InputDecoration(
              hintText: 'Describe your event in natural language...',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              errorText: _errorMessage,
            ),
            onChanged: (value) {
              // Clear error when user starts typing
              if (_errorMessage != null) {
                setState(() {
                  _errorMessage = null;
                });
              }
            },
          ),
          const SizedBox(height: 24),

          // Submit button
          ElevatedButton.icon(
            onPressed: _isProcessing || _textController.text.trim().isEmpty
                ? null
                : () => _processEventText(appState),
            icon: _isProcessing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_isProcessing ? 'Processing...' : 'Create Event'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),

          // Processing indicator
          if (_isProcessing) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('AI is analyzing your text...'),
                  ],
                ),
              ),
            ),
          ],

          const Spacer(),

          // Footer info
          if (!_isProcessing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                'Your text will be processed securely using OpenAI\'s API.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  /// Process the event text using AI service
  Future<void> _processEventText(AppStateProvider appState) async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter some text to process';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Create AI service with current settings
      final aiService = OpenAiCalendarEventInterpreter(appState.settings!);

      // Process the text
      final CalendarEventProperties properties =
          await aiService.eventToCalendarPropertiesAsync(text);

      // Convert to EventModel
      final event = properties.toEventModel();

      // Set current event in app state
      appState.setCurrentEvent(event);

      // Navigate to event details screen
      if (mounted) {
        AppRouter.navigateToEventDetails(context, event: event);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _getErrorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// Get user-friendly error message from exception
  String _getErrorMessage(Object error) {
    if (error.toString().contains('API key')) {
      return 'Invalid API key. Please check your settings.';
    } else if (error.toString().contains('network') ||
        error.toString().contains('timeout') ||
        error.toString().contains('connection')) {
      return 'Network error. Please check your connection and try again.';
    } else if (error.toString().contains('rate limit')) {
      return 'API rate limit reached. Please wait a moment and try again.';
    } else if (error.toString().contains('insufficient') ||
        error.toString().contains('quota')) {
      return 'API quota exceeded. Please check your OpenAI account.';
    } else {
      return 'Failed to process text. Please try again or check your input.';
    }
  }
}
