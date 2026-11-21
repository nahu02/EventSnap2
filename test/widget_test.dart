import 'package:event_snap_2/main.dart';
import 'package:event_snap_2/models/event_model.dart';
import 'package:event_snap_2/widgets/event_form.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets('App launches without errors', (WidgetTester tester) async {
    final sharedContentSource = FakeSharedContentSource();
    await tester.pumpWidget(
      EventSnapApp(
        settingsService: InMemorySettingsService(),
        aiServiceFactory: FakeAiServiceFactory(),
        sharedContentSource: sharedContentSource,
        imageInputService: FakeImageInputService(),
        calendarCreator: FakeCalendarCreator(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EventSnap'), findsOneWidget);
    expect(sharedContentSource.initialCalls, 1);
  });

  testWidgets('App launches with the default services', (tester) async {
    // Real SecureSettingsService over mocked storage plugins.
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const EventSnapApp());
    await tester.pumpAndSettle();
    expect(find.text('EventSnap'), findsOneWidget);
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
