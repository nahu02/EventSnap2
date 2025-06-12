import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';

// Project imports
import 'package:event_snap_2/models/settings.dart';
import 'package:event_snap_2/providers/app_state_provider.dart';
import 'package:event_snap_2/services/settings_service.dart';

// Screen imports
import 'package:event_snap_2/screens/home_screen.dart';
import 'package:event_snap_2/screens/settings_screen.dart';
import 'package:event_snap_2/screens/event_text_input_screen.dart';
import 'package:event_snap_2/screens/event_details_screen.dart';
import 'package:event_snap_2/models/event_model.dart';

// Mock class for SettingsService using mocktail
class MockSettingsService extends Mock implements SettingsService {}

// Fake class for Settings to be used with registerFallbackValue
class FakeSettings extends Fake implements Settings {}

void main() {
  // Register fallback values for mocktail
  setUpAll(() {
    registerFallbackValue(FakeSettings());
  });

  // Helper function to create a MaterialApp with a mock AppStateProvider
  Widget createTestableWidget({
    required Widget child,
    required AppStateProvider appStateProvider,
  }) {
    return ChangeNotifierProvider<AppStateProvider>.value(
      value: appStateProvider,
      child: MaterialApp(home: child),
    );
  }

  // Mock SettingsService for tests
  late MockSettingsService mockSettingsService;
  late AppStateProvider appStateProvider;

  setUp(() {
    mockSettingsService = MockSettingsService();
    // Default behavior for getSettings, can be overridden in specific tests
    when(
      () => mockSettingsService.getSettings(),
    ).thenAnswer((_) async => Settings.defaults());
    when(
      () => mockSettingsService.updateSettings(any()),
    ).thenAnswer((_) async {});
    when(() => mockSettingsService.clearSettings()).thenAnswer((_) async {});
    when(
      () => mockSettingsService.getSetting(any()),
    ).thenAnswer((_) async => null);
    when(
      () => mockSettingsService.setSetting(any(), any()),
    ).thenAnswer((_) async {});
    when(() => mockSettingsService.hasSettings()).thenAnswer((_) async => true);

    appStateProvider = AppStateProvider(settingsService: mockSettingsService);
  });

  group('Screen Rendering Tests', () {
    testWidgets('HomeScreen renders without errors', (
      WidgetTester tester,
    ) async {
      // Initialize AppStateProvider as HomeScreen expects settings to be loaded
      await appStateProvider.initialize();

      await tester.pumpWidget(
        createTestableWidget(
          child: const HomeScreen(),
          appStateProvider: appStateProvider,
        ),
      );
      await tester
          .pumpAndSettle(); // Wait for any async operations or animations

      expect(find.text('Welcome to EventSnap!'), findsOneWidget);
    });

    // Test for SettingsScreen
    testWidgets('SettingsScreen renders without errors', (
      WidgetTester tester,
    ) async {
      await appStateProvider.initialize();

      await tester.pumpWidget(
        createTestableWidget(
          child: const SettingsScreen(),
          appStateProvider: appStateProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
    });

    // Test for EventTextInputScreen
    testWidgets(
      'EventTextInputScreen renders, allows text input, and enables Create Event button',
      (tester) async {
        // Set a specific screen size for the test
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        // Ensure the test window size is reset after the test
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        when(
          () => mockSettingsService.getSettings(),
        ).thenAnswer((_) async => Settings(openAiApiKey: 'test_api_key'));
        await appStateProvider.initialize();

        expect(
          appStateProvider.isConfigured,
          isTrue,
          reason: "Provider should be configured.",
        );

        await tester.pumpWidget(
          createTestableWidget(
            child: const EventTextInputScreen(),
            appStateProvider: appStateProvider,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Create Event from Text'),
          findsOneWidget,
          reason: "AppBar title should be present.",
        );

        // Verify essential initial UI elements are present
        final textFieldFinder = find.byType(TextField);
        expect(
          textFieldFinder,
          findsOneWidget,
          reason: "TextField should be present.",
        );
        expect(
          find.byType(CheckboxListTile),
          findsOneWidget,
          reason: "CheckboxListTile should be present.",
        );
        final initialButtonFinder = find.byKey(const Key('create_event_button'));
        expect(
          initialButtonFinder,
          findsOneWidget,
          reason: "Create Event button should be present initially.",
        );

        // Enter text into the TextField
        const inputText = 'Meeting tomorrow at 2 PM';
        await tester.enterText(textFieldFinder, inputText);
        await tester.pumpAndSettle();

        final textFieldWidget = tester.widget<TextField>(textFieldFinder);
        expect(
          textFieldWidget.controller!.text,
          inputText,
          reason: "TextField should contain the entered text.",
        );

        // Verify the button is present, enabled, and has correct text
        final buttonFinder = find.byKey(const Key('create_event_button'));
        expect(
          buttonFinder,
          findsOneWidget,
          reason: "Create Event button should still be present.",
        );

        final buttonWidget = tester.widget<ElevatedButton>(buttonFinder);
        expect(
          buttonWidget.enabled,
          isTrue,
          reason: "Create Event button should be enabled after text input.",
        );

        expect(
          find.descendant(
            of: buttonFinder,
            matching: find.text('Create Event'),
          ),
          findsOneWidget,
          reason: "Button text should be 'Create Event'.",
        );
      },
    );

    // Test for EventDetailsScreen
    testWidgets('EventDetailsScreen renders without errors', (
      WidgetTester tester,
    ) async {
      final mockEvent = EventModel(
        title: 'Test Event Details',
        startDateTime: DateTime.now(),
        endDateTime: DateTime.now().add(const Duration(hours: 1)),
        description: 'Test description 2345',
        location: 'Test location',
      );
      appStateProvider.setCurrentEvent(mockEvent);

      await appStateProvider.initialize();

      await tester.pumpWidget(
        createTestableWidget(
          child: const EventDetailsScreen(),
          appStateProvider: appStateProvider,
        ),
      );
      await tester.pumpAndSettle();

      // Check for elements from the mockEvent
      expect(find.text('Test Event Details'), findsOneWidget);
      expect(find.text('Test description 2345'), findsOneWidget);
    });
  });
}
