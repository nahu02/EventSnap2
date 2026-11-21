/// Widget test harness: registers fake services exactly like `main.dart`
/// registers the real ones (docs/v3_plan.md §4.3).
///
/// ```dart
/// final services = TestServices(settings: const Settings(openAiApiKey: 'sk-test'));
/// await services.initAppState();
/// await tester.pumpWidget(services.wrap(const HomeScreen()));
/// ```
library;

import 'package:event_snap_2/models/settings.dart';
import 'package:event_snap_2/navigation/app_router.dart';
import 'package:event_snap_2/providers/app_state_provider.dart';
import 'package:event_snap_2/services/ai/ai_service_factory.dart';
import 'package:event_snap_2/services/calendar/calendar_creator.dart';
import 'package:event_snap_2/services/platform/image_input_service.dart';
import 'package:event_snap_2/services/platform/shared_content_source.dart';
import 'package:event_snap_2/services/settings_service.dart';
import 'package:event_snap_2/themes/app_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

/// A configured set of fakes plus an [AppStateProvider] over them.
class TestServices {
  TestServices({
    Settings? settings,
    InMemorySettingsService? settingsService,
    FakeAiServiceFactory? aiServiceFactory,
    FakeSharedContentSource? sharedContentSource,
    FakeImageInputService? imageInputService,
    FakeCalendarCreator? calendarCreator,
  }) : settingsService = settingsService ?? InMemorySettingsService(settings),
       aiServiceFactory = aiServiceFactory ?? FakeAiServiceFactory(),
       sharedContentSource = sharedContentSource ?? FakeSharedContentSource(),
       imageInputService = imageInputService ?? FakeImageInputService(),
       calendarCreator = calendarCreator ?? FakeCalendarCreator() {
    appState = AppStateProvider(settingsService: this.settingsService);
  }

  final InMemorySettingsService settingsService;
  final FakeAiServiceFactory aiServiceFactory;
  final FakeSharedContentSource sharedContentSource;
  final FakeImageInputService imageInputService;
  final FakeCalendarCreator calendarCreator;
  late final AppStateProvider appState;

  /// Shortcut to the shared fake interpreter.
  FakeCalendarEventInterpreter get interpreter => aiServiceFactory.interpreter;

  /// Shortcut to the fake model catalog.
  FakeModelCatalog get modelCatalog => aiServiceFactory.modelCatalog;

  /// Loads settings into [appState] (call before pumping screens that need
  /// `isInitialized`).
  Future<void> initAppState() => appState.initialize();

  /// The providers `main.dart` registers, backed by the fakes.
  List<InheritedProvider<Object?>> get providers => [
    Provider<SettingsService>.value(value: settingsService),
    Provider<AiServiceFactory>.value(value: aiServiceFactory),
    Provider<SharedContentSource>.value(value: sharedContentSource),
    Provider<ImageInputService>.value(value: imageInputService),
    Provider<CalendarCreator>.value(value: calendarCreator),
    ChangeNotifierProvider<AppStateProvider>.value(value: appState),
  ];

  /// Wraps [home] in the providers and a `MaterialApp` using the app router,
  /// so `AppRouter.openReview` / `openSettings` work inside tests.
  Widget wrap(Widget home, {ThemeMode themeMode = ThemeMode.light}) {
    return MultiProvider(
      providers: providers,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: home,
        onGenerateRoute: AppRouter.generateRoute,
      ),
    );
  }
}
