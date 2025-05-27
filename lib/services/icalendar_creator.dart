import 'dart:io';
import 'package:ical/serializer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:event_snap_2/models/calendar_event_properties.dart';
import 'package:event_snap_2/services/calendar_creator.dart';
import 'package:url_launcher/url_launcher.dart';

/// iCalendar implementation of CalendarCreator
///
/// Uses the ical package to generate RFC 5545 compliant .ics files
/// from calendar event data. Files are saved to the app's temporary
/// directory and can be shared with calendar applications.
class ICalendarCreator implements CalendarCreator {
  @override
  Future<String> createIcalFile(CalendarEventProperties properties) async {
    // Validate input properties
    final validationErrors = properties.validate();
    if (validationErrors.isNotEmpty) {
      throw ArgumentError(
        'Invalid calendar event properties: ${validationErrors.join(', ')}',
      );
    }

    try {
      // Create the calendar container
      final calendar = ICalendar();

      // Parse start and end times
      final DateTime startDateTime;
      final DateTime endDateTime;

      if (properties.start != null) {
        startDateTime = DateTime.parse(properties.start!);
      } else {
        throw ArgumentError('Start time is required for calendar events');
      }

      if (properties.end != null) {
        endDateTime = DateTime.parse(properties.end!);
      } else {
        // Default to 1 hour after start time if no end time provided
        endDateTime = startDateTime.add(const Duration(hours: 1));
      }

      // Generate unique UID for the event
      final uid = _generateUniqueUid();

      // Create the event
      final event = IEvent(
        summary: properties.summary ?? 'Untitled Event',
        description: properties.description,
        location: properties.location,
        start: startDateTime,
        end: endDateTime,
        uid: uid,
        status: IEventStatus.CONFIRMED,
      );

      // Add the event to the calendar
      calendar.addElement(event);

      // Get the temporary directory for saving the file
      final tempDir = await getTemporaryDirectory();
      final fileName = 'event_${DateTime.now().millisecondsSinceEpoch}.ics';
      final filePath = '${tempDir.path}/$fileName';

      // Serialize the calendar to iCalendar format
      final icalContent = calendar.serialize();

      // Save to file
      final file = File(filePath);
      await file.writeAsString(icalContent);

      return filePath;
    } catch (e) {
      // Re-throw ArgumentError exceptions to preserve their type for validation
      if (e is ArgumentError) {
        rethrow;
      }
      throw Exception('Failed to create iCalendar file: $e');
    }
  }

  /// Shares the generated .ics file with calendar applications
  ///
  /// Takes the [filePath] returned from createIcalFile and uses the
  /// platform's file sharing mechanism to open it with calendar apps.
  ///
  /// Returns true if the file was successfully shared, false otherwise.
  Future<bool> shareIcalFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw FileSystemException('iCalendar file does not exist', filePath);
      }

      // Create a file URI for sharing
      final uri = Uri.file(filePath);

      // Launch the file with the default calendar application
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      return launched;
    } catch (e) {
      throw Exception('Failed to share iCalendar file: $e');
    }
  }

  /// Generates a unique identifier for calendar events
  ///
  /// Creates a UID following RFC 5545 recommendations using
  /// current timestamp and a domain-like suffix.
  String _generateUniqueUid() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecond;
    return '$timestamp-$random@eventsnap.app';
  }

  /// Validates that the temporary directory is accessible
  ///
  /// Throws an exception if the temporary directory cannot be accessed
  /// or created. Used internally for debugging file system issues.
  Future<void> validateTemporaryDirectory() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) {
        throw FileSystemException(
          'Temporary directory does not exist',
          tempDir.path,
        );
      }
    } catch (e) {
      throw Exception('Failed to access temporary directory: $e');
    }
  }
}
