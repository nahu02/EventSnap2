import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../navigation/app_router.dart';
import '../providers/app_state_provider.dart';
import '../models/event_model.dart';
import '../models/calendar_event_properties.dart';
import '../services/services.dart';

/// Event details screen for viewing and editing calendar events
///
/// Displays a form with all event properties that can be edited by the user.
/// Includes validation, date/time pickers, and "Add to Calendar" functionality.
class EventDetailsScreen extends StatefulWidget {
  final dynamic initialEvent;

  const EventDetailsScreen({super.key, this.initialEvent});

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  
  // Form controllers
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _locationController;
  
  // Date and time values
  late DateTime _startDateTime;
  late DateTime _endDateTime;
  
  // State variables
  bool _isLoading = false;
  String? _errorMessage;
  List<String> _validationErrors = [];
  
  @override
  void initState() {
    super.initState();
    _initializeFromEvent();
  }
  
  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }
  
  /// Initialize form fields from the event data
  void _initializeFromEvent() {
    final appState = context.read<AppStateProvider>();
    final EventModel? event = widget.initialEvent ?? appState.currentEvent;
    
    if (event != null) {
      _titleController = TextEditingController(text: event.title);
      _descriptionController = TextEditingController(text: event.description ?? '');
      _locationController = TextEditingController(text: event.location ?? '');
      _startDateTime = event.startDateTime;
      _endDateTime = event.endDateTime;
    } else {
      // Default values for new event
      final now = DateTime.now();
      _titleController = TextEditingController();
      _descriptionController = TextEditingController();
      _locationController = TextEditingController();
      _startDateTime = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
      _endDateTime = _startDateTime.add(const Duration(hours: 1));
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
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isLoading ? null : _validateAndSave,
            tooltip: 'Save Event',
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  /// Build the main body content
  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Error display
            if (_errorMessage != null) _buildErrorCard(),
            
            // Validation errors
            if (_validationErrors.isNotEmpty) _buildValidationErrorsCard(),
            
            // Title field
            _buildTitleField(),
            const SizedBox(height: 16),
            
            // Description field
            _buildDescriptionField(),
            const SizedBox(height: 16),
            
            // Location field
            _buildLocationField(),
            const SizedBox(height: 24),
            
            // Date and time section
            _buildDateTimeSection(),
            const SizedBox(height: 24),
            
            // Event summary
            _buildEventSummary(),
          ],
        ),
      ),
    );
  }

  /// Build error message card
  Widget _buildErrorCard() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _errorMessage = null),
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ],
        ),
      ),
    );
  }

  /// Build validation errors card
  Widget _buildValidationErrorsCard() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Validation Errors',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._validationErrors.map((error) => Padding(
              padding: const EdgeInsets.only(left: 24.0, bottom: 4.0),
              child: Text(
                '• $error',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  /// Build title input field
  Widget _buildTitleField() {
    return TextFormField(
      controller: _titleController,
      decoration: const InputDecoration(
        labelText: 'Event Title *',
        hintText: 'Enter the event title',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.title),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Title is required';
        }
        return null;
      },
      textInputAction: TextInputAction.next,
      onChanged: (_) => _clearErrors(),
    );
  }

  /// Build description input field
  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      decoration: const InputDecoration(
        labelText: 'Description',
        hintText: 'Enter event description (optional)',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.description),
        alignLabelWithHint: true,
      ),
      maxLines: 3,
      textInputAction: TextInputAction.next,
      onChanged: (_) => _clearErrors(),
    );
  }

  /// Build location input field
  Widget _buildLocationField() {
    return TextFormField(
      controller: _locationController,
      decoration: const InputDecoration(
        labelText: 'Location',
        hintText: 'Enter event location (optional)',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.location_on),
      ),
      textInputAction: TextInputAction.done,
      onChanged: (_) => _clearErrors(),
    );
  }

  /// Build date and time section
  Widget _buildDateTimeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Date & Time',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            
            // Start date and time
            _buildDateTimeField(
              label: 'Start',
              dateTime: _startDateTime,
              onChanged: (newDateTime) {
                setState(() {
                  _startDateTime = newDateTime;
                  // Ensure end time is after start time
                  if (_endDateTime.isBefore(_startDateTime)) {
                    _endDateTime = _startDateTime.add(const Duration(hours: 1));
                  }
                });
                _clearErrors();
              },
            ),
            const SizedBox(height: 16),
            
            // End date and time
            _buildDateTimeField(
              label: 'End',
              dateTime: _endDateTime,
              onChanged: (newDateTime) {
                setState(() {
                  _endDateTime = newDateTime;
                });
                _clearErrors();
              },
            ),
            
            const SizedBox(height: 12),
            
            // Duration display
            _buildDurationDisplay(),
          ],
        ),
      ),
    );
  }

  /// Build date and time field
  Widget _buildDateTimeField({
    required String label,
    required DateTime dateTime,
    required ValueChanged<DateTime> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            '$label:',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () => _pickDateTime(dateTime, onChanged),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      DateFormat('MMM dd, yyyy - HH:mm').format(dateTime),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Build duration display
  Widget _buildDurationDisplay() {
    final duration = _endDateTime.difference(_startDateTime);
    final durationText = _formatDuration(duration);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'Duration: $durationText',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Build event summary card
  Widget _buildEventSummary() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Event Summary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _buildSummaryRow(
              icon: Icons.title,
              label: 'Title',
              value: _titleController.text.isNotEmpty 
                ? _titleController.text 
                : 'No title entered',
            ),
            if (_descriptionController.text.isNotEmpty)
              _buildSummaryRow(
                icon: Icons.description,
                label: 'Description',
                value: _descriptionController.text,
              ),
            if (_locationController.text.isNotEmpty)
              _buildSummaryRow(
                icon: Icons.location_on,
                label: 'Location',
                value: _locationController.text,
              ),
            _buildSummaryRow(
              icon: Icons.schedule,
              label: 'Duration',
              value: _formatDuration(_endDateTime.difference(_startDateTime)),
            ),
          ],
        ),
      ),
    );
  }

  /// Build summary row
  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// Build bottom navigation bar with action buttons
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : () => AppRouter.goBack(context),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _addToCalendar,
                icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.calendar_today),
                label: Text(_isLoading ? 'Adding...' : 'Add to Calendar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pick date and time
  Future<void> _pickDateTime(
    DateTime currentDateTime,
    ValueChanged<DateTime> onChanged,
  ) async {
    // Pick date
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: currentDateTime,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    
    if (pickedDate == null) return;
    
    // Pick time
    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentDateTime),
    );
    
    if (pickedTime == null) return;
    
    // Combine date and time
    final newDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    
    onChanged(newDateTime);
  }

  /// Format duration for display
  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays} day${duration.inDays > 1 ? 's' : ''}';
    } else if (duration.inHours > 0) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      if (minutes > 0) {
        return '${hours}h ${minutes}m';
      } else {
        return '$hours hour${hours > 1 ? 's' : ''}';
      }
    } else {
      return '${duration.inMinutes} minute${duration.inMinutes > 1 ? 's' : ''}';
    }
  }

  /// Validate and save the event
  void _validateAndSave() {
    _clearErrors();
    
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    // Create event model for validation
    try {
      final event = _createEventModel();
      final validationErrors = event.validate();
      
      if (validationErrors.isNotEmpty) {
        setState(() {
          _validationErrors = validationErrors;
        });
        return;
      }
      
      // Update app state with the validated event
      final appState = context.read<AppStateProvider>();
      appState.setCurrentEvent(event);
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event saved successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
    } catch (e) {
      setState(() {
        _errorMessage = 'Error creating event: $e';
      });
    }
  }

  /// Add event to calendar
  Future<void> _addToCalendar() async {
    _clearErrors();
    
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Create and validate event
      final event = _createEventModel();
      final validationErrors = event.validate();
      
      if (validationErrors.isNotEmpty) {
        setState(() {
          _validationErrors = validationErrors;
        });
        return;
      }
      
      // Convert to CalendarEventProperties
      final properties = CalendarEventProperties.fromEventModel(event);
      
      // Capture the app state provider before async operations
      final appState = context.read<AppStateProvider>();
      
      // Create iCalendar file
      final iCalendarCreator = ICalendarCreator();
      final filePath = await iCalendarCreator.createIcalFile(properties);
      
      // Share the file
      final success = await iCalendarCreator.shareIcalFile(filePath);
      
      if (success) {
        // Update app state
        appState.setCurrentEvent(event);
        
        // Show success message and navigate back
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Event added to calendar successfully!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          
          // Navigate back to home
          AppRouter.navigateToHome(context);
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to share event. Please try again.';
        });
      }
      
    } catch (e) {
      setState(() {
        _errorMessage = _getErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Create EventModel from form data
  EventModel _createEventModel() {
    return EventModel(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty 
        ? null 
        : _descriptionController.text.trim(),
      location: _locationController.text.trim().isEmpty 
        ? null 
        : _locationController.text.trim(),
      startDateTime: _startDateTime,
      endDateTime: _endDateTime,
    );
  }

  /// Clear all error states
  void _clearErrors() {
    if (_errorMessage != null || _validationErrors.isNotEmpty) {
      setState(() {
        _errorMessage = null;
        _validationErrors = [];
      });
    }
  }

  /// Get user-friendly error message
  String _getErrorMessage(Object error) {
    final errorString = error.toString();
    
    if (errorString.contains('file system') || errorString.contains('directory')) {
      return 'Unable to create calendar file. Please check storage permissions.';
    } else if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Network error. Please check your connection and try again.';
    } else if (errorString.contains('permission')) {
      return 'Permission denied. Please check app permissions.';
    } else {
      return 'An unexpected error occurred. Please try again.';
    }
  }
}
