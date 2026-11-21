import 'dart:async';

import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/navigation/app_router.dart';
import 'package:event_snap_2/screens/home_screen.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/themes/app_theme.dart';
import 'package:event_snap_2/ui/error_presentation.dart';
import 'package:event_snap_2/widgets/home/composer_card.dart';
import 'package:event_snap_2/widgets/home/example_suggestions.dart';
import 'package:event_snap_2/widgets/home/home_action_bar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

const configured = Settings(openAiApiKey: 'sk-test1234567890');
const photo = InputImage(path: '/nonexistent/photo.jpg');
const photo2 = InputImage(path: '/nonexistent/photo2.jpg');

/// Settings service whose loads wait until [gate] completes.
class _GatedSettingsService extends InMemorySettingsService {
  _GatedSettingsService(super.initial);

  final gate = Completer<void>();

  @override
  Future<Settings> getSettings() async {
    await gate.future;
    return super.getSettings();
  }
}

/// Image service whose pickers fail like a platform error would.
class _ThrowingImageInputService extends FakeImageInputService {
  @override
  Future<InputImage?> pickFromGallery() async {
    galleryCalls++;
    throw Exception('picker crashed');
  }

  @override
  Future<InputImage?> captureWithCamera() async {
    cameraCalls++;
    throw Exception('camera crashed');
  }
}

/// Settings service whose loads fail while [fail] is true.
class _FailingSettingsService extends InMemorySettingsService {
  _FailingSettingsService(super.initial);

  bool fail = true;

  @override
  Future<Settings> getSettings() async {
    if (fail) throw Exception('storage broken');
    return super.getSettings();
  }
}

/// Stand-in for the settings screen (owned by another workstream).
class _StubSettings extends StatelessWidget {
  const _StubSettings();

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Settings stub')));
}

/// Stand-in for the review screen: shows the result and pops with an outcome.
class _StubReview extends StatelessWidget {
  const _StubReview(this.result);

  final ExtractionResult result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review stub')),
      body: Column(
        children: [
          for (final event in result.events) Text('Event: ${event.title}'),
          TextButton(
            onPressed: () => Navigator.of(context).pop(ReviewOutcome.exported),
            child: const Text('Stub export'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Stub back'),
          ),
        ],
      ),
    );
  }
}

/// Wraps [HomeScreen] like `TestServices.wrap`, but routes `/settings` and
/// `/review` to the stubs above so these tests only cover the home screen.
Widget wrapHome(
  TestServices services, {
  ThemeMode themeMode = ThemeMode.light,
}) {
  return MultiProvider(
    providers: services.providers,
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const HomeScreen(),
      onGenerateRoute: (settings) => switch (settings.name) {
        AppRouter.settings => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const _StubSettings(),
        ),
        AppRouter.review => MaterialPageRoute<ReviewOutcome>(
          settings: settings,
          builder: (_) => _StubReview(settings.arguments! as ExtractionResult),
        ),
        _ => AppRouter.generateRoute(settings),
      },
    ),
  );
}

final reviewScreen = find.byType(_StubReview);
final settingsScreen = find.byType(_StubSettings);

final textField = find.byKey(ComposerCard.textFieldKey);
final findEventsButton = find.byKey(HomeActionBar.findEventsKey);
final cancelButton = find.byKey(HomeActionBar.cancelKey);

bool isEnabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).enabled;

String composerText(WidgetTester tester) =>
    tester.widget<TextField>(textField).controller!.text;

/// A phone-sized view (logical pixels).
void usePhoneView(WidgetTester tester, {Size size = const Size(412, 915)}) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<TestServices> pumpHome(
  WidgetTester tester, {
  Settings? settings = configured,
  TestServices? services,
  ThemeMode themeMode = ThemeMode.light,
  bool settle = true,
}) async {
  usePhoneView(tester);
  final s = services ?? TestServices(settings: settings);
  if (!s.appState.isInitialized) await s.initAppState();
  await tester.pumpWidget(wrapHome(s, themeMode: themeMode));
  if (settle) await tester.pumpAndSettle();
  return s;
}

/// Lets an in-flight extraction render without waiting for the (endless)
/// progress animation to settle.
Future<void> pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> enterAndFind(WidgetTester tester, String text) async {
  await tester.enterText(textField, text);
  await tester.pump();
  await tester.tap(findEventsButton);
}

void main() {
  group('composer', () {
    testWidgets('Find events needs text or an image', (tester) async {
      final services = await pumpHome(tester);
      services.imageInputService.galleryResult = photo;

      expect(isEnabled(tester, findEventsButton), isFalse);

      await tester.enterText(textField, '   ');
      await tester.pump();
      expect(isEnabled(tester, findEventsButton), isFalse);

      await tester.enterText(textField, 'Lunch tomorrow at 12');
      await tester.pump();
      expect(isEnabled(tester, findEventsButton), isTrue);

      await tester.enterText(textField, '');
      await tester.pump();
      expect(isEnabled(tester, findEventsButton), isFalse);

      await tester.tap(find.byTooltip('Add image from gallery'));
      await tester.pumpAndSettle();
      expect(isEnabled(tester, findEventsButton), isTrue);
    });

    testWidgets('example chips fill the text and then hide', (tester) async {
      await pumpHome(tester);
      expect(find.text('Try an example'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('example_chip_1')));
      await tester.pumpAndSettle();

      expect(composerText(tester), ExampleSuggestions.examples[1]);
      expect(isEnabled(tester, findEventsButton), isTrue);
      expect(find.text('Try an example'), findsNothing);
    });

    testWidgets('adds and removes images', (tester) async {
      final services = await pumpHome(tester);
      services.imageInputService
        ..galleryResult = photo
        ..cameraResult = photo2;

      await tester.tap(find.byTooltip('Add image from gallery'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Take a photo'));
      await tester.pumpAndSettle();

      expect(services.imageInputService.galleryCalls, 1);
      expect(services.imageInputService.cameraCalls, 1);
      expect(find.byTooltip('Remove image 1'), findsOneWidget);
      expect(find.byTooltip('Remove image 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove image 1'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove image 2'), findsNothing);
      expect(find.byTooltip('Remove image 1'), findsOneWidget);

      await tester.tap(findEventsButton);
      await tester.pumpAndSettle();
      expect(services.interpreter.calls.single.images, [photo2]);
    });

    testWidgets('a cancelled pick adds nothing', (tester) async {
      final services = await pumpHome(tester);
      await tester.tap(find.byTooltip('Add image from gallery'));
      await tester.pumpAndSettle();
      expect(services.imageInputService.galleryCalls, 1);
      expect(find.byTooltip('Remove image 1'), findsNothing);
    });

    testWidgets('a failing picker shows a snackbar and keeps the composer', (
      tester,
    ) async {
      final images = _ThrowingImageInputService();
      final services = await pumpHome(
        tester,
        services: TestServices(settings: configured, imageInputService: images),
      );
      await tester.enterText(textField, 'Picnic on Sunday');
      await tester.pump();

      await tester.tap(find.byTooltip('Add image from gallery'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load that image"), findsOneWidget);

      await tester.tap(find.byTooltip('Take a photo'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load that image"), findsOneWidget);

      expect(images.galleryCalls, 1);
      expect(images.cameraCalls, 1);
      expect(composerText(tester), 'Picnic on Sunday');
      expect(find.byTooltip('Remove image 1'), findsNothing);
      expect(isEnabled(tester, findEventsButton), isTrue);
      expect(services.interpreter.calls, isEmpty);
    });

    testWidgets('hides the camera when unsupported', (tester) async {
      await pumpHome(
        tester,
        services: TestServices(
          settings: configured,
          imageInputService: FakeImageInputService(cameraSupported: false),
        ),
      );
      expect(find.byTooltip('Take a photo'), findsNothing);
      expect(find.byTooltip('Add image from gallery'), findsOneWidget);
    });

    testWidgets('limits attachments to four images', (tester) async {
      final services = await pumpHome(tester);
      services.imageInputService.galleryResult = photo;
      for (var i = 0; i < HomeScreen.maxImages; i++) {
        await tester.tap(find.byTooltip('Add image from gallery'));
        await tester.pumpAndSettle();
      }
      expect(find.byTooltip('Remove image 4'), findsOneWidget);
      final gallery = find.widgetWithIcon(
        IconButton,
        Icons.add_photo_alternate_outlined,
      );
      expect(tester.widget<IconButton>(gallery).onPressed, isNull);
    });

    testWidgets('pastes clipboard text', (tester) async {
      String? clipboard = 'Pasted: dinner at 7pm';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return clipboard == null ? null : {'text': clipboard};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpHome(tester);

      await tester.tap(find.byTooltip('Paste'));
      await tester.pumpAndSettle();
      expect(composerText(tester), 'Pasted: dinner at 7pm');
      expect(isEnabled(tester, findEventsButton), isTrue);

      clipboard = null;
      await tester.tap(find.byTooltip('Paste'));
      await tester.pump();
      expect(find.text('Nothing to paste'), findsOneWidget);
    });

    testWidgets('clear empties the composer and can be undone', (tester) async {
      final services = await pumpHome(tester);
      services.imageInputService.galleryResult = photo;
      await tester.enterText(textField, 'Yoga on Monday');
      await tester.tap(find.byTooltip('Add image from gallery'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(composerText(tester), isEmpty);
      expect(find.byTooltip('Remove image 1'), findsNothing);
      expect(find.text('Clear'), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(composerText(tester), 'Yoga on Monday');
      expect(find.byTooltip('Remove image 1'), findsOneWidget);
    });
  });

  group('setup and status', () {
    testWidgets('setup card when not configured', (tester) async {
      final services = await pumpHome(tester, settings: null);

      expect(find.text('Finish setting up'), findsOneWidget);
      expect(find.byKey(const Key('model_status_chip')), findsNothing);
      await tester.enterText(textField, 'Lunch at 12');
      await tester.pump();
      expect(isEnabled(tester, findEventsButton), isFalse);

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(settingsScreen, findsOneWidget);

      await services.appState.updateSettings(configured);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(find.text('Finish setting up'), findsNothing);
      expect(find.text('OpenAI · gpt-5-mini'), findsOneWidget);
      expect(isEnabled(tester, findEventsButton), isTrue);
    });

    testWidgets('status chip shows provider and model and opens settings', (
      tester,
    ) async {
      await pumpHome(
        tester,
        settings: const Settings(
          provider: AiProvider.opper,
          opperApiKey: 'op-key',
          opperModel: 'anthropic/claude-sonnet-5-5',
        ),
      );
      expect(find.text('Opper · anthropic/claude-sonnet-5-5'), findsOneWidget);

      await tester.tap(find.byKey(const Key('model_status_chip')));
      await tester.pumpAndSettle();
      expect(settingsScreen, findsOneWidget);
    });

    testWidgets('composer is usable before settings have loaded', (
      tester,
    ) async {
      usePhoneView(tester);
      final settingsService = _GatedSettingsService(configured);
      final services = TestServices(settingsService: settingsService);
      unawaited(services.appState.initialize());
      await tester.pumpWidget(wrapHome(services));
      await tester.pump();

      expect(find.text('Finish setting up'), findsNothing);
      await tester.enterText(textField, 'Lunch at 12');
      await tester.pump();
      expect(isEnabled(tester, findEventsButton), isFalse);

      settingsService.gate.complete();
      await tester.pumpAndSettle();
      expect(isEnabled(tester, findEventsButton), isTrue);
      expect(find.text('OpenAI · gpt-5-mini'), findsOneWidget);
    });

    testWidgets('shows a settings load error with retry', (tester) async {
      usePhoneView(tester);
      final settingsService = _FailingSettingsService(configured);
      final services = TestServices(settingsService: settingsService);
      await services.initAppState();
      await tester.pumpWidget(wrapHome(services));
      await tester.pumpAndSettle();

      expect(find.text('Settings problem'), findsOneWidget);
      settingsService.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Settings problem'), findsNothing);
      expect(find.text('OpenAI · gpt-5-mini'), findsOneWidget);
    });

    testWidgets('warns when the model cannot read images', (tester) async {
      final services = await pumpHome(
        tester,
        settings: configured.copyWith(openAiModel: 'gpt-3.5-turbo'),
      );
      services.imageInputService.galleryResult = photo;
      expect(find.text("This model can't read images"), findsNothing);

      await tester.tap(find.byTooltip('Add image from gallery'));
      await tester.pumpAndSettle();
      expect(find.text("This model can't read images"), findsOneWidget);

      await tester.tap(find.text('Change model'));
      await tester.pumpAndSettle();
      expect(settingsScreen, findsOneWidget);
    });

    testWidgets('no vision warning for vision models', (tester) async {
      final services = await pumpHome(tester);
      services.imageInputService.galleryResult = photo;
      await tester.tap(find.byTooltip('Add image from gallery'));
      await tester.pumpAndSettle();
      expect(find.text("This model can't read images"), findsNothing);
    });
  });

  group('extraction', () {
    testWidgets('opens the review screen with the result', (tester) async {
      final services = await pumpHome(tester);
      services.interpreter.result = sampleResult(
        events: [sampleEvent(title: 'Board meeting')],
      );

      await enterAndFind(tester, '  Board meeting May 25 10am ');
      await tester.pumpAndSettle();

      expect(
        services.interpreter.calls.single.text,
        'Board meeting May 25 10am',
      );
      expect(services.aiServiceFactory.createdWith.single, configured);
      final review = tester.widget<_StubReview>(reviewScreen);
      expect(review.result.events.single.title, 'Board meeting');
    });

    testWidgets('shows progress and disables inputs while working', (
      tester,
    ) async {
      final services = await pumpHome(tester);
      final pending = Completer<ExtractionResult>();
      services.interpreter.handler = (_, _) => pending.future;

      await enterAndFind(tester, 'Lunch at 12');
      await pumpFrames(tester);

      expect(find.text('Reading your text…'), findsOneWidget);
      expect(find.text('OpenAI · gpt-5-mini'), findsWidgets);
      expect(cancelButton, findsOneWidget);
      expect(findEventsButton, findsNothing);
      expect(tester.widget<TextField>(textField).enabled, isFalse);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      pending.complete(sampleResult());
      await tester.pumpAndSettle();
      expect(reviewScreen, findsOneWidget);
    });

    testWidgets('stage text mentions the image', (tester) async {
      final services = await pumpHome(tester);
      services.imageInputService.galleryResult = photo;
      services.interpreter.handler = (_, _) =>
          Completer<ExtractionResult>().future;

      await tester.tap(find.byTooltip('Add image from gallery'));
      await tester.pumpAndSettle();
      await tester.tap(findEventsButton);
      await pumpFrames(tester);

      expect(find.text('Looking at your image…'), findsOneWidget);
      expect(services.interpreter.calls.single.images, [photo]);
    });

    testWidgets('cancel stops waiting and ignores a late result', (
      tester,
    ) async {
      final services = await pumpHome(tester);
      final pending = Completer<ExtractionResult>();
      services.interpreter.handler = (_, _) => pending.future;

      await enterAndFind(tester, 'Lunch at 12');
      await pumpFrames(tester);
      await tester.tap(cancelButton);
      await pumpFrames(tester);

      expect(services.interpreter.tokens.single!.isCancelled, isTrue);
      expect(find.text('Reading your text…'), findsNothing);
      expect(isEnabled(tester, findEventsButton), isTrue);
      expect(composerText(tester), 'Lunch at 12');

      pending.complete(sampleResult());
      await tester.pumpAndSettle();
      expect(reviewScreen, findsNothing);
      expect(find.byKey(const Key('home_error_banner')), findsNothing);
    });

    testWidgets('system back cancels a running extraction', (tester) async {
      final services = await pumpHome(tester);
      services.interpreter.handler = (_, _) =>
          Completer<ExtractionResult>().future;

      await enterAndFind(tester, 'Lunch at 12');
      await pumpFrames(tester);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      expect(services.interpreter.tokens.single!.isCancelled, isTrue);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(isEnabled(tester, findEventsButton), isTrue);
    });

    testWidgets('no events shows an inline hint', (tester) async {
      final services = await pumpHome(tester);
      await enterAndFind(tester, 'hello there');
      await tester.pumpAndSettle();

      expect(services.interpreter.calls, hasLength(1));
      expect(reviewScreen, findsNothing);
      expect(find.text('No events found'), findsOneWidget);
      expect(find.text('Try adding a date or time.'), findsOneWidget);

      // Editing the text hides the stale hint.
      await tester.enterText(textField, 'hello there at 5pm');
      await tester.pump();
      expect(find.text('No events found'), findsNothing);
    });

    testWidgets('exported outcome clears the composer', (tester) async {
      final services = await pumpHome(tester);
      services.interpreter.result = sampleResult();
      await enterAndFind(tester, 'Team meeting on May 25 at 10');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stub export'));
      await tester.pumpAndSettle();

      expect(reviewScreen, findsNothing);
      expect(composerText(tester), isEmpty);
      expect(find.text('Sent to your calendar app'), findsOneWidget);
      expect(isEnabled(tester, findEventsButton), isFalse);
    });

    testWidgets('discarding the review keeps the composer', (tester) async {
      final services = await pumpHome(tester);
      services.interpreter.result = sampleResult();
      await enterAndFind(tester, 'Team meeting on May 25 at 10');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stub back'));
      await tester.pumpAndSettle();

      expect(composerText(tester), 'Team meeting on May 25 at 10');
      expect(find.text('Sent to your calendar app'), findsNothing);
    });
  });

  group('errors', () {
    final cases = <AiErrorKind, ErrorAction?>{
      AiErrorKind.notConfigured: ErrorAction.openSettings,
      AiErrorKind.auth: ErrorAction.openSettings,
      AiErrorKind.modelNotFound: ErrorAction.chooseModel,
      AiErrorKind.unsupportedInput: ErrorAction.chooseVisionModel,
      AiErrorKind.network: ErrorAction.retry,
      AiErrorKind.timeout: ErrorAction.retry,
      AiErrorKind.server: ErrorAction.retry,
      AiErrorKind.rateLimited: ErrorAction.retry,
      AiErrorKind.quotaExceeded: null,
    };

    for (final MapEntry(key: kind, value: action) in cases.entries) {
      testWidgets('${kind.name} → ${action?.label ?? 'no action'}', (
        tester,
      ) async {
        final services = await pumpHome(tester);
        services.interpreter.error = AiException(kind, 'technical detail');

        await enterAndFind(tester, 'Lunch at 12');
        await tester.pumpAndSettle();

        expect(find.text(AiException.userMessageFor(kind)), findsOneWidget);
        expect(find.textContaining('technical detail'), findsNothing);
        expect(isEnabled(tester, findEventsButton), isTrue);

        if (action == null) {
          expect(
            find.descendant(
              of: find.byKey(const Key('home_error_banner')),
              matching: find.byType(TextButton),
            ),
            findsNothing,
          );
          return;
        }
        final button = find.byKey(ValueKey('error_action_${action.name}'));
        expect(
          find.descendant(of: button, matching: find.text(action.label)),
          findsOneWidget,
        );

        services.interpreter
          ..error = null
          ..result = sampleResult();
        await tester.tap(button);
        await tester.pumpAndSettle();

        if (action == ErrorAction.retry) {
          expect(services.interpreter.calls, hasLength(2));
          expect(reviewScreen, findsOneWidget);
        } else {
          expect(settingsScreen, findsOneWidget);
          expect(services.interpreter.calls, hasLength(1));
        }
      });
    }

    testWidgets('cancelled errors are not shown', (tester) async {
      final services = await pumpHome(tester);
      services.interpreter.error = const AiException(
        AiErrorKind.cancelled,
        'cancelled',
      );
      await enterAndFind(tester, 'Lunch at 12');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home_error_banner')), findsNothing);
    });

    testWidgets('the error banner can be dismissed', (tester) async {
      final services = await pumpHome(tester);
      services.interpreter.error = const AiException(
        AiErrorKind.network,
        'offline',
      );
      await enterAndFind(tester, 'Lunch at 12');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home_error_banner')), findsNothing);
    });

    testWidgets('changing settings clears a stale error', (tester) async {
      final services = await pumpHome(tester);
      services.interpreter.error = const AiException(AiErrorKind.auth, '401');
      await enterAndFind(tester, 'Lunch at 12');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home_error_banner')), findsOneWidget);

      await services.appState.updateSettings(
        configured.copyWith(openAiApiKey: 'sk-new-key-12345'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home_error_banner')), findsNothing);
    });
  });

  group('sharing', () {
    const shared = SharedContent(text: 'Concert on Saturday at 8pm');

    testWidgets('initial share fills the composer and is processed', (
      tester,
    ) async {
      final services = TestServices(
        settings: configured,
        sharedContentSource: FakeSharedContentSource(initial: shared),
      );
      services.interpreter.result = sampleResult();
      await pumpHome(tester, services: services);

      expect(services.sharedContentSource.initialCalls, 1);
      expect(services.interpreter.calls.single.text, shared.text);
      expect(reviewScreen, findsOneWidget);
    });

    testWidgets('live share with images replaces the composer and is '
        'processed', (tester) async {
      final services = await pumpHome(tester);
      await tester.enterText(textField, 'Old draft');
      await tester.pump();

      services.sharedContentSource.emit(
        const SharedContent(text: 'Flyer', images: [photo, photo2]),
      );
      await tester.pumpAndSettle();

      final input = services.interpreter.calls.single;
      expect(input.text, 'Flyer');
      expect(input.images, [photo, photo2]);
      expect(find.text('Old draft'), findsNothing);
    });

    testWidgets('not processed when auto-processing is off', (tester) async {
      final services = await pumpHome(
        tester,
        settings: configured.copyWith(autoProcessShared: false),
      );
      services.sharedContentSource.emit(shared);
      await tester.pumpAndSettle();

      expect(composerText(tester), shared.text);
      expect(find.text('Shared content added'), findsOneWidget);
      expect(services.interpreter.calls, isEmpty);
      expect(isEnabled(tester, findEventsButton), isTrue);
    });

    testWidgets('not processed when not configured', (tester) async {
      final services = await pumpHome(tester, settings: null);
      services.sharedContentSource.emit(shared);
      await tester.pumpAndSettle();

      expect(composerText(tester), shared.text);
      expect(find.text('Finish setting up'), findsOneWidget);
      expect(services.interpreter.calls, isEmpty);
    });

    testWidgets('undo restores what was in the composer', (tester) async {
      final services = await pumpHome(
        tester,
        settings: configured.copyWith(autoProcessShared: false),
      );
      await tester.enterText(textField, 'My draft');
      await tester.pump();
      services.sharedContentSource.emit(shared);
      await tester.pumpAndSettle();
      expect(composerText(tester), shared.text);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(composerText(tester), 'My draft');
    });

    testWidgets('a share before settings loaded waits for them', (
      tester,
    ) async {
      usePhoneView(tester);
      final settingsService = _GatedSettingsService(configured);
      final services = TestServices(
        settingsService: settingsService,
        sharedContentSource: FakeSharedContentSource(initial: shared),
      );
      services.interpreter.result = sampleResult();
      unawaited(services.appState.initialize());
      await tester.pumpWidget(wrapHome(services));
      await tester.pump();
      await tester.pump();

      expect(composerText(tester), shared.text);
      expect(services.interpreter.calls, isEmpty);

      settingsService.gate.complete();
      await tester.pumpAndSettle();

      expect(services.interpreter.calls.single.text, shared.text);
      expect(services.aiServiceFactory.createdWith.single, configured);
      expect(reviewScreen, findsOneWidget);
    });

    testWidgets('a share before settings loaded respects the loaded '
        'auto-process setting', (tester) async {
      usePhoneView(tester);
      final settingsService = _GatedSettingsService(
        configured.copyWith(autoProcessShared: false),
      );
      final services = TestServices(
        settingsService: settingsService,
        sharedContentSource: FakeSharedContentSource(initial: shared),
      );
      unawaited(services.appState.initialize());
      await tester.pumpWidget(wrapHome(services));
      await tester.pump();
      settingsService.gate.complete();
      await tester.pumpAndSettle();

      expect(composerText(tester), shared.text);
      expect(services.interpreter.calls, isEmpty);
    });

    testWidgets('a share during extraction replaces the running one', (
      tester,
    ) async {
      final services = await pumpHome(tester);
      final first = Completer<ExtractionResult>();
      services.interpreter.handler = (input, _) =>
          input.text == 'First' ? first.future : Future.value(sampleResult());

      await enterAndFind(tester, 'First');
      await pumpFrames(tester);
      services.sharedContentSource.emit(shared);
      await tester.pumpAndSettle();

      expect(services.interpreter.tokens.first!.isCancelled, isTrue);
      expect(services.interpreter.calls.map((c) => c.text), [
        'First',
        shared.text,
      ]);
      expect(reviewScreen, findsOneWidget);

      first.complete(sampleResult(events: [sampleEvent(title: 'Stale')]));
      await tester.pumpAndSettle();
      expect(reviewScreen, findsOneWidget);
    });

    testWidgets('a share while reviewing is processed after the review '
        'closes and survives the export', (tester) async {
      final services = await pumpHome(tester);
      services.interpreter.result = sampleResult();
      await enterAndFind(tester, 'First text');
      await tester.pumpAndSettle();
      expect(reviewScreen, findsOneWidget);

      services.sharedContentSource.emit(shared);
      await tester.pumpAndSettle();
      expect(services.interpreter.calls, hasLength(1));

      await tester.tap(find.text('Stub export'));
      await tester.pumpAndSettle();

      expect(services.interpreter.calls, hasLength(2));
      expect(services.interpreter.calls.last.text, shared.text);
      expect(reviewScreen, findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('the bottom bar stays above the keyboard', (tester) async {
      await pumpHome(tester);
      await tester.enterText(textField, 'Lunch at 12');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      final button = tester.getRect(findEventsButton);
      expect(button.bottom, lessThanOrEqualTo(915 - 300));
      expect(isEnabled(tester, findEventsButton), isTrue);
    });

    Future<void> scaleText(WidgetTester tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('setup state fits at text scale 2.0 on a small phone', (
      tester,
    ) async {
      await scaleText(tester);
      final services = TestServices();
      await services.initAppState();
      usePhoneView(tester, size: const Size(360, 740));
      await tester.pumpWidget(wrapHome(services));
      await tester.pumpAndSettle();
      // Layout overflows are reported as test failures by the framework.
      expect(find.text('Finish setting up'), findsOneWidget);
    });

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('busy composer fits at text scale 2.0 (${themeMode.name})', (
        tester,
      ) async {
        await scaleText(tester);
        final services = TestServices(
          settings: const Settings(
            provider: AiProvider.opper,
            opperApiKey: 'op-key',
            opperModel: 'openai/gpt-3.5-turbo-long-model-name-for-layout',
          ),
        );
        services.modelCatalog.models[AiProvider.opper] = const [
          AiModelInfo(
            id: 'openai/gpt-3.5-turbo-long-model-name-for-layout',
            provider: AiProvider.opper,
            supportsVision: false,
          ),
        ];
        services.imageInputService.galleryResult = photo;
        services.interpreter.error = const AiException(
          AiErrorKind.unsupportedInput,
          'no vision',
        );
        await services.initAppState();
        usePhoneView(tester, size: const Size(360, 740));
        await tester.pumpWidget(wrapHome(services, themeMode: themeMode));
        await tester.pumpAndSettle();

        await tester.enterText(textField, 'Dinner with Sam on Friday at 7pm');
        for (var i = 0; i < HomeScreen.maxImages; i++) {
          await tester.tap(find.byTooltip('Add image from gallery'));
          await tester.pumpAndSettle();
        }
        await tester.tap(findEventsButton);
        await tester.pumpAndSettle();

        // Layout overflows are reported as test failures by the framework.
        expect(find.byKey(const Key('home_error_banner')), findsOneWidget);
        expect(find.text("This model can't read images"), findsOneWidget);
        expect(
          Theme.of(tester.element(find.byType(HomeScreen))).brightness,
          themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light,
        );

        // Processing state.
        services.interpreter.handler = (_, _) =>
            Completer<ExtractionResult>().future;
        await tester.tap(findEventsButton);
        await pumpFrames(tester);
        // Layout overflows are reported as test failures by the framework.
        expect(find.text('Looking at your images…'), findsOneWidget);
      });
    }
  });
}
