import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/event_model.dart';
import '../models/extraction.dart';
import '../navigation/app_router.dart';
import '../services/calendar/calendar_creator.dart';
import '../widgets/event_form.dart';

/// Review the extracted events, edit them and hand them to a calendar app.
///
/// Pops with [ReviewOutcome.exported] after a successful hand-off and with
/// [ReviewOutcome.discarded] when the user leaves via the back button.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.result});

  final ExtractionResult result;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late List<EventModel> _events;
  bool _isLoading = false;
  String? _overallErrorMessage;

  // GlobalKeys for each EventForm
  final Map<int, GlobalKey<EventFormState>> _formKeys = {};

  @override
  void initState() {
    super.initState();
    _events = List<EventModel>.of(widget.result.events);
    for (var i = 0; i < _events.length; i++) {
      _formKeys[i] = GlobalKey<EventFormState>();
    }
  }

  Future<void> _handleShareAllEvents() async {
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    if (_events.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No events to add.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _overallErrorMessage = null;
    });

    var allFormsValid = true;
    for (var i = 0; i < _events.length; i++) {
      final formState = _formKeys[i]?.currentState;
      if (formState == null) continue;
      if (formState.validateForm()) {
        _events[i] = formState.getCurrentEventModel();
      } else {
        allFormsValid = false;
      }
    }

    if (!allFormsValid) {
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Some events have errors. Please review them.'),
        ),
      );
      return;
    }

    try {
      final creator = context.read<CalendarCreator>();
      final filePath = await creator.createIcsFile(_events);
      final opened = await creator.openInCalendarApp(filePath);
      if (!mounted) return;
      if (opened) {
        Navigator.of(context).pop(ReviewOutcome.exported);
        return;
      }
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No calendar app found. Install a calendar app and try again.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _overallErrorMessage = 'Could not add the events: $e';
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not add the events: $e'),
          backgroundColor: colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review events'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(ReviewOutcome.discarded),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _events.isNotEmpty && !_isLoading
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: FilledButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    _events.length > 1
                        ? 'Add ${_events.length} events to calendar'
                        : 'Add to calendar',
                  ),
                  onPressed: _handleShareAllEvents,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorScheme = Theme.of(context).colorScheme;
    final banners = <Widget>[
      if (_overallErrorMessage != null)
        _Banner(
          text: _overallErrorMessage!,
          background: colorScheme.errorContainer,
          foreground: colorScheme.onErrorContainer,
        ),
      for (final warning in widget.result.warnings)
        _Banner(
          text: warning,
          background: colorScheme.surfaceContainerHighest,
          foreground: colorScheme.onSurfaceVariant,
        ),
    ];

    if (_events.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...banners,
          const SizedBox(height: 32),
          const Center(child: Text('No events found.')),
        ],
      );
    }

    // A single event is shown directly, several in expandable cards.
    if (_events.length == 1) {
      return ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ...banners,
          EventForm(
            key: _formKeys[0],
            initialEvent: _events.first,
            onChanged: (updatedEvent) {
              if (mounted) setState(() => _events[0] = updatedEvent);
            },
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _events.length + banners.length,
      itemBuilder: (context, i) {
        if (i < banners.length) return banners[i];
        final index = i - banners.length;
        final event = _events[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: ExpansionTile(
            maintainState: true,
            leading: const Icon(Icons.event_note),
            title: Text(
              event.title.isNotEmpty ? event.title : 'Event ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(event.formattedTimeRange),
            children: [
              EventForm(
                key: _formKeys[index],
                initialEvent: event,
                onChanged: (updatedEvent) {
                  if (mounted) setState(() => _events[index] = updatedEvent);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: background,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, style: TextStyle(color: foreground)),
      ),
    );
  }
}
