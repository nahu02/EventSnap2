import 'package:material_ui/material_ui.dart';

/// Meaning of an [InlineBanner], mapped to colour-scheme roles
/// (docs/v3_plan.md §6.0).
enum BannerTone {
  /// Neutral hint (surface container).
  info,

  /// Something worked (primary container).
  success,

  /// "Check this" (tertiary container).
  warning,

  /// Something failed (error container).
  error,
}

/// A `MaterialBanner`-like card for persistent, inline feedback: an icon, an
/// optional title, a message and optional actions.
///
/// Text wraps freely (safe at large text scales). Errors and warnings are
/// announced to screen readers as a live region.
class InlineBanner extends StatelessWidget {
  const InlineBanner({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.tone = BannerTone.info,
    this.actions = const [],
    this.onDismiss,
    this.dismissTooltip = 'Dismiss',
  });

  final IconData icon;
  final String? title;
  final String message;
  final BannerTone tone;

  /// Usually `TextButton`s; they are coloured to match the banner.
  final List<Widget> actions;

  /// Shows a close button when set.
  final VoidCallback? onDismiss;
  final String dismissTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (background, foreground, accent) = switch (tone) {
      BannerTone.info => (
        cs.surfaceContainerHigh,
        cs.onSurface,
        cs.onSurfaceVariant,
      ),
      BannerTone.success => (
        cs.primaryContainer,
        cs.onPrimaryContainer,
        cs.onPrimaryContainer,
      ),
      BannerTone.warning => (
        cs.tertiaryContainer,
        cs.onTertiaryContainer,
        cs.onTertiaryContainer,
      ),
      BannerTone.error => (
        cs.errorContainer,
        cs.onErrorContainer,
        cs.onErrorContainer,
      ),
    };

    final title = this.title;
    final onDismiss = this.onDismiss;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
            if (onDismiss != null)
              // Pull the 48 px button into the card's padding so the close
              // icon lines up with the text.
              Transform.translate(
                offset: const Offset(8, -12),
                child: IconButton(
                  icon: const Icon(Icons.close),
                  color: foreground,
                  tooltip: dismissTooltip,
                  onPressed: onDismiss,
                ),
              ),
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 4),
          TextButtonTheme(
            data: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: foreground),
            ),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OverflowBar(
                spacing: 8,
                overflowAlignment: OverflowBarAlignment.end,
                children: actions,
              ),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      container: true,
      liveRegion: tone == BannerTone.error || tone == BannerTone.warning,
      child: Card.filled(
        margin: EdgeInsets.zero,
        color: background,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            onDismiss != null ? 8 : 16,
            actions.isNotEmpty ? 8 : 16,
          ),
          child: content,
        ),
      ),
    );
  }
}
