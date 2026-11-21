import 'package:material_ui/material_ui.dart';

import '../models/event_model.dart';
import '../models/field_evidence.dart';
import 'review/evidence_line.dart';
import 'review/event_formatting.dart';

/// Editable form for one event, with the AI's per-field evidence.
///
/// Fields: title, all-day switch, start/end date + time (locale and 24-hour
/// aware), location and description. Under each field an [EvidenceLine]
/// explains where the value came from; once the user changes a field it reads
/// "Edited by you" (compared against [originalEvent]).
///
/// Changing the start moves the end by the same amount (the duration is
/// kept). Valid states are reported through [onChanged].
class EventForm extends StatefulWidget {
  const EventForm({
    super.key,
    required this.initialEvent,
    this.originalEvent,
    this.onChanged,
    this.onEditedFieldsChanged,
    this.onFieldFocused,
    this.onShowInSource,
    this.sourceText = '',
    this.hasImages = false,
  });

  /// Values the form starts with.
  final EventModel initialEvent;

  /// The AI suggestion: source of the evidence and baseline for "Edited by
  /// you". Defaults to [initialEvent].
  final EventModel? originalEvent;

  /// Called with the current event whenever the form holds a valid event.
  final ValueChanged<EventModel>? onChanged;

  /// Called when the set of fields that differ from [originalEvent] changes.
  final ValueChanged<Set<EventField>>? onEditedFieldsChanged;

  /// Called when a field gains focus or its evidence line is tapped.
  final ValueChanged<EventField>? onFieldFocused;

  /// Called by an evidence line's "Show in source" action.
  final ValueChanged<EventField>? onShowInSource;

  /// The original input text (evidence quotes are shown in its context).
  final String sourceText;

  /// Whether the input had images.
  final bool hasImages;

  @override
  EventFormState createState() => EventFormState();
}

class EventFormState extends State<EventForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _locationController;
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _descriptionFocus = FocusNode();
  final FocusNode _locationFocus = FocusNode();

  late DateTime _start;
  late DateTime _end;
  late bool _isAllDay;

  /// Timed start/end before switching to all-day (restored when switching
  /// back).
  (DateTime, DateTime)? _timedBeforeAllDay;

  Set<EventField> _reportedEdited = const {};

  EventModel get _original => widget.originalEvent ?? widget.initialEvent;

  @override
  void initState() {
    super.initState();
    final event = widget.initialEvent;
    _titleController = TextEditingController(text: event.title);
    _descriptionController = TextEditingController(
      text: event.description ?? '',
    );
    _locationController = TextEditingController(text: event.location ?? '');
    _start = event.startDateTime;
    _end = event.endDateTime;
    _isAllDay = event.isAllDay;
    _reportedEdited = editedFields;

    _titleController.addListener(_handleChanged);
    _descriptionController.addListener(_handleChanged);
    _locationController.addListener(_handleChanged);
    _titleFocus.addListener(() => _handleFocus(_titleFocus, EventField.title));
    _descriptionFocus.addListener(
      () => _handleFocus(_descriptionFocus, EventField.description),
    );
    _locationFocus.addListener(
      () => _handleFocus(_locationFocus, EventField.location),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    _locationFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Public API

  /// Start of the event as currently entered.
  DateTime get start => _start;

  /// End as currently entered (exclusive midnight for all-day events).
  DateTime get end => _end;

  /// Whether the event is currently all-day.
  bool get isAllDay => _isAllDay;

  /// Fields whose value differs from the AI suggestion ([originalEvent]).
  Set<EventField> get editedFields {
    final o = _original;
    final allDayChanged = _isAllDay != o.isAllDay;
    return {
      if (_titleController.text.trim() != o.title.trim()) EventField.title,
      if (_blankToNull(_descriptionController.text) !=
          _blankToNull(o.description))
        EventField.description,
      if (_blankToNull(_locationController.text) != _blankToNull(o.location))
        EventField.location,
      if (allDayChanged || _start != o.startDateTime) EventField.start,
      if (allDayChanged || _end != o.endDateTime) EventField.end,
    };
  }

  /// Validates the form, showing errors inline. Returns true when valid.
  bool validateForm() {
    final fieldsValid = _formKey.currentState?.validate() ?? false;
    return fieldsValid && _end.isAfter(_start);
  }

  /// The event as currently entered. Throws [ArgumentError] when the form is
  /// not valid (call [validateForm] first).
  EventModel getCurrentEventModel() {
    final initial = widget.initialEvent;
    return EventModel(
      id: initial.id,
      isAllDay: _isAllDay,
      evidence: _original.evidence,
      title: _titleController.text.trim(),
      description: _blankToNull(_descriptionController.text),
      location: _blankToNull(_locationController.text),
      startDateTime: _start,
      endDateTime: _end,
    );
  }

  /// Moves the start to [newStart] and the end by the same amount, keeping
  /// the duration. For all-day events only the date of [newStart] is used.
  void setStart(DateTime newStart) {
    setState(() {
      if (_isAllDay) {
        final day = DateTime(newStart.year, newStart.month, newStart.day);
        final shiftDays = _daysBetween(_start, day);
        _start = day;
        _end = DateTime(_end.year, _end.month, _end.day + shiftDays);
      } else {
        final delta = newStart.difference(_start);
        _start = newStart;
        _end = _end.add(delta);
      }
    });
    _handleChanged();
  }

  /// Sets the end (exclusive midnight for all-day events). The start is not
  /// moved; an end before the start is reported as an error.
  void setEnd(DateTime newEnd) {
    setState(() => _end = newEnd);
    _handleChanged();
  }

  /// Switches between an all-day and a timed event.
  ///
  /// Turning all-day on keeps the covered days; turning it off restores the
  /// previous times (or 09:00 with a one-hour duration).
  void setAllDay(bool value) {
    if (value == _isAllDay) return;
    setState(() {
      if (value) {
        _timedBeforeAllDay = (_start, _end);
        final startDay = DateTime(_start.year, _start.month, _start.day);
        var endDay = _isMidnight(_end)
            ? _end
            : DateTime(_end.year, _end.month, _end.day + 1);
        if (!endDay.isAfter(startDay)) {
          endDay = DateTime(startDay.year, startDay.month, startDay.day + 1);
        }
        _start = startDay;
        _end = endDay;
      } else {
        final previous = _timedBeforeAllDay;
        final startTime = previous?.$1 ?? DateTime(2000, 1, 1, 9);
        final previousDuration = previous?.$2.difference(previous.$1);
        final lastDay = DateTime(_end.year, _end.month, _end.day - 1);
        final newStart = DateTime(
          _start.year,
          _start.month,
          _start.day,
          startTime.hour,
          startTime.minute,
        );
        DateTime newEnd;
        if (_daysBetween(_start, lastDay) == 0) {
          final duration =
              previousDuration != null &&
                  previousDuration > Duration.zero &&
                  previousDuration < const Duration(days: 1)
              ? previousDuration
              : const Duration(hours: 1);
          newEnd = newStart.add(duration);
        } else {
          final endTime =
              previous?.$2 ?? newStart.add(const Duration(hours: 1));
          newEnd = DateTime(
            lastDay.year,
            lastDay.month,
            lastDay.day,
            endTime.hour,
            endTime.minute,
          );
        }
        if (!newEnd.isAfter(newStart)) {
          newEnd = newStart.add(const Duration(hours: 1));
        }
        _start = newStart;
        _end = newEnd;
      }
      _isAllDay = value;
    });
    _handleChanged();
  }

  // ---------------------------------------------------------------------------

  void _handleFocus(FocusNode node, EventField field) {
    if (node.hasFocus) widget.onFieldFocused?.call(field);
  }

  void _handleChanged() {
    if (!mounted) return;
    setState(() {});
    final edited = editedFields;
    if (!_sameSet(edited, _reportedEdited)) {
      _reportedEdited = edited;
      widget.onEditedFieldsChanged?.call(edited);
    }
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    if (_titleController.text.trim().isEmpty || !_end.isAfter(_start)) return;
    try {
      onChanged(getCurrentEventModel());
    } on ArgumentError {
      // Incomplete input; validateForm() reports it.
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    widget.onFieldFocused?.call(isStart ? EventField.start : EventField.end);
    final current = isStart
        ? _start
        : (_isAllDay ? DateTime(_end.year, _end.month, _end.day - 1) : _end);
    final first = DateTime(2000);
    final last = DateTime(2100, 12, 31);
    final initial = current.isBefore(first)
        ? first
        : current.isAfter(last)
        ? last
        : current;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: isStart ? 'Start date' : 'End date',
    );
    if (picked == null || !mounted) return;
    if (isStart) {
      setStart(
        DateTime(
          picked.year,
          picked.month,
          picked.day,
          _start.hour,
          _start.minute,
        ),
      );
    } else if (_isAllDay) {
      setEnd(DateTime(picked.year, picked.month, picked.day + 1));
    } else {
      setEnd(
        DateTime(picked.year, picked.month, picked.day, _end.hour, _end.minute),
      );
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    widget.onFieldFocused?.call(isStart ? EventField.start : EventField.end);
    final current = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: isStart ? 'Start time' : 'End time',
    );
    if (picked == null || !mounted) return;
    final value = DateTime(
      current.year,
      current.month,
      current.day,
      picked.hour,
      picked.minute,
    );
    if (isStart) {
      setStart(value);
    } else {
      setEnd(value);
    }
  }

  // ---------------------------------------------------------------------------
  // Build

  @override
  Widget build(BuildContext context) {
    final fmt = EventFormatter.of(context);
    final edited = editedFields;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('event_title_field'),
            controller: _titleController,
            focusNode: _titleFocus,
            decoration: const InputDecoration(
              labelText: 'Title',
              prefixIcon: Icon(Icons.title),
            ),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Add a title' : null,
          ),
          ..._evidence(EventField.title, edited, fmt),
          const SizedBox(height: 16),
          _buildWhen(context, fmt, edited),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('event_location_field'),
            controller: _locationController,
            focusNode: _locationFocus,
            decoration: const InputDecoration(
              labelText: 'Location',
              prefixIcon: Icon(Icons.place_outlined),
            ),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
          ),
          ..._evidence(EventField.location, edited, fmt),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('event_description_field'),
            controller: _descriptionController,
            focusNode: _descriptionFocus,
            decoration: const InputDecoration(
              labelText: 'Description',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            minLines: 1,
            maxLines: 6,
          ),
          ..._evidence(EventField.description, edited, fmt),
        ],
      ),
    );
  }

  Widget _buildWhen(
    BuildContext context,
    EventFormatter fmt,
    Set<EventField> edited,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final endBeforeStart = !_end.isAfter(_start);
    final lastDay = DateTime(_end.year, _end.month, _end.day - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.schedule_outlined, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'When',
                style: theme.textTheme.titleSmall?.copyWith(color: cs.primary),
              ),
            ),
            if (!endBeforeStart)
              Chip(
                key: const ValueKey('event_duration_chip'),
                avatar: const Icon(Icons.timelapse_outlined),
                label: Text(
                  fmt.duration(start: _start, end: _end, isAllDay: _isAllDay),
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        SwitchListTile(
          key: const ValueKey('event_all_day_switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('All day'),
          value: _isAllDay,
          onChanged: setAllDay,
        ),
        _DateTimeRow(
          label: 'Starts',
          dateText: fmt.date(_start),
          timeText: _isAllDay ? null : fmt.time(_start),
          dateKey: const ValueKey('event_start_date'),
          timeKey: const ValueKey('event_start_time'),
          dateSemantics: 'Start date',
          timeSemantics: 'Start time',
          onDate: () => _pickDate(isStart: true),
          onTime: () => _pickTime(isStart: true),
        ),
        ..._evidence(EventField.start, edited, fmt),
        const SizedBox(height: 12),
        _DateTimeRow(
          label: 'Ends',
          dateText: fmt.date(_isAllDay ? lastDay : _end),
          timeText: _isAllDay ? null : fmt.time(_end),
          dateKey: const ValueKey('event_end_date'),
          timeKey: const ValueKey('event_end_time'),
          dateSemantics: 'End date',
          timeSemantics: 'End time',
          errorText: endBeforeStart ? 'End must be after start' : null,
          onDate: () => _pickDate(isStart: false),
          onTime: () => _pickTime(isStart: false),
        ),
        ..._evidence(EventField.end, edited, fmt),
      ],
    );
  }

  List<Widget> _evidence(
    EventField field,
    Set<EventField> edited,
    EventFormatter fmt,
  ) {
    final evidence = _original.evidence[field];
    if (evidence == null) return const [];
    final isEdited = edited.contains(field);
    // Nothing to justify for an empty field the user did not touch.
    final hasValue = switch (field) {
      EventField.title => _titleController.text.trim().isNotEmpty,
      EventField.description => _descriptionController.text.trim().isNotEmpty,
      EventField.location => _locationController.text.trim().isNotEmpty,
      EventField.start || EventField.end => true,
    };
    if (!hasValue && !isEdited) return const [];

    final o = _original;
    final suggested = switch (field) {
      EventField.title => o.title,
      EventField.description => _blankToNull(o.description) ?? 'none',
      EventField.location => _blankToNull(o.location) ?? 'none',
      EventField.start => fmt.startValue(o),
      EventField.end => fmt.endValue(o),
    };
    final onShowInSource = widget.onShowInSource;
    return [
      const SizedBox(height: 4),
      EvidenceLine(
        key: ValueKey('evidence_line_${field.name}'),
        field: field,
        evidence: evidence,
        edited: isEdited,
        sourceText: widget.sourceText,
        hasImages: widget.hasImages,
        suggestedValue: suggested,
        onActivate: () => widget.onFieldFocused?.call(field),
        onShowInSource: onShowInSource == null
            ? null
            : () => onShowInSource(field),
      ),
    ];
  }

  // ---------------------------------------------------------------------------

  static String? _blankToNull(String? s) {
    final trimmed = s?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static bool _isMidnight(DateTime d) =>
      d.hour == 0 && d.minute == 0 && d.second == 0 && d.millisecond == 0;

  static int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  static bool _sameSet(Set<EventField> a, Set<EventField> b) =>
      a.length == b.length && a.containsAll(b);
}

/// "Starts" / "Ends" label above date and time buttons (wraps at large text
/// sizes and on narrow screens).
class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.dateText,
    required this.timeText,
    required this.dateKey,
    required this.timeKey,
    required this.dateSemantics,
    required this.timeSemantics,
    required this.onDate,
    required this.onTime,
    this.errorText,
  });

  final String label;
  final String dateText;
  final String? timeText;
  final Key dateKey;
  final Key timeKey;
  final String dateSemantics;
  final String timeSemantics;
  final VoidCallback onDate;
  final VoidCallback onTime;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasError = errorText != null;
    final style = hasError
        ? OutlinedButton.styleFrom(
            foregroundColor: cs.error,
            side: BorderSide(color: cs.error),
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: hasError ? cs.error : cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Semantics(
              label: dateSemantics,
              child: OutlinedButton.icon(
                key: dateKey,
                style: style,
                onPressed: onDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(dateText),
              ),
            ),
            if (timeText != null)
              Semantics(
                label: timeSemantics,
                child: OutlinedButton.icon(
                  key: timeKey,
                  style: style,
                  onPressed: onTime,
                  icon: const Icon(Icons.access_time, size: 18),
                  label: Text(timeText!),
                ),
              ),
          ],
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errorText!,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ),
      ],
    );
  }
}
