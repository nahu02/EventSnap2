import 'package:material_ui/material_ui.dart';

import 'layout.dart';

/// Bar for a screen's primary bottom action (docs/v3_plan.md §6.0).
///
/// Use as `Scaffold.bottomNavigationBar`. It stays above the on-screen
/// keyboard (it is padded by the keyboard's height), respects the system
/// navigation bar (`SafeArea`), limits its content to the page's max content
/// width and has no fixed height, so it grows with large text.
///
/// [showProgress] shows an indeterminate progress line along its top edge.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.child,
    this.showProgress = false,
  });

  final Widget child;
  final bool showProgress;

  /// Height reserved for the progress line (also present when hidden, so
  /// the bar does not jump).
  static const double progressHeight = 4;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Material(
        color: cs.surfaceContainer,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: progressHeight,
                child: showProgress
                    ? const LinearProgressIndicator(
                        minHeight: progressHeight,
                        semanticsLabel: 'Working',
                      )
                    : null,
              ),
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.s,
                    AppSpacing.page,
                    AppSpacing.m,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
