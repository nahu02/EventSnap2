// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:event_snap_2/main.dart';
import 'package:event_snap_2/models/event_model.dart';
import 'package:event_snap_2/widgets/event_form.dart';

void main() {
  testWidgets('App launches without errors', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const EventSnapApp());

    // Verify that the app launches successfully
    expect(find.text('EventSnap'), findsOneWidget);
  });

  testWidgets('EventForm renders without errors', (WidgetTester tester) async {
    // Create a dummy EventModel for the EventForm.
    final initialEvent = EventModel(
      title: 'Test Event',
      startDateTime: DateTime.now(),
      endDateTime: DateTime.now().add(const Duration(hours: 1)),
    );

    // Build the EventForm widget.
    await tester.pumpWidget(
      MaterialApp(
        // Required for Directionality, Theme, etc.
        home: Scaffold(body: EventForm(initialEvent: initialEvent)),
      ),
    );

    // Verify that the EventForm renders successfully by checking for a common element, e.g., the title field.
    expect(find.text('Test Event'), findsOneWidget);
  });
}
