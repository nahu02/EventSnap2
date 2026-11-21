import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/event_model.dart';
import '../models/extraction.dart';
import '../models/field_evidence.dart';
import '../navigation/app_router.dart';
import '../providers/app_state_provider.dart';
import '../services/calendar/calendar_creator.dart';
import '../widgets/event_form.dart';
import '../widgets/review/evidence_line.dart';
import '../widgets/review/review_event_card.dart';
import '../widgets/review/review_notices.dart';
import '../widgets/review/source_card.dart';

/// Review the extracted events, see why each value was chosen, edit them and
/// hand them to a calendar app.
///
/// Pops with [ReviewOutcome.exported] after a successful hand-off and with
/// [ReviewOutcome.discarded] when the user leaves (after confirming if there
/// are edits). System back without edits pops with `null`.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.result});

  final ExtractionResult result;

  /// Play Store search offered when no app can open calendar files.
  static final Uri calendarAppSearchUri = Uri.parse(
    'https://play.google.com/store/search?q=calendar&c=apps',
  );

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

/// Editing state of one event on the screen (survives remove → undo).
class _ReviewItem {
  _ReviewItem(this.original, {required this.expanded}) : current = original;

  /// The AI suggestion (evidence + "edited" baseline).
  final EventModel original;

  /// Latest valid values from the form.
  EventModel current;

  Set<EventField> edited = const {};
  bool expanded;
  final GlobalKey<EventFormState> formKey = GlobalKey<EventFormState>();

  String get id => original.id;

  /// Low-confidence fields with a value that the user has not changed.
  int get checkCount {
    var count = 0;
    for (final entry in original.evidence.entries) {
      if (entry.value.confidence != EvidenceConfidence.low) continue;
      if (edited.contains(entry.key)) continue;
      final hasValue = switch (entry.key) {
        EventField.description =>
          current.description?.trim().isNotEmpty ?? false,
        EventField.location => current.location?.trim().isNotEmpty ?? false,
        _ => true,
      };
      if (hasValue) count++;
    }
    return count;
  }
}

enum _ExportProblem { noCalendarApp, failed }

class _ReviewScreenState extends State<ReviewScreen> {
  late final List<_ReviewItem> _items;
  final GlobalKey<SourceCardState> _sourceKey = GlobalKey<SourceCardState>();

  /// Field whose evidence quote is highlighted in the source.
  ({String eventId, EventField field})? _focus;

  bool _exporting = false;
  _ExportProblem? _exportProblem;

  @override
  void initState() {
    super.initState();
    final events = widget.result.events;
    _items = [
      for (final event in events)
        _ReviewItem(event, expanded: events.length <= 3),
    ];
  }

  ExtractionInput get _input => widget.result.input;

  /// Whether leaving should be confirmed. Nothing is lost once every event
  /// was removed.
  bool get _hasEdits =>
      _items.isNotEmpty &&
      (_items.length < widget.result.events.length ||
          _items.any((item) => item.edited.isNotEmpty));

  SourceHighlight? get _highlight {
    final focus = _focus;
    if (focus == null) return null;
    for (final item in _items) {
      if (item.id != focus.eventId) continue;
      final quote = item.original.evidence[focus.field]?.quote;
      if (quote == null) return null;
      final title = item.current.title;
      return SourceHighlight(
        quote: quote,
        label: _items.length > 1
            ? '${focus.field.label.toLowerCase()} of “$title”'
            : focus.field.label.toLowerCase(),
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Actions

  void _focusField(_ReviewItem item, EventField field) {
    final next = (eventId: item.id, field: field);
    if (_focus == next) return;
    setState(() => _focus = next);
  }

  void _showInSource(_ReviewItem item, EventField field) {
    setState(() => _focus = (eventId: item.id, field: field));
    _sourceKey.currentState?.reveal();
  }

  void _remove(_ReviewItem item) {
    final index = _items.indexOf(item);
    if (index < 0) return;
    setState(() {
      _items.removeAt(index);
      if (_focus?.eventId == item.id) _focus = null;
      _exportProblem = null;
    });
    final title = item.current.title;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        persist: false,
        duration: const Duration(seconds: 5),
        content: Text('Removed “$title”'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted || _items.contains(item)) return;
            setState(() => _items.insert(math.min(index, _items.length), item));
          },
        ),
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('Your edits to these events will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );
    return discard ?? false;
  }

  Future<void> _leave() async {
    if (_hasEdits && !await _confirmDiscard()) return;
    if (!mounted) return;
    Navigator.of(context).pop(ReviewOutcome.discarded);
  }

  void _editText() => Navigator.of(context).pop(ReviewOutcome.discarded);

  Future<void> _export() async {
    if (_items.isEmpty || _exporting) return;
    FocusScope.of(context).unfocus();

    final invalid = <_ReviewItem>[];
    for (final item in _items) {
      final form = item.formKey.currentState;
      if (form != null && !form.validateForm()) invalid.add(item);
    }
    if (invalid.isNotEmpty) {
      setState(() {
        for (final item in invalid) {
          item.expanded = true;
        }
        _exportProblem = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = invalid.first.formKey.currentContext;
        if (target != null && target.mounted) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 300),
            alignment: 0.1,
          );
        }
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _items.length == 1
                ? 'Fix the highlighted fields first'
                : invalid.length == 1
                ? 'Fix the highlighted fields in 1 event first'
                : 'Fix the highlighted fields in ${invalid.length} events '
                      'first',
          ),
        ),
      );
      return;
    }

    final events = [
      for (final item in _items)
        item.formKey.currentState?.getCurrentEventModel() ?? item.current,
    ];
    final creator = context.read<CalendarCreator>();
    setState(() {
      _exporting = true;
      _exportProblem = null;
    });
    try {
      final path = await creator.createIcsFile(events);
      final opened = await creator.openInCalendarApp(path);
      if (!mounted) return;
      if (opened) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        Navigator.of(context).pop(ReviewOutcome.exported);
        return;
      }
      setState(() {
        _exporting = false;
        _exportProblem = _ExportProblem.noCalendarApp;
      });
    } catch (error, stackTrace) {
      debugPrint('Calendar export failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportProblem = _ExportProblem.failed;
      });
    }
  }

  Future<void> _findCalendarApp() async {
    try {
      final launched = await launchUrl(
        ReviewScreen.calendarAppSearchUri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;
    } catch (_) {
      // Fall through to the message below.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Could not open the app store'),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build

  bool _debugMode(BuildContext context) {
    try {
      return context.select<AppStateProvider, bool>(
        (state) => state.settings.debugMode,
      );
    } on ProviderNotFoundException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final count = _items.length;
    final scaler = MediaQuery.textScalerOf(context);
    final toolbarHeight = math.max(
      kToolbarHeight,
      scaler.scale(28) + scaler.scale(16) + 16,
    );

    return PopScope<Object?>(
      canPop: !_hasEdits,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: toolbarHeight,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _leave,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Review events'),
              Text(
                switch (count) {
                  0 => 'No events',
                  1 => '1 event',
                  _ => '$count events',
                },
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildContent(context),
              ),
            ),
          ),
        ),
        bottomNavigationBar: count == 0 ? null : _buildBottomBar(context),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context) {
    final result = widget.result;
    final sections = <Widget>[
      if (result.warnings.isNotEmpty)
        ReviewWarningsBanner(warnings: result.warnings),
      if (!_input.isEmpty)
        SourceCard(key: _sourceKey, input: _input, highlight: _highlight),
      if (_debugMode(context)) RawResponsePanel(result: result),
    ];

    if (_items.isEmpty) {
      final removedAll = result.events.isNotEmpty;
      sections.add(
        ReviewEmptyState(
          title: removedAll ? 'All events removed' : 'No events found',
          message: removedAll
              ? 'Undo to bring them back, or go back and edit your text.'
              : 'Try adding a date, a time or a place to your text.',
          onEditText: _editText,
        ),
      );
    } else {
      final single = _items.length == 1;
      for (final item in _items) {
        sections.add(
          ReviewEventCard(
            key: ValueKey('event_card_${item.id}'),
            event: item.current,
            expanded: single || item.expanded,
            checkCount: item.checkCount,
            edited: item.edited.isNotEmpty,
            onToggleExpanded: single
                ? null
                : () => setState(() => item.expanded = !item.expanded),
            onRemove: () => _remove(item),
            child: EventForm(
              key: item.formKey,
              initialEvent: item.current,
              originalEvent: item.original,
              sourceText: _input.text,
              hasImages: _input.hasImages,
              onChanged: (event) => setState(() => item.current = event),
              onEditedFieldsChanged: (fields) =>
                  setState(() => item.edited = fields),
              onFieldFocused: (field) => _focusField(item, field),
              onShowInSource: _input.hasText
                  ? (field) => _showInSource(item, field)
                  : null,
            ),
          ),
        );
      }
    }

    return [
      for (var i = 0; i < sections.length; i++) ...[
        if (i > 0) const SizedBox(height: 16),
        sections[i],
      ],
    ];
  }

  Widget _buildBottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = _items.length;
    final problem = _exportProblem;
    final label = count > 1
        ? 'Add $count events to calendar'
        : 'Add to calendar';

    return Padding(
      // Keep the primary action above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (problem != null) ...[
                      _buildProblem(problem),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      key: const ValueKey('review_export_button'),
                      onPressed: _exporting ? null : _export,
                      icon: _exporting
                          ? SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onSurface,
                              ),
                            )
                          : const Icon(Icons.event_available_outlined),
                      label: Text(label),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProblem(_ExportProblem problem) {
    void dismiss() => setState(() => _exportProblem = null);
    return switch (problem) {
      _ExportProblem.noCalendarApp => ExportProblemBanner(
        title: 'No calendar app found',
        message:
            'Install a calendar app, such as Google Calendar, then try again.',
        actionLabel: 'Get a calendar app',
        onAction: _findCalendarApp,
        onDismiss: dismiss,
      ),
      _ExportProblem.failed => ExportProblemBanner(
        title: 'Could not create the calendar file',
        message:
            'Something went wrong while preparing your events. '
            'Please try again.',
        onDismiss: dismiss,
      ),
    };
  }
}
