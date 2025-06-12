import 'dart:io';
import 'package:ical/serializer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:event_snap_2/models/calendar_event_properties.dart';
import 'package:event_snap_2/services/calendar_creator.dart';
import 'package:event_snap_2/services/android_calendar_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

/// iCalendar implementation of CalendarCreator
///
/// Uses the ical package to generate RFC 5545 compliant .ics files
/// from calendar event data. Files are saved to the app's temporary
/// directory and can be shared with calendar applications.
class ICalendarCreator implements CalendarCreator {
  @override
  Future<String> createIcalFile(CalendarEventProperties properties) async {
    // This method will now call the new method that handles a list of properties.
    // For backward compatibility, it wraps the single property in a list.
    return createIcalFileWithMultipleEvents([properties]);
  }

  /// Creates an iCalendar (.ics) file from a list of calendar event properties
  ///
  /// Takes a list of [propertiesList] containing event data for multiple events
  /// and returns the absolute file path to the generated .ics file.
  @override
  Future<String> createIcalFileWithMultipleEvents(
    List<CalendarEventProperties> propertiesList,
  ) async {
    if (propertiesList.isEmpty) {
      throw ArgumentError('Properties list cannot be empty.');
    }

    try {
      // Create the calendar container
      final calendar = ICalendar();

      for (final properties in propertiesList) {
        // Validate input properties
        final validationErrors = properties.validate();
        if (validationErrors.isNotEmpty) {
          throw ArgumentError(
            'Invalid calendar event properties: ${validationErrors.join(', ')} for event "${properties.summary ?? 'Unnamed Event'}"',
          );
        }

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
      }

      // Get the temporary directory for saving the file
      final tempDir = await getTemporaryDirectory();
      final fileName = 'events_${DateTime.now().millisecondsSinceEpoch}.ics';
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
  /// On Android, uses the native FileProvider system for secure file sharing
  /// with better calendar app compatibility. Falls back to url_launcher on
  /// other platforms or if the Android method fails.
  ///
  /// Returns true if the file was successfully shared, false otherwise.
  Future<bool> shareIcalFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw FileSystemException('iCalendar file does not exist', filePath);
      }

      // On Android, use the native calendar service for better integration
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          // First check if there are calendar apps available
          final hasApps = await AndroidCalendarService.hasCalendarApps();
          if (!hasApps) {
            return false;
          }

          // Attempt to share using Android's native method
          final success = await AndroidCalendarService.shareCalendarFile(
            filePath,
          );
          return success;
        } catch (e) {
          // If Android method fails, fall through to url_launcher
          debugPrint(
            'Android calendar service failed, falling back to url_launcher: $e',
          );
        }
      }

      // Fallback to url_launcher for other platforms or if Android method fails
      final uri = Uri.file(filePath);
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

  /// Check if calendar applications are available on the device
  ///
  /// Returns true if there are applications that can handle calendar files,
  /// false otherwise. This can be used to provide appropriate user feedback
  /// when no calendar apps are available.
  ///
  /// On Android, uses the native platform service to check for calendar apps.
  /// On other platforms, assumes calendar apps are available.
  Future<bool> hasCalendarApps() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await AndroidCalendarService.hasCalendarApps();
      }

      // On other platforms, assume calendar apps are available
      return true;
    } catch (e) {
      // If we can't check, assume there might be apps available
      return true;
    }
  }
}
