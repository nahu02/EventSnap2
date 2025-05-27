import 'package:flutter/material.dart';
import '../navigation/app_router.dart';

/// Placeholder screen for event text input
///
/// This will be fully implemented in Step 9.
/// For now, provides basic structure and navigation.
class EventTextInputScreen extends StatelessWidget {
  const EventTextInputScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Event from Text'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => AppRouter.goBack(context),
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.text_fields, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Event Text Input',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'This screen will be implemented in Step 9.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
