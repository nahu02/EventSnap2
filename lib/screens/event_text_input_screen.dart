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
  bool _hasText = false;
  String? _errorMessage;
  bool _parseMultipleEvents = false;

  @override
  void initState() {
    super.initState();
    // Set initial text if provided (e.g., from sharing)
    if (widget.initialText != null) {
      _textController.text = widget.initialText!;
      _hasText = widget.initialText!.trim().isNotEmpty;
    }

    // Listen to text changes to update button state
    _textController.addListener(_onTextChanged);
  }

  /// Update button state when text changes
  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset:
          false, // Prevent layout changes when keyboard appears
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
    return SafeArea(
      child: Column(
        children: [
          // Main scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Instructions
                  Card(
                    margin: const EdgeInsets.only(bottom: 8.0),
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
                            'Paste or type text describing one or more events.\nFor example:',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '• "Meeting with John tomorrow at 2 PM in the conference room"\n'
                            '• "Next Monday: Team lunch at 12, then project discussion from 3 to 4 PM."\n',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          Text(
                            'If your text contains multiple distinct events, make sure to check the checkbox below.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Text input
                  Text(
                    'Event Description',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _textController,
                    focusNode: _textFocusNode,
                    maxLines: 10,
                    enabled: !_isProcessing,
                    decoration: InputDecoration(
                      hintText: 'Describe your event in natural language...',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
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
                  // Checkbox for multiple events
                  CheckboxListTile(
                    title: const Text('The text contains multiple events'),
                    value: _parseMultipleEvents,
                    onChanged: (bool? value) {
                      if (!_isProcessing) {
                        // Prevent changing while processing
                        setState(() {
                          _parseMultipleEvents = value ?? false;
                        });
                      }
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero, // Remove default padding
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),

                  // Submit button
                  ElevatedButton.icon(
                    key: const Key('create_event_button'),
                    onPressed: _isProcessing || !_hasText
                        ? null
                        : () => _processEventText(appState),
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _isProcessing ? 'Processing...' : 'Create Event',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),

                  // Add some space at the bottom for better scrolling
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Footer
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
            ),
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

      if (_parseMultipleEvents) {
        // Process text for multiple events
        final List<CalendarEventProperties> propertiesList = await aiService
            .eventsToCalendarPropertiesAsync(text);

        if (propertiesList.isEmpty) {
          if (mounted) {
            setState(() {
              _errorMessage = 'No events found in the provided text.';
            });
          }
          return; // Early return if no events are found
        }

        // Convert to List<EventModel>
        final eventsList = propertiesList.map((p) => p.toEventModel()).toList();

        // Set current events in app state
        appState.setCurrentEvents(eventsList); // Used eventsList here

        // Navigate to event details screen
        if (mounted) {
          // No specific event to pass if multiple, EventDetailsScreen will use AppState
          AppRouter.navigateToEventDetails(context);
        }
      } else {
        // Process text for a single event
        final CalendarEventProperties properties = await aiService
            .eventToCalendarPropertiesAsync(text);

        // Convert to EventModel
        final event = properties.toEventModel();

        // Set current event in app state
        appState.setCurrentEvent(event);

        // Navigate to event details screen
        if (mounted) {
          AppRouter.navigateToEventDetails(context, event: event);
        }
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
