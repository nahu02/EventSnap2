import 'package:event_snap_2/main.dart';
import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/providers/app_state_provider.dart';
import 'package:event_snap_2/screens/home_screen.dart';
import 'package:event_snap_2/widgets/event_form.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

void main() {
  Widget buildApp({
    InMemorySettingsService? settingsService,
    FakeAiServiceFactory? aiServiceFactory,
    FakeSharedContentSource? sharedContentSource,
  }) {
    return EventSnapApp(
      settingsService: settingsService ?? InMemorySettingsService(),
      aiServiceFactory: aiServiceFactory ?? FakeAiServiceFactory(),
      sharedContentSource: sharedContentSource ?? FakeSharedContentSource(),
      imageInputService: FakeImageInputService(),
      calendarCreator: FakeCalendarCreator(),
    );
  }

  Brightness homeBrightness(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(HomeScreen))).brightness;

  testWidgets('App launches without errors', (WidgetTester tester) async {
    final sharedContentSource = FakeSharedContentSource();
    await tester.pumpWidget(buildApp(sharedContentSource: sharedContentSource));
    await tester.pumpAndSettle();

    expect(find.text('EventSnap'), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Finish setting up'), findsOneWidget);
    expect(sharedContentSource.initialCalls, 1);
  });

  testWidgets('App launches with the default services', (tester) async {
    // Real SecureSettingsService over mocked storage plugins.
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const EventSnapApp());
    await tester.pumpAndSettle();
    expect(find.text('EventSnap'), findsOneWidget);
    expect(find.text('Find events'), findsOneWidget);
  });

  testWidgets('a share that launched the app is processed with the '
      'loaded settings', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    const stored = Settings(openAiApiKey: 'sk-test1234567890');
    final factory = FakeAiServiceFactory()
      ..interpreter.result = sampleResult(
        events: [sampleEvent(title: 'Concert')],
      );
    await tester.pumpWidget(
      buildApp(
        settingsService: InMemorySettingsService(stored),
        aiServiceFactory: factory,
        sharedContentSource: FakeSharedContentSource(
          initial: const SharedContent(text: 'Concert on Saturday at 8pm'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(factory.interpreter.calls.single.text, 'Concert on Saturday at 8pm');
    expect(factory.createdWith.single, stored);
    expect(find.text('Review events'), findsOneWidget);
  });

  testWidgets('theme follows settings.themeMode', (tester) async {
    await tester.pumpWidget(
      buildApp(
        settingsService: InMemorySettingsService(
          const Settings(themeMode: AppThemeMode.dark),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(homeBrightness(tester), Brightness.dark);

    final appState = Provider.of<AppStateProvider>(
      tester.element(find.byType(HomeScreen)),
      listen: false,
    );
    await appState.updateSettings(
      appState.settings.copyWith(themeMode: AppThemeMode.light),
    );
    await tester.pumpAndSettle();
    expect(homeBrightness(tester), Brightness.light);

    // System mode follows the platform brightness.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await appState.updateSettings(
      appState.settings.copyWith(themeMode: AppThemeMode.system),
    );
    await tester.pumpAndSettle();
    expect(homeBrightness(tester), Brightness.dark);
  });

  testWidgets('EventForm renders without errors', (WidgetTester tester) async {
    final initialEvent = EventModel(
      title: 'Test Event',
      startDateTime: DateTime.now(),
      endDateTime: DateTime.now().add(const Duration(hours: 1)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EventForm(initialEvent: initialEvent)),
      ),
    );

    expect(find.text('Test Event'), findsOneWidget);
  });
}
