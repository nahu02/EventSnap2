import 'package:event_snap_2/models/event_model.dart';
import 'package:event_snap_2/navigation/app_router.dart';
import 'package:event_snap_2/providers/app_state_provider.dart';
import 'package:event_snap_2/services/icalendar_creator.dart';
import 'package:event_snap_2/widgets/event_form.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:event_snap_2/models/calendar_event_properties.dart'; // Added import

class EventDetailsScreen extends StatefulWidget {
  // If a single event is passed, it will be shown directly.
  // If multiple events are passed via AppStateProvider, they will be in ExpansionTiles.
  final EventModel? initialEvent;

  const EventDetailsScreen({super.key, this.initialEvent});

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  List<EventModel> _events = [];
  bool _isLoading = false;
  String? _overallErrorMessage;

  // Store GlobalKeys for each EventForm
  final Map<int, GlobalKey<EventFormState>> _formKeys = {};

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  void _loadEvents() {
    final appState = context.read<AppStateProvider>();
    List<EventModel> loadedEvents = [];

    if (widget.initialEvent != null) {
      // If a single event is passed via constructor, use it.
      loadedEvents = [widget.initialEvent!];
    } else if (appState.currentEvents.isNotEmpty) {
      // If AppStateProvider has multiple events, use them.
      loadedEvents = List<EventModel>.from(appState.currentEvents);
    } else if (appState.currentEvent != null &&
        appState.currentEvents.isEmpty) {
      // Fallback: if old currentEvent is somehow populated and new list isn\'t (should ideally not happen)
      loadedEvents = [appState.currentEvent!];
    } else {
      // Default placeholder events if nothing is provided (for development/testing)
      final now = DateTime.now();
      loadedEvents = [
        EventModel(
          title: 'Sample Event 1',
          description: 'This is a sample event.',
          location: 'Sample Location A',
          startDateTime: now.add(const Duration(days: 1, hours: 10)),
          endDateTime: now.add(const Duration(days: 1, hours: 11)),
        ),
        EventModel(
          title: 'Sample Event 2',
          description: 'Another sample event.',
          location: 'Sample Location B',
          startDateTime: now.add(const Duration(days: 2, hours: 14)),
          endDateTime: now.add(const Duration(days: 2, hours: 15)),
        ),
      ];
    }
    setState(() {
      _events = loadedEvents;
      _formKeys.clear(); // Clear existing keys before repopulating
      for (int i = 0; i < _events.length; i++) {
        _formKeys[i] = GlobalKey<EventFormState>();
      }
    });
  }

  Future<void> _handleShareAllEvents() async {
    if (_events.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No events to share.')));
      return;
    }

    setState(() => _isLoading = true);
    _overallErrorMessage = null;
    bool allFormsValid = true;
    final List<CalendarEventProperties> propertiesList = [];

    // Validate all forms and collect event data
    for (int i = 0; i < _events.length; i++) {
      final formState = _formKeys[i]?.currentState;
      if (formState != null) {
        if (formState.validateForm()) {
          final eventModel = formState.getCurrentEventModel();
          // Update the event in our local list to reflect changes
          _events[i] = eventModel;
          propertiesList.add(
            CalendarEventProperties(
              summary: eventModel.title,
              description: eventModel.description,
              location: eventModel.location,
              start: eventModel.startDateTime.toIso8601String(),
              end: eventModel.endDateTime.toIso8601String(),
            ),
          );
        } else {
          allFormsValid = false;
        }
      }
    }

    if (!allFormsValid) {
      setState(() {
        _isLoading = false;
        _overallErrorMessage = 'Please correct the errors in the event forms.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Some event forms have errors. Please review.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (propertiesList.isEmpty && _events.isNotEmpty) {
      setState(() {
        _isLoading = false;
        _overallErrorMessage =
            'Could not gather event data. Please check forms.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not process event data. Please review forms.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final creator = ICalendarCreator();
      final filePath = await creator.createIcalFileWithMultipleEvents(
        propertiesList,
      );
      final shared = await creator.shareIcalFile(filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              shared
                  ? 'All events shared successfully!'
                  : 'Failed to share events or no calendar apps found.',
            ),
            backgroundColor: shared ? Colors.green : Colors.amber,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _overallErrorMessage = 'Error sharing all events: \$e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing events: \$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => AppRouter.goBack(context),
        ),
        // Removed Share All button from AppBar actions
        // actions: [
        //   if (_events.length > 1)
        //     IconButton(
        //       icon: const Icon(Icons.share),
        //       tooltip: 'Share All Events',
        //       onPressed: _isLoading ? null : _handleShareAllEvents,
        //     ),
        // ],
      ),
      body: _buildBody(),
      // Add a bottom navigation bar for the "Add All to Calendar" button
      bottomNavigationBar: _events.length > 1 && !_isLoading
          ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: const Text('Add All to Calendar'),
                onPressed: _handleShareAllEvents,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            )
          : null, // Show nothing if only one event or loading
    );
  }

  Widget _buildBody() {
    // Adjusted isLoading check to only show loader if it's for the "Add All" operation
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_overallErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _overallErrorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_events.isEmpty) {
      return const Center(child: Text('No event details to display.'));
    }

    // If only one event, display it directly without ExpansionTile
    if (_events.length == 1) {
      // Ensure a key is assigned if not already
      _formKeys.putIfAbsent(0, () => GlobalKey<EventFormState>());
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: EventForm(
          key: _formKeys[0],
          initialEvent: _events.first,
          onChanged: (updatedEvent) {
            if (mounted) {
              setState(() {
                _events[0] = updatedEvent;
              });
            }
          },
        ),
      );
    }

    // If multiple events, display them in a ListView of ExpansionTiles
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _events.length,
      itemBuilder: (context, index) {
        // Ensure a key is assigned if not already
        _formKeys.putIfAbsent(index, () => GlobalKey<EventFormState>());
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0.0),
          child: ExpansionTile(
            maintainState: true, // Add this line
            leading: const Icon(
              Icons.event_note,
            ), // Or use ExpansionTileController for custom arrow
            title: Text(
              _events[index].title.isNotEmpty
                  ? _events[index].title
                  : 'Event ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(_events[index].formattedTimeRange),
            children: [
              EventForm(
                key: _formKeys[index],
                initialEvent:
                    _events[index], // Pass the event from the _events list
                onChanged: (updatedEvent) {
                  if (mounted) {
                    setState(() {
                      _events[index] = updatedEvent;
                    });
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
