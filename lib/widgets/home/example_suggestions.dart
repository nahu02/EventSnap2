import 'package:material_ui/material_ui.dart';

/// Empty-state help under the composer: tappable example texts and a hint
/// that content can be shared into the app.
class ExampleSuggestions extends StatelessWidget {
  const ExampleSuggestions({super.key, required this.onSelected});

  /// Examples covering a time, a place, an all-day range and several events.
  static const examples = [
    'Dentist next Tuesday at 3:30pm',
    'Team lunch Friday 12:30 at Café Central',
    'Weekend trip to the lake, Saturday to Sunday',
    'Parents evening Thursday 6pm, school play next Wednesday at 5',
  ];

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Try an example',
          style: theme.textTheme.titleSmall?.copyWith(color: cs.primary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < examples.length; i++)
              ActionChip(
                key: ValueKey('example_chip_$i'),
                avatar: const Icon(Icons.auto_awesome_outlined),
                label: Text(
                  examples[i],
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () => onSelected(examples[i]),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.share_outlined, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tip: share text or a photo from any app to EventSnap to '
                'find its events.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
