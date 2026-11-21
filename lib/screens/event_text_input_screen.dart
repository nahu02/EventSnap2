import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/extraction.dart';
import '../navigation/app_router.dart';
import '../providers/app_state_provider.dart';
import '../services/ai/ai_cancellation_token.dart';
import '../services/ai/ai_exceptions.dart';
import '../services/ai/ai_service_factory.dart';

/// TEMPORARY text input screen (v2 flow). Workstream F replaces it with the
/// composer on the home screen and deletes this file.
///
/// Sends the text to the configured AI provider and opens the review screen
/// with the result.
class EventTextInputScreen extends StatefulWidget {
  final String? initialText;

  const EventTextInputScreen({super.key, this.initialText});

  @override
  State<EventTextInputScreen> createState() => _EventTextInputScreenState();
}

class _EventTextInputScreenState extends State<EventTextInputScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  AiCancellationToken? _cancellationToken;
  bool _hasText = false;
  String? _errorMessage;

  bool get _isProcessing => _cancellationToken != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _textController.text = widget.initialText!;
      _hasText = widget.initialText!.trim().isNotEmpty;
    }
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  void dispose() {
    _cancellationToken?.cancel();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Event from Text')),
      body: Consumer<AppStateProvider>(
        builder: (context, appState, child) {
          if (!appState.isConfigured) {
            return _buildConfigurationRequired(context, appState);
          }
          return _buildMainContent(context, appState);
        },
      ),
    );
  }

  Widget _buildConfigurationRequired(
    BuildContext context,
    AppStateProvider appState,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Setup Required',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please configure your ${appState.settings.provider.displayName} '
              'API key in settings before creating events.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => AppRouter.openSettings(context),
              icon: const Icon(Icons.settings),
              label: const Text('Go to Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, AppStateProvider appState) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Paste or type text describing one or more events, e.g. '
                    '"Meeting with John tomorrow at 2 PM in the conference room".',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _textController,
                    focusNode: _textFocusNode,
                    maxLines: 10,
                    minLines: 5,
                    enabled: !_isProcessing,
                    decoration: InputDecoration(
                      hintText: 'Describe your event in natural language...',
                      border: const OutlineInputBorder(),
                      errorText: _errorMessage,
                      errorMaxLines: 3,
                    ),
                    onChanged: (_) {
                      if (_errorMessage != null) {
                        setState(() => _errorMessage = null);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
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
                  ),
                  if (_isProcessing)
                    TextButton(
                      onPressed: () => _cancellationToken?.cancel(),
                      child: const Text('Cancel'),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Your text will be sent to ${appState.settings.provider.displayName} for processing.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processEventText(AppStateProvider appState) async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Please enter some text to process');
      return;
    }

    final token = AiCancellationToken();
    setState(() {
      _cancellationToken = token;
      _errorMessage = null;
    });

    try {
      final interpreter = context.read<AiServiceFactory>().createInterpreter(
        appState.settings,
      );
      final result = await interpreter.extractEvents(
        ExtractionInput(text: text),
        cancellationToken: token,
      );
      if (!mounted) return;
      setState(() => _cancellationToken = null);

      if (result.events.isEmpty) {
        setState(() {
          _errorMessage =
              'No events found — try adding a date or time to your text.';
        });
        return;
      }

      final outcome = await AppRouter.openReview(context, result);
      if (!mounted) return;
      if (outcome == ReviewOutcome.exported) {
        _textController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Events sent to your calendar app.')),
        );
      }
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _cancellationToken = null;
        if (e.kind != AiErrorKind.cancelled) _errorMessage = e.userMessage;
      });
    }
  }
}
