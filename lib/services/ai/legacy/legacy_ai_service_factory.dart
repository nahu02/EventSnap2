import '../default_ai_service_factory.dart';

/// TEMPORARY alias so `main.dart` keeps compiling until integration swaps its
/// registration to `DefaultAiServiceFactory()`. The legacy adapter is gone:
/// this name already resolves to the new implementation. Delete this file
/// (and the `legacy/` folder) when `main.dart` no longer imports it.
typedef LegacyAiServiceFactory = DefaultAiServiceFactory;
