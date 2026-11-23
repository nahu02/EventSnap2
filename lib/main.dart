import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'navigation/app_router.dart';
import 'providers/app_state_provider.dart';
import 'services/ai/ai_service_factory.dart';
import 'services/ai/default_ai_service_factory.dart';
import 'services/calendar/calendar_creator.dart';
import 'services/calendar/icalendar_creator.dart';
import 'services/platform/android_shared_content_source.dart';
import 'services/platform/image_input_service.dart';
import 'services/platform/picker_image_input_service.dart';
import 'services/platform/shared_content_source.dart';
import 'services/platform/snap_file_store.dart';
import 'services/platform/snap_service.dart';
import 'services/settings_service.dart';
import 'themes/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EventSnapApp());
}

/// Main application widget
///
/// Registers the services (screens obtain them with `context.read<…>()`),
/// the app state, theming and navigation. Every service can be overridden,
/// e.g. with fakes in widget tests.
class EventSnapApp extends StatelessWidget {
  const EventSnapApp({
    super.key,
    this.settingsService,
    this.aiServiceFactory,
    this.sharedContentSource,
    this.imageInputService,
    this.calendarCreator,
    this.snapService,
    this.snapFileStore,
  });

  final SettingsService? settingsService;
  final AiServiceFactory? aiServiceFactory;
  final SharedContentSource? sharedContentSource;
  final ImageInputService? imageInputService;
  final CalendarCreator? calendarCreator;
  final SnapService? snapService;
  final SnapFileStore? snapFileStore;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SettingsService>(
          create: (_) => settingsService ?? SecureSettingsService(),
        ),
        Provider<AiServiceFactory>(
          create: (_) => aiServiceFactory ?? DefaultAiServiceFactory(),
        ),
        Provider<SharedContentSource>(
          create: (_) => sharedContentSource ?? AndroidSharedContentSource(),
          dispose: (_, source) => source.dispose(),
        ),
        Provider<ImageInputService>(
          create: (_) => imageInputService ?? PickerImageInputService(),
        ),
        Provider<CalendarCreator>(
          create: (_) => calendarCreator ?? ICalendarCreator(),
        ),
        Provider<SnapService>(
          create: (_) => snapService ?? AndroidSnapService(),
        ),
        Provider<SnapFileStore>(
          create: (_) => snapFileStore ?? SnapFileStore(),
        ),
        ChangeNotifierProvider<AppStateProvider>(
          create: (context) =>
              AppStateProvider(settingsService: context.read<SettingsService>())
                ..initialize(),
        ),
      ],
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          return Consumer<AppStateProvider>(
            builder: (context, appState, child) {
              return MaterialApp(
                title: 'EventSnap',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light(dynamicScheme: lightDynamic),
                darkTheme: AppTheme.dark(dynamicScheme: darkDynamic),
                themeMode: appState.themeMode,
                initialRoute: AppRouter.home,
                onGenerateRoute: AppRouter.generateRoute,
              );
            },
          );
        },
      ),
    );
  }
}
