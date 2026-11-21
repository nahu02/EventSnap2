import '../../models/settings.dart';
import 'calendar_event_interpreter.dart';
import 'model_catalog.dart';

/// Creates AI services for the current settings. Registered via `provider`
/// in `main.dart`; screens use `context.read<AiServiceFactory>()`.
abstract class AiServiceFactory {
  CalendarEventInterpreter createInterpreter(Settings settings);
  ModelCatalog get modelCatalog;
}
