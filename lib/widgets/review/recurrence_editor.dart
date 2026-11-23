import 'package:material_ui/material_ui.dart';

import '../../models/recurrence.dart';
import 'event_formatting.dart';

/// Result of [showRecurrenceEditor]: [rule] is `null` for "Does not repeat".
/// (The sheet itself returns `null` when dismissed, so "no repeat" and
/// "cancelled" stay distinguishable.)
class RecurrenceEditResult {
  const RecurrenceEditResult(this.rule);

  final RecurrenceRule? rule;
}

/// Ordinal (1..4, or -1 for the last) of [date]'s weekday within its month.
int weekdayOrdinalOf(DateTime date) {
  final n = (date.day - 1) ~/ 7 + 1;
  return n >= 5 ? -1 : n;
}

/// Shows the repeat editor as a modal bottom sheet for an event starting at
/// [start]. Resolves to `null` when dismissed without applying.
Future<RecurrenceEditResult?> showRecurrenceEditor(
  BuildContext context, {
  required RecurrenceRule? rule,
  required DateTime start,
}) {
  return showModalBottomSheet<RecurrenceEditResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => RecurrenceEditor(initial: rule, start: start),
  );
}

enum _End { never, until, count }

/// The content of the repeat editor sheet: frequency, "Every N", weekdays,
/// monthly mode and the end condition. "Done" pops a [RecurrenceEditResult].
class RecurrenceEditor extends StatefulWidget {
  const RecurrenceEditor({
    super.key,
    required this.initial,
    required this.start,
  });

  final RecurrenceRule? initial;
  final DateTime start;

  @override
  State<RecurrenceEditor> createState() => _RecurrenceEditorState();
}

class _RecurrenceEditorState extends State<RecurrenceEditor> {
  RecurrenceFrequency? _frequency;
  late int _interval;
  late Set<int> _weekdays;
  late bool _nth;
  late int _ordinalWeekday;
  late int _ordinal;
  late int _monthDay;
  late _End _end;
  late DateTime _until;
  late int _count;

  DateTime get _startDay =>
      DateTime(widget.start.year, widget.start.month, widget.start.day);

  @override
  void initState() {
    super.initState();
    final rule = widget.initial;
    final start = widget.start;
    _frequency = rule?.frequency;
    _interval = rule?.interval ?? 1;
    _weekdays = rule != null && rule.byWeekdays.isNotEmpty
        ? {...rule.byWeekdays}
        : {start.weekday};
    _nth = rule?.isNthWeekday ?? false;
    _ordinal = rule?.weekdayOrdinal ?? weekdayOrdinalOf(start);
    _ordinalWeekday = _nth && rule!.byWeekdays.isNotEmpty
        ? rule.byWeekdays.first
        : start.weekday;
    _monthDay = rule?.byMonthDay ?? start.day;
    _end = rule?.until != null
        ? _End.until
        : rule?.count != null
        ? _End.count
        : _End.never;
    _until = rule?.until ?? DateTime(start.year, start.month + 3, start.day);
    _count = rule?.count ?? 10;
  }

  RecurrenceRule? _build() {
    final frequency = _frequency;
    if (frequency == null) return null;
    final monthly = frequency == RecurrenceFrequency.monthly;
    return RecurrenceRule(
      frequency: frequency,
      interval: _interval,
      byWeekdays: frequency == RecurrenceFrequency.weekly
          ? _weekdays
          : monthly && _nth
          ? {_ordinalWeekday}
          : const {},
      byMonthDay: monthly && !_nth ? _monthDay : null,
      weekdayOrdinal: monthly && _nth ? _ordinal : null,
      count: _end == _End.count ? _count : null,
      until: _end == _End.until ? _until : null,
    );
  }

  void _setFrequency(RecurrenceFrequency? value) {
    setState(() => _frequency = value);
  }

  Future<void> _pickUntil() async {
    final first = _startDay;
    final picked = await showDatePicker(
      context: context,
      initialDate: _until.isBefore(first) ? first : _until,
      firstDate: first,
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Repeat until',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _until = picked;
      _end = _End.until;
    });
  }

  String _unit() {
    final plural = _interval != 1;
    return switch (_frequency) {
      RecurrenceFrequency.daily => plural ? 'days' : 'day',
      RecurrenceFrequency.weekly => plural ? 'weeks' : 'week',
      RecurrenceFrequency.monthly => plural ? 'months' : 'month',
      RecurrenceFrequency.yearly => plural ? 'years' : 'year',
      null => '',
    };
  }

  static String _frequencyLabel(RecurrenceFrequency? f) => switch (f) {
    null => 'Does not repeat',
    RecurrenceFrequency.daily => 'Daily',
    RecurrenceFrequency.weekly => 'Weekly',
    RecurrenceFrequency.monthly => 'Monthly',
    RecurrenceFrequency.yearly => 'Yearly',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fmt = EventFormatter.of(context);
    final frequency = _frequency;
    final nthOrdinal = weekdayOrdinalOf(widget.start);

    final children = <Widget>[
      Text('Repeats', style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        fmt.recurrence(_build(), widget.start),
        key: const ValueKey('recurrence_preview'),
        style: theme.textTheme.bodyMedium?.copyWith(color: cs.primary),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in <RecurrenceFrequency?>[
            null,
            ...RecurrenceFrequency.values,
          ])
            ChoiceChip(
              key: ValueKey('recurrence_freq_${f?.name ?? 'none'}'),
              label: Text(_frequencyLabel(f)),
              selected: _frequency == f,
              onSelected: (_) => _setFrequency(f),
            ),
        ],
      ),
    ];

    if (frequency != null) {
      children
        ..add(const SizedBox(height: 16))
        ..add(
          Row(
            children: [
              Text('Every', style: theme.textTheme.bodyLarge),
              IconButton(
                key: const ValueKey('recurrence_interval_minus'),
                tooltip: 'Fewer',
                onPressed: _interval > 1
                    ? () => setState(() => _interval--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '$_interval',
                key: const ValueKey('recurrence_interval_value'),
                style: theme.textTheme.titleMedium,
              ),
              IconButton(
                key: const ValueKey('recurrence_interval_plus'),
                tooltip: 'More',
                onPressed: _interval < 99
                    ? () => setState(() => _interval++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
              Flexible(child: Text(_unit(), style: theme.textTheme.bodyLarge)),
            ],
          ),
        );
    }

    if (frequency == RecurrenceFrequency.weekly) {
      children
        ..add(const SizedBox(height: 8))
        ..add(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  key: ValueKey('recurrence_weekday_$day'),
                  label: Text(fmt.weekdayShort(day)),
                  selected: _weekdays.contains(day),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _weekdays = {..._weekdays, day};
                    } else if (_weekdays.length > 1) {
                      _weekdays = {..._weekdays}..remove(day);
                    }
                  }),
                ),
            ],
          ),
        );
    }

    if (frequency == RecurrenceFrequency.monthly) {
      final nthLabel =
          'On the ${EventFormatter.ordinalWord(nthOrdinal)} '
          '${fmt.weekdayLong(widget.start.weekday)}';
      children
        ..add(const SizedBox(height: 8))
        ..add(
          SegmentedButton<bool>(
            key: const ValueKey('recurrence_monthly_mode'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                label: Text('On day ${widget.start.day}'),
              ),
              ButtonSegment(value: true, label: Text(nthLabel)),
            ],
            selected: {_nth},
            onSelectionChanged: (value) => setState(() {
              _nth = value.first;
              _monthDay = widget.start.day;
              _ordinal = nthOrdinal;
              _ordinalWeekday = widget.start.weekday;
            }),
          ),
        );
    }

    if (frequency != null) {
      children
        ..add(const SizedBox(height: 16))
        ..add(
          Text(
            'Ends',
            style: theme.textTheme.titleSmall?.copyWith(color: cs.primary),
          ),
        )
        ..add(const SizedBox(height: 8))
        ..add(
          SegmentedButton<_End>(
            key: const ValueKey('recurrence_end_mode'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _End.never, label: Text('Never')),
              ButtonSegment(value: _End.until, label: Text('On date')),
              ButtonSegment(value: _End.count, label: Text('After')),
            ],
            selected: {_end},
            onSelectionChanged: (value) => setState(() => _end = value.first),
          ),
        );
      if (_end == _End.until) {
        children
          ..add(const SizedBox(height: 8))
          ..add(
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const ValueKey('recurrence_until_button'),
                onPressed: _pickUntil,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(fmt.shortDate(_until)),
              ),
            ),
          );
      } else if (_end == _End.count) {
        children
          ..add(const SizedBox(height: 8))
          ..add(
            Row(
              children: [
                IconButton(
                  key: const ValueKey('recurrence_count_minus'),
                  tooltip: 'Fewer occurrences',
                  onPressed: _count > 1 ? () => setState(() => _count--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  '$_count',
                  key: const ValueKey('recurrence_count_value'),
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  key: const ValueKey('recurrence_count_plus'),
                  tooltip: 'More occurrences',
                  onPressed: _count < 999
                      ? () => setState(() => _count++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
                Flexible(
                  child: Text(
                    _count == 1 ? 'occurrence' : 'occurrences',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          );
      }
    }

    children
      ..add(const SizedBox(height: 24))
      ..add(
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('recurrence_done'),
              onPressed: () =>
                  Navigator.of(context).pop(RecurrenceEditResult(_build())),
              child: const Text('Done'),
            ),
          ],
        ),
      );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
