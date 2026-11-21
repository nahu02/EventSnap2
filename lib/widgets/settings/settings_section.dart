import 'package:material_ui/material_ui.dart';

/// A titled group of settings: a `titleSmall` header in `primary` above an
/// outlined card holding [children].
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        Card.outlined(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// Tone of a [SettingsNotice], mapped to colour-scheme roles.
enum NoticeTone { info, warning, error, success }

/// Inline, non-blocking message (e.g. a capability warning).
class SettingsNotice extends StatelessWidget {
  const SettingsNotice({
    super.key,
    required this.message,
    this.tone = NoticeTone.warning,
    this.icon,
  });

  final String message;
  final NoticeTone tone;

  /// Defaults to an icon matching [tone].
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground, defaultIcon) = switch (tone) {
      NoticeTone.info => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.info_outline,
      ),
      NoticeTone.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.warning_amber_outlined,
      ),
      NoticeTone.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
      NoticeTone.success => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon ?? defaultIcon, size: 20, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One option of a [SettingsSegmentedButton].
class SettingsOption<T> {
  const SettingsOption(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Single-select [SegmentedButton] that stacks its segments vertically when
/// the labels do not fit side by side (narrow screens, large text scales).
class SettingsSegmentedButton<T> extends StatelessWidget {
  const SettingsSegmentedButton({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<SettingsOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  // M3 segment metrics: 12 px horizontal padding per side, an 18 px icon (or
  // the selected check mark) plus 8 px gap, 1 px borders and a small margin.
  static const double _segmentChrome = 2 * 12 + 18 + 8 + 2 + 8;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final showIcons = options.every((o) => o.icon != null);

    double widest = 0;
    for (final option in options) {
      final painter = TextPainter(
        text: TextSpan(text: option.label, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width + _segmentChrome;
      painter.dispose();
      if (width > widest) widest = width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final fits = widest * options.length <= constraints.maxWidth;
        return SegmentedButton<T>(
          direction: fits ? Axis.horizontal : Axis.vertical,
          showSelectedIcon: !showIcons,
          segments: [
            for (final option in options)
              ButtonSegment<T>(
                value: option.value,
                label: Text(option.label),
                icon: showIcons ? Icon(option.icon) : null,
              ),
          ],
          selected: {selected},
          onSelectionChanged: (values) {
            if (values.isNotEmpty) onChanged(values.first);
          },
        );
      },
    );
  }
}

/// Integer setting edited with a slider; the value is shown next to the
/// title. [onChanged] fires while dragging, [onChangeEnd] once released.
class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    required this.onChangeEnd,
    this.description,
    this.step = 1,
  });

  final String title;
  final String? description;
  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int value) format;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  int _snap(double raw) {
    final snapped = min + ((raw - min) / step).round() * step;
    return snapped.clamp(min, max);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(title, style: theme.textTheme.bodyLarge)),
              const SizedBox(width: 12),
              Text(
                format(clamped),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          Slider(
            value: clamped.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min) ~/ step,
            label: format(clamped),
            semanticFormatterCallback: (raw) => format(_snap(raw)),
            onChanged: (raw) => onChanged(_snap(raw)),
            onChangeEnd: (raw) => onChangeEnd(_snap(raw)),
          ),
        ],
      ),
    );
  }
}
