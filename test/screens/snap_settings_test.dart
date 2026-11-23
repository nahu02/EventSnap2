import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/screens/settings_screen.dart';
import 'package:event_snap_2/services/platform/snap_service.dart';
import 'package:event_snap_2/widgets/settings/snap_status_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/snap_fakes.dart';
import '../helpers/test_app.dart';
import 'settings_test_helpers.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'EventSnap',
      packageName: 'com.example.event_snap_2',
      version: '3.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<TestServices> pump(
    WidgetTester tester, {
    SnapStatus status = const SnapStatus(supported: true, enabled: false),
    Settings settings = const Settings(),
  }) async {
    usePhoneView(tester);
    final services = TestServices(
      settings: settings,
      snapService: FakeSnapService(status: status),
    );
    await services.initAppState();
    await tester.pumpWidget(services.wrap(const SettingsScreen()));
    await tester.pumpAndSettle();
    return services;
  }

  Finder statusText() => find.byKey(SnapStatusTile.statusKey);
  String statusLabel(WidgetTester tester) =>
      tester.widget<Text>(statusText()).data!;

  test('autoProcessSnaps defaults to off', () {
    expect(const Settings().autoProcessSnaps, isFalse);
  });

  testWidgets('auto-process screen snaps toggle persists', (tester) async {
    final services = await pump(tester);
    await tester.ensureVisible(find.text('Auto-process screen snaps'));
    expect(services.settingsService.settings.autoProcessSnaps, isFalse);

    await tester.tap(find.text('Auto-process screen snaps'));
    await tester.pumpAndSettle();
    expect(services.settingsService.settings.autoProcessSnaps, isTrue);

    await tester.tap(find.text('Auto-process screen snaps'));
    await tester.pumpAndSettle();
    expect(services.settingsService.settings.autoProcessSnaps, isFalse);
  });

  for (final (provider, name) in [
    (AiProvider.openai, 'OpenAI'),
    (AiProvider.opper, 'Opper'),
  ]) {
    testWidgets('the note names $name and warns about no confirmation', (
      tester,
    ) async {
      await pump(tester, settings: Settings(provider: provider));
      expect(
        find.text(
          'The screenshot is then sent to $name without confirmation',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'shows that the accessibility service is off and opens settings',
    (tester) async {
      final services = await pump(tester);
      await tester.ensureVisible(statusText());
      expect(statusLabel(tester), 'Accessibility service is off');

      await tester.tap(find.byKey(SnapStatusTile.openSettingsKey));
      await tester.pump();
      expect(services.snapService.openSettingsCalls, 1);
    },
  );

  testWidgets('shows that the accessibility service is on', (tester) async {
    await pump(
      tester,
      status: const SnapStatus(supported: true, enabled: true),
    );
    await tester.ensureVisible(statusText());
    expect(statusLabel(tester), 'Accessibility service is on');
    expect(find.byKey(SnapStatusTile.openSettingsKey), findsOneWidget);
  });

  testWidgets('old Android: explains and offers no button', (tester) async {
    await pump(tester, status: SnapStatus.unsupported);
    await tester.ensureVisible(statusText());
    expect(statusLabel(tester), 'Needs Android 11 or newer');
    expect(find.byKey(SnapStatusTile.openSettingsKey), findsNothing);
  });

  testWidgets('mentions SnapKey Map and the launcher shortcuts', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('SnapKey Map'), findsOneWidget);
    expect(find.textContaining('launcher'), findsOneWidget);
  });

  testWidgets('re-reads the status when the app resumes', (tester) async {
    final services = await pump(tester);
    await tester.ensureVisible(statusText());
    expect(statusLabel(tester), 'Accessibility service is off');

    services.snapService.status = const SnapStatus(
      supported: true,
      enabled: true,
    );
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(statusLabel(tester), 'Accessibility service is on');
  });
}
