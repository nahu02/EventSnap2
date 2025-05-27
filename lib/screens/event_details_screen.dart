import 'package:flutter/material.dart';
import '../navigation/app_router.dart';

/// Placeholder screen for event details
///
/// This will be fully implemented in Step 10.
/// For now, provides basic structure and navigation.
class EventDetailsScreen extends StatelessWidget {
  final dynamic initialEvent;

  const EventDetailsScreen({super.key, this.initialEvent});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Details'),
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
              Icon(Icons.event, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Event Details',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'This screen will be implemented in Step 10.',
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
