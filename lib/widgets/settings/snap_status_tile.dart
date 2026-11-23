import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../services/platform/snap_service.dart';

/// Settings › Sharing › "Screen snaps": whether the accessibility service
/// behind the Snap shortcuts is on, a button that opens the system
/// accessibility settings, and a hint on how to trigger a snap.
///
/// The status is re-read when the app resumes (the user comes back from the
/// system settings).
class SnapStatusTile extends StatefulWidget {
  const SnapStatusTile({super.key});

  static const statusKey = Key('snap_status_text');
  static const openSettingsKey = Key('snap_open_accessibility_button');

  @override
  State<SnapStatusTile> createState() => _SnapStatusTileState();
}

class _SnapStatusTileState extends State<SnapStatusTile>
    with WidgetsBindingObserver {
  SnapStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final status = await context.read<SnapService>().getStatus();
    if (mounted && status != _status) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = _status;
    final (String text, IconData icon, Color color) = switch (status) {
      null => ('Checking…', Icons.screenshot_monitor_outlined, cs.outline),
      SnapStatus(supported: false) => (
        'Needs Android 11 or newer',
        Icons.block_outlined,
        cs.outline,
      ),
      SnapStatus(enabled: true) => (
        'Accessibility service is on',
        Icons.check_circle_outline,
        cs.primary,
      ),
      _ => ('Accessibility service is off', Icons.error_outline, cs.tertiary),
    };
    final canOpen = status != null && status.supported;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.screenshot_outlined, color: cs.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Screen snaps', style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            text,
                            key: SnapStatusTile.statusKey,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Assign "Snap screen" or "Snap & crop" to a hardware key '
                      'with an app like SnapKey Map (run a supported app '
                      "shortcut), or use the launcher's long-press menu on "
                      'EventSnap.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (canOpen)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: SnapStatusTile.openSettingsKey,
                  onPressed: () => unawaited(
                    context.read<SnapService>().openAccessibilitySettings(),
                  ),
                  icon: const Icon(Icons.settings_accessibility),
                  label: const Text('Accessibility settings'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
