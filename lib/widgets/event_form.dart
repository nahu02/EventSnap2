import 'package:event_snap_2/models/event_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EventForm extends StatefulWidget {
  final EventModel initialEvent;
  final void Function(EventModel)? onChanged; // Added onChanged callback

  const EventForm({
    super.key,
    required this.initialEvent,
    this.onChanged, // Added to constructor
  });

  @override
  EventFormState createState() => EventFormState();
}

class EventFormState extends State<EventForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _locationController;

  late DateTime _startDateTime;
  late DateTime _endDateTime;

  String? _errorMessage;
  List<String> _validationErrors = [];

  @override
  void initState() {
    super.initState();
    _initializeFromEvent(widget.initialEvent);

    // Add listeners to text controllers
    _titleController.addListener(_handleTextChange);
    _descriptionController.addListener(_handleTextChange);
    _locationController.addListener(_handleTextChange);
  }

  @override
  void dispose() {
    // Remove listeners and dispose controllers
    _titleController.removeListener(_handleTextChange);
    _descriptionController.removeListener(_handleTextChange);
    _locationController.removeListener(_handleTextChange);

    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _initializeFromEvent(EventModel event) {
    _titleController = TextEditingController(text: event.title);
    _descriptionController = TextEditingController(
      text: event.description ?? '',
    );
    _locationController = TextEditingController(text: event.location ?? '');
    _startDateTime = event.startDateTime;
    _endDateTime = event.endDateTime;
  }

  // Method to notify parent about changes
  void _notifyParentOfChanges() {
    if (widget.onChanged != null) {
      widget.onChanged!(getCurrentEventModel());
    }
  }

  // Handler for text controller changes
  void _handleTextChange() {
    _clearErrors(); // Clear errors on text change
    _notifyParentOfChanges(); // Notify parent
  }

  void _clearErrors() {
    if (mounted) {
      setState(() {
        _errorMessage = null;
        _validationErrors = [];
      });
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime initialDate = isStartDate ? _startDateTime : _endDateTime;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      if (mounted) {
        setState(() {
          if (isStartDate) {
            _startDateTime = DateTime(
              picked.year,
              picked.month,
              picked.day,
              _startDateTime.hour,
              _startDateTime.minute,
            );
            if (_endDateTime.isBefore(_startDateTime)) {
              _endDateTime = _startDateTime.add(const Duration(hours: 1));
            }
          } else {
            _endDateTime = DateTime(
              picked.year,
              picked.month,
              picked.day,
              _endDateTime.hour,
              _endDateTime.minute,
            );
            if (_endDateTime.isBefore(_startDateTime)) {
              _startDateTime = _endDateTime.subtract(const Duration(hours: 1));
            }
          }
          _clearErrors();
          _notifyParentOfChanges(); // Notify parent after date change
        });
      }
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStartDate) async {
    final DateTime initialTime = isStartDate ? _startDateTime : _endDateTime;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialTime),
    );
    if (picked != null) {
      if (mounted) {
        setState(() {
          if (isStartDate) {
            _startDateTime = DateTime(
              _startDateTime.year,
              _startDateTime.month,
              _startDateTime.day,
              picked.hour,
              picked.minute,
            );
            if (_endDateTime.isBefore(_startDateTime)) {
              _endDateTime = _startDateTime.add(const Duration(hours: 1));
            }
          } else {
            _endDateTime = DateTime(
              _endDateTime.year,
              _endDateTime.month,
              _endDateTime.day,
              picked.hour,
              picked.minute,
            );
            if (_endDateTime.isBefore(_startDateTime)) {
              _startDateTime = _endDateTime.subtract(const Duration(hours: 1));
            }
          }
          _clearErrors();
          _notifyParentOfChanges(); // Notify parent after time change
        });
      }
    }
  }

  String _formatDate(DateTime dateTime) {
    return DateFormat.yMMMd().format(dateTime);
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat.jm().format(dateTime);
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) return 'Invalid duration';
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    String text = '';
    if (days > 0) text += '${days}d ';
    if (hours > 0) text += '${hours}h ';
    if (minutes > 0) text += '${minutes}m';
    return text.trim().isEmpty ? '0m' : text.trim();
  }

  /// Validates the form and returns true if valid, false otherwise.
  /// Also updates _validationErrors if any.
  bool validateForm() {
    _clearErrors();
    final isValid = _formKey.currentState?.validate() ?? false;
    final List<String> currentValidationErrors = [];

    if (!isValid) {
      currentValidationErrors.add('Please correct the highlighted fields.');
    }
    if (_endDateTime.isBefore(_startDateTime)) {
      currentValidationErrors.add('End time cannot be before start time.');
    }

    if (currentValidationErrors.isNotEmpty) {
      if (mounted) {
        setState(() {
          _validationErrors = currentValidationErrors;
        });
      }
      return false;
    }
    return true;
  }

  /// Constructs an EventModel from the current form values.
  /// Call validateForm() before this to ensure data is valid.
  EventModel getCurrentEventModel() {
    return EventModel(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      location: _locationController.text.trim().isNotEmpty
          ? _locationController.text.trim()
          : null,
      startDateTime: _startDateTime,
      endDateTime: _endDateTime,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) _buildErrorCard(),
            if (_validationErrors.isNotEmpty) _buildValidationErrorsCard(),
            _buildTitleField(),
            const SizedBox(height: 16),
            _buildDescriptionField(),
            const SizedBox(height: 16),
            _buildLocationField(),
            const SizedBox(height: 24),
            _buildDateTimeSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 16),
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

  Widget _buildValidationErrorsCard() {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Please fix the following errors:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._validationErrors.map(
              (error) => Padding(
                padding: const EdgeInsets.only(left: 32.0, bottom: 4.0),
                child: Text(
                  '• $error',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          return 'Title cannot be empty.';
        }
        return null;
      },
      textInputAction: TextInputAction.next,
      // onChanged: (_) => _clearErrors(), // Removed, handled by listener
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      decoration: const InputDecoration(
        labelText: 'Description',
        hintText: 'Enter the event description (optional)',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.description),
      ),
      textInputAction: TextInputAction.next,
      maxLines: 3,
      // onChanged: (_) => _clearErrors(), // No longer needed if _handleTextChange calls _clearErrors
    );
  }

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
      // onChanged: (_) => _clearErrors(), // No longer needed if _handleTextChange calls _clearErrors
    );
  }

  Widget _buildDateTimeSection() {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date & Time', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _buildDateTimeField(
              label: 'Start',
              dateTime: _startDateTime,
              onDateChanged: () => _selectDate(context, true),
              onTimeChanged: () => _selectTime(context, true),
            ),
            const SizedBox(height: 16),
            _buildDateTimeField(
              label: 'End',
              dateTime: _endDateTime,
              onDateChanged: () => _selectDate(context, false),
              onTimeChanged: () => _selectTime(context, false),
            ),
            const SizedBox(height: 12),
            _buildDurationDisplay(),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeField({
    required String label,
    required DateTime dateTime,
    required VoidCallback onDateChanged,
    required VoidCallback onTimeChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text('$label:', style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: onDateChanged,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_formatDate(dateTime)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: onTimeChanged,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_formatTime(dateTime)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDurationDisplay() {
    final duration = _endDateTime.difference(_startDateTime);
    final durationText = _formatDuration(duration);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      alignment: Alignment.centerRight,
      child: Text(
        'Duration: $durationText',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
