import 'package:event_snap_2/models/extraction.dart';
import 'package:event_snap_2/screens/crop_screen.dart';
import 'package:event_snap_2/services/platform/snap_service.dart';
import 'package:event_snap_2/themes/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../helpers/test_app.dart';

const _snap = InputImage(path: '/cache/snaps/snap_1.jpg', isEphemeral: true);

/// Opens the crop screen from a button and records what it pops with.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String result = 'none';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('result: $result'),
          TextButton(
            onPressed: () async {
              final image = await Navigator.of(context).push<InputImage>(
                MaterialPageRoute(
                  builder: (_) => const CropScreen(image: _snap),
                ),
              );
              setState(() => result = image?.path ?? 'cancelled');
            },
            child: const Text('Open crop'),
          ),
        ],
      ),
    );
  }
}

void main() {
  late TestServices services;

  Future<void> pumpCrop(WidgetTester tester) async {
    services = TestServices();
    await tester.pumpWidget(
      MultiProvider(
        providers: services.providers,
        child: MaterialApp(theme: AppTheme.light(), home: const _Host()),
      ),
    );
    await tester.tap(find.text('Open crop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The (missing) image file makes the crop widget report an error: it is
    // irrelevant here.
    tester.takeException();
  }

  testWidgets('shows the crop UI with Cancel and Use selection', (
    tester,
  ) async {
    await pumpCrop(tester);
    expect(find.text('Crop screenshot'), findsOneWidget);
    expect(find.byKey(const Key('crop_image')), findsOneWidget);
    expect(find.byKey(CropScreen.cancelKey), findsOneWidget);
    expect(find.byKey(CropScreen.useSelectionKey), findsOneWidget);
  });

  testWidgets('Use selection crops, deletes the full screenshot and returns '
      'the cropped image', (tester) async {
    await pumpCrop(tester);
    await tester.tap(find.byKey(CropScreen.useSelectionKey));
    await tester.pumpAndSettle();

    final crop = services.snapService.crops.single;
    expect(crop.source, _snap);
    expect(crop.region, const Rect.fromLTRB(0, 0, 1, 1));
    expect(services.snapFileStore.deleted, [_snap]);
    expect(find.text('result: /cache/snaps/crop_1.jpg'), findsOneWidget);
  });

  testWidgets('Cancel returns null and leaves the deletion to the caller', (
    tester,
  ) async {
    await pumpCrop(tester);
    await tester.tap(find.byKey(CropScreen.cancelKey));
    await tester.pumpAndSettle();

    expect(find.text('result: cancelled'), findsOneWidget);
    expect(services.snapService.crops, isEmpty);
    expect(services.snapFileStore.deleted, isEmpty);
  });

  testWidgets('a failed crop keeps the screen open and keeps the file', (
    tester,
  ) async {
    await pumpCrop(tester);
    services.snapService.cropFailure = const SnapException("Couldn't crop it");
    await tester.tap(find.byKey(CropScreen.useSelectionKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Couldn't crop it"), findsOneWidget);
    expect(find.byKey(CropScreen.useSelectionKey), findsOneWidget);
    expect(services.snapFileStore.deleted, isEmpty);
  });
}
