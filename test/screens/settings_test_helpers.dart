/// Helpers shared by the settings screen and model picker tests.
library;

import 'dart:async';

import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/providers/app_state_provider.dart';
import 'package:event_snap_2/themes/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

/// [FakeModelCatalog] whose calls can be held open and that records
/// `forceRefresh` flags.
class ScriptedModelCatalog extends FakeModelCatalog {
  ScriptedModelCatalog({super.models, super.error});

  /// When set, [listModels] waits for it before answering.
  Completer<void>? listGate;

  /// When set, [verifyApiKey] waits for it before answering.
  Completer<void>? verifyGate;

  /// `forceRefresh` of every [listModels] call, in order.
  final List<bool> forceRefreshFlags = [];

  /// Model ids passed to [findModel], in order.
  final List<String> findCalls = [];

  @override
  Future<List<AiModelInfo>> listModels(
    AiProvider provider, {
    required String apiKey,
    bool forceRefresh = false,
  }) async {
    forceRefreshFlags.add(forceRefresh);
    final gate = listGate;
    if (gate != null) await gate.future;
    return super.listModels(
      provider,
      apiKey: apiKey,
      forceRefresh: forceRefresh,
    );
  }

  @override
  Future<AiModelInfo?> findModel(
    AiProvider provider,
    String modelId, {
    required String apiKey,
  }) {
    findCalls.add(modelId);
    return super.findModel(provider, modelId, apiKey: apiKey);
  }

  @override
  Future<void> verifyApiKey(AiProvider provider, String apiKey) async {
    final gate = verifyGate;
    if (gate != null) await gate.future;
    return super.verifyApiKey(provider, apiKey);
  }
}

/// [count] Opper-style models; every 100th is recommended, even ones support
/// structured output, multiples of 3 support vision.
List<AiModelInfo> generateModels(int count) => [
  for (var i = 0; i < count; i++)
    AiModelInfo(
      id: 'vendor${i % 7}/model-$i',
      displayName: 'Model $i',
      provider: AiProvider.opper,
      vendor: 'Vendor ${i % 7}',
      supportsStructuredOutput: i.isEven,
      supportsVision: i % 3 == 0,
      speed: 'fast',
      quality: 'great',
      recommended: i % 100 == 0,
    ),
];

/// Services with a [ScriptedModelCatalog].
TestServices servicesWith({
  Settings settings = const Settings(),
  ScriptedModelCatalog? catalog,
}) {
  return TestServices(
    settings: settings,
    aiServiceFactory: FakeAiServiceFactory(
      modelCatalog: catalog ?? ScriptedModelCatalog(),
    ),
  );
}

/// Like [TestServices.wrap], but the app theme follows
/// [AppStateProvider.themeMode] like `main.dart`.
Widget themedApp(TestServices services, Widget home) {
  return MultiProvider(
    providers: services.providers,
    child: Consumer<AppStateProvider>(
      builder: (context, appState, _) => MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: appState.themeMode,
        home: home,
      ),
    ),
  );
}

/// A phone-sized logical viewport ([width] x [height]).
void usePhoneView(
  WidgetTester tester, {
  double width = 412,
  double height = 2400,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
