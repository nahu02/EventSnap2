import 'dart:async';

import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/navigation/app_router.dart';
import 'package:event_snap_2/screens/crop_screen.dart';
import 'package:event_snap_2/screens/home_screen.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/themes/app_theme.dart';
import 'package:event_snap_2/widgets/home/composer_card.dart';
import 'package:event_snap_2/widgets/home/home_action_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

const configured = Settings(openAiApiKey: 'sk-test1234567890');
const snap = InputImage(path: '/cache/snaps/snap_1.jpg', isEphemeral: true);
const snap2 = InputImage(path: '/cache/snaps/snap_2.jpg', isEphemeral: true);
const gallery = InputImage(path: '/gallery/photo.jpg');

SharedContent snapContent(InputImage image, {bool crop = false}) =>
    SharedContent(images: [image], isSnap: true, crop: crop);

/// Stand-in for the review screen (owned by another workstream).
class _StubReview extends StatelessWidget {
  const _StubReview(this.result);

  final ExtractionResult result;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review stub')),
    body: Column(
      children: [
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

Widget wrapHome(TestServices services) => MultiProvider(
  providers: services.providers,
  child: MaterialApp(
    theme: AppTheme.light(),
    home: const HomeScreen(),
    onGenerateRoute: (settings) => settings.name == AppRouter.review
        ? MaterialPageRoute<ReviewOutcome>(
            settings: settings,
            builder: (_) =>
                _StubReview(settings.arguments! as ExtractionResult),
          )
        : AppRouter.generateRoute(settings),
  ),
);

final attachments = find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('attachment_'),
);
final findEventsButton = find.byKey(HomeActionBar.findEventsKey);
final cancelButton = find.byKey(HomeActionBar.cancelKey);

void usePhoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 915) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<TestServices> pumpHome(
  WidgetTester tester, {
  Settings settings = configured,
  TestServices? services,
}) async {
  usePhoneView(tester);
  final s = services ?? TestServices(settings: settings);
  if (!s.appState.isInitialized) await s.initAppState();
  await tester.pumpWidget(wrapHome(s));
  await tester.pumpAndSettle();
  return s;
}

/// Lets a pushed route finish its transition (its spinner never settles).
Future<void> pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('plain snap', () {
    testWidgets('lands in the composer and is not processed by default', (
      tester,
    ) async {
      final services = await pumpHome(tester);
      services.sharedContentSource.emit(snapContent(snap));
      await tester.pumpAndSettle();

      expect(attachments, findsOneWidget);
      expect(services.interpreter.calls, isEmpty);
      expect(services.snapFileStore.deleted, isEmpty);
      expect(
        tester.widget<ButtonStyleButton>(findEventsButton).enabled,
        isTrue,
      );
    });

    testWidgets('autoProcessSnaps starts "Find events" with the snap', (
      tester,
    ) async {
      final services = await pumpHome(
        tester,
        settings: configured.copyWith(autoProcessSnaps: true),
      );
      services.interpreter.result = sampleResult();
      services.sharedContentSource.emit(snapContent(snap));
      await tester.pumpAndSettle();

      expect(services.interpreter.calls.single.images, [snap]);
      expect(find.byType(_StubReview), findsOneWidget);
      // Still needed while the review is open.
      expect(services.snapFileStore.deleted, isEmpty);
    });

    testWidgets('autoProcessShared does not auto-process snaps', (
      tester,
    ) async {
      final services = await pumpHome(
        tester,
        settings: configured.copyWith(autoProcessShared: true),
      );
      services.sharedContentSource.emit(snapContent(snap));
      await tester.pumpAndSettle();
      expect(services.interpreter.calls, isEmpty);
    });

    testWidgets('a snap on cold start is processed only if allowed and the '
        'initial snap survives the leftover cleanup', (tester) async {
      final services = TestServices(
        settings: configured.copyWith(autoProcessSnaps: true),
        sharedContentSource: FakeSharedContentSource(
          initial: snapContent(snap),
        ),
      );
      services.interpreter.result = sampleResult();
      await pumpHome(tester, services: services);

      expect(services.snapFileStore.leftoverKeeps.single, [snap]);
      expect(services.interpreter.calls.single.images, [snap]);
    });

    testWidgets('leftovers are cleaned up on start', (tester) async {
      final services = await pumpHome(tester);
      expect(services.snapFileStore.leftoverKeeps, [<InputImage>[]]);
    });

    testWidgets('keeps text and other images; oldest image makes room', (
      tester,
    ) async {
      final services = await pumpHome(tester);
      services.sharedContentSource.emit(const SharedContent(images: [gallery]));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(ComposerCard.textFieldKey), 'Party');
      services.sharedContentSource.emit(snapContent(snap));
      await tester.pumpAndSettle();
      expect(attachments, findsNWidgets(2));
      expect(
        tester
            .widget<TextField>(find.byKey(ComposerCard.textFieldKey))
            .controller!
            .text,
        'Party',
      );
      expect(services.snapFileStore.deleted, isEmpty);
    });
  });

  group('snap errors', () {
    testWidgets('service disabled: banner with a button to the settings', (
      tester,
    ) async {
      final services = await pumpHome(tester);
      services.sharedContentSource.emit(
        const SharedContent(isSnap: true, snapError: SnapError.serviceDisabled),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('snap_problem_banner')), findsOneWidget);
      expect(find.text('Turn on screen snaps'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('open_accessibility_settings_button')),
      );
      await tester.pump();
      expect(services.snapService.openSettingsCalls, 1);
    });

    testWidgets('unsupported / secure / failed explain themselves', (
      tester,
    ) async {
      final services = await pumpHome(tester);
      for (final (error, title) in [
        (SnapError.unsupported, 'Screen snaps need Android 11 or newer'),
        (SnapError.secure, "Couldn't capture this screen"),
        (SnapError.failed, 'Screenshot failed'),
      ]) {
        services.sharedContentSource.emit(
          SharedContent(isSnap: true, snapError: error),
        );
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(
          find.byKey(const Key('open_accessibility_settings_button')),
          findsNothing,
        );
      }
    });

    testWidgets('the banner goes away with the next good snap', (tester) async {
      final services = await pumpHome(tester);
      services.sharedContentSource
        ..emit(const SharedContent(isSnap: true, snapError: SnapError.failed))
        ..emit(snapContent(snap));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('snap_problem_banner')), findsNothing);
    });
  });

  group('deletion policy', () {
    testWidgets('0 events: snap is deleted and leaves the composer', (
      tester,
    ) async {
      final services = await pumpHome(tester);
      services.sharedContentSource.emit(snapContent(snap));
      await tester.pumpAndSettle();
      await tester.tap(findEventsButton);
      await pumpFrames(tester);

      expect(find.byKey(const Key('no_events_banner')), findsOneWidget);
      expect(services.snapFileStore.deleted, [snap]);
      expect(attachments, findsNothing);
    });

    testWidgets('error: snap is deleted', (tester) async {
      final services = await pumpHome(tester);
      services.interpreter.error = const AiException(AiErrorKind.network, 'x');
      services.sharedContentSource.emit(snapContent(snap));
      await tester.pumpAndSettle();
      await tester.tap(findEventsButton);
      await pumpFrames(tester);

      expect(find.byKey(const Key('home_error_banner')), findsOneWidget);
      expect(services.snapFileStore.deleted, [snap]);
      expect(attachments, findsNothing);
    });

    testWidgets('cancel: snap is deleted', (tester) async {
      final services = await pumpHome(tester);
      final gate = Completer<ExtractionResult>();
      services.interpreter.handler = (input, token) => gate.future;
      services.sharedContentSource.emit(snapContent(snap));
      await tester.pumpAndSettle();
      await tester.tap(findEventsButton);
      await pumpFrames(tester);
      expect(cancelButton, findsOneWidget);

      await tester.tap(cancelButton);
      await pumpFrames(tester);
      expect(services.snapFileStore.deleted, [snap]);
      expect(attachments, findsNothing);
    });

    testWidgets('review exported: deleted only after the review closed', (
      tester,
    ) async {
      final services = await pumpHome(
        tester,
        settings: configured.copyWith(autoProcessSnaps: true),
      );
      services.interpreter.result = sampleResult();
      services.sharedContentSource.emit(snapContent(snap));
      await tester.pumpAndSettle();
      expect(find.byType(_StubReview), findsOneWidget);
      expect(services.snapFileStore.deleted, isEmpty);

      await tester.tap(find.text('Stub export'));
      await tester.pumpAndSettle();
      // (Deleting twice is harmless: the real store skips missing files.)
      expect(services.snapFileStore.deleted.toSet(), {snap});
      expect(attachments, findsNothing);
    });

    testWidgets('review discarded: deleted and removed from the composer', (
      tester,
    ) async {
      final services = await pumpHome(
        tester,
        settings: configured.copyWith(autoProcessSnaps: true),
      );
      services.interpreter.result = sampleResult();
      services.sharedContentSource.emit(snapContent(snap));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stub back'));
      await tester.pumpAndSettle();

      expect(services.snapFileStore.deleted, [snap]);
      expect(attachments, findsNothing);
    });

    testWidgets('a snap replaced while the review is open waits for it', (
      tester,
    ) async {
      final services = await pumpHome(
        tester,
        settings: configured.copyWith(autoProcessSnaps: true),
      );
      services.interpreter.result = sampleResult();
      services.sharedContentSource.emit(snapContent(snap));
      await tester.pumpAndSettle();
      // Shared text replaces the composer behind the open review.
      services.sharedContentSource.emit(const SharedContent(text: 'Other'));
      await tester.pump();
      expect(services.snapFileStore.deleted, isEmpty);

      await tester.tap(find.text('Stub back'));
      await tester.pumpAndSettle();
      expect(services.snapFileStore.deleted, [snap]);
    });

    testWidgets('removing the chip deletes a snap but not a gallery image', (
      tester,
    ) async {
      final services = await pumpHome(tester);
      services.sharedContentSource
        ..emit(const SharedContent(images: [gallery]))
        ..emit(snapContent(snap));
      await tester.pumpAndSettle();
      expect(attachments, findsNWidgets(2));

      final removeButtons = find.byIcon(Icons.close);
      await tester.tap(removeButtons.at(1));
      await tester.pump();
      expect(services.snapFileStore.deleted, [snap]);

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
      expect(services.snapFileStore.deleted, [snap]); // gallery: untouched
      expect(attachments, findsNothing);
    });

    testWidgets('clearing the composer deletes the snap', (tester) async {
      final services = await pumpHome(tester);
      services.sharedContentSource.emit(snapContent(snap));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('composer_clear_button')));
      await tester.pump();

      expect(services.snapFileStore.deleted, [snap]);
      expect(attachments, findsNothing);
    });

    testWidgets('shared content replacing the composer deletes the snap', (
      tester,
    ) async {
      final services = await pumpHome(
        tester,
        settings: configured.copyWith(autoProcessShared: false),
      );
      services.sharedContentSource
        ..emit(snapContent(snap))
        ..emit(const SharedContent(text: 'Something else'));
      await tester.pumpAndSettle();
      expect(services.snapFileStore.deleted, [snap]);
    });
  });

  group('snap & crop', () {
    testWidgets('opens the crop screen; Use selection starts extraction '
        'without autoProcessSnaps', (tester) async {
      final services = await pumpHome(tester);
      services.interpreter.result = sampleResult();
      services.sharedContentSource.emit(snapContent(snap, crop: true));
      await pumpRoute(tester);
      expect(find.byType(CropScreen), findsOneWidget);
      expect(services.interpreter.calls, isEmpty);

      await tester.tap(find.byKey(CropScreen.useSelectionKey));
      await pumpRoute(tester);
      await tester.pumpAndSettle();

      final cropped = services.snapService.crops.single;
      expect(cropped.source, snap);
      expect(services.snapFileStore.deleted, [snap]); // full screenshot gone
      final input = services.interpreter.calls.single;
      expect(input.images.single.path, '/cache/snaps/crop_1.jpg');
      expect(input.images.single.isEphemeral, isTrue);
      expect(find.byType(_StubReview), findsOneWidget);
    });

    testWidgets('Cancel deletes the screenshot and returns to the composer', (
      tester,
    ) async {
      final services = await pumpHome(tester);
      services.sharedContentSource.emit(snapContent(snap, crop: true));
      await pumpRoute(tester);

      await tester.tap(find.byKey(CropScreen.cancelKey));
      await pumpRoute(tester);
      await tester.pumpAndSettle();

      expect(find.byType(CropScreen), findsNothing);
      expect(services.snapFileStore.deleted, [snap]);
      expect(services.interpreter.calls, isEmpty);
      expect(attachments, findsNothing);
    });

    testWidgets('a second snap during cropping is dropped', (tester) async {
      final services = await pumpHome(tester);
      services.sharedContentSource.emit(snapContent(snap, crop: true));
      await pumpRoute(tester);

      services.sharedContentSource.emit(snapContent(snap2));
      await tester.pump();
      expect(services.snapFileStore.deleted, [snap2]);
      expect(find.byType(CropScreen), findsOneWidget);
    });
  });
}
