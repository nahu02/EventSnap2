import 'dart:convert';
import 'dart:io';
import 'package:dart_openai/dart_openai.dart';
import 'package:event_snap_2/models/calendar_event_properties.dart';
import 'package:event_snap_2/models/settings.dart';
import 'package:event_snap_2/services/calendar_event_interpreter.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';

/// OpenAI implementation of CalendarEventInterpreter
///
/// Uses the dart_openai SDK to communicate with OpenAI's GPT models
/// and extract structured calendar event information from natural language text.
class OpenAiCalendarEventInterpreter implements CalendarEventInterpreter {
  final Settings _settings;

  /// Creates an OpenAI calendar event interpreter with the given settings
  ///
  /// [settings] must contain a valid OpenAI API key
  OpenAiCalendarEventInterpreter(this._settings) {
    if (!_settings.hasApiKey) {
      throw ArgumentError('Settings must contain a valid OpenAI API key');
    }
    OpenAI.apiKey = _settings.openAiApiKey;
  }

  @override
  Future<CalendarEventProperties> eventToCalendarPropertiesAsync(
    String eventText,
  ) async {
    if (eventText.trim().isEmpty) {
      throw ArgumentError('Event text cannot be empty');
    }

    int retryCount = 0;
    while (retryCount <= _settings.maxRetries) {
      try {
        final chatCompletion = await OpenAI.instance.chat
            .create(
              model: _settings.openAiModel,
              messages: _createMessages(eventText),
              temperature: 0.2,
              maxTokens: 500,
              responseFormat: {"type": "json_object"},
            )
            .timeout(Duration(seconds: _settings.timeoutSeconds));

        final jsonResponse =
            chatCompletion.choices.first.message.content?.first.text;

        if (jsonResponse == null || jsonResponse.isEmpty) {
          throw FormatException('Empty response from OpenAI API');
        }

        return _parseJsonToCalendarProperties(jsonResponse);
      } on SocketException catch (e) {
        retryCount++;
        if (retryCount > _settings.maxRetries) {
          throw Exception(
            'Network error after ${_settings.maxRetries} retries: ${e.message}',
          );
        }
        await Future.delayed(
          Duration(seconds: retryCount * 2),
        ); // Exponential backoff
      } on HttpException catch (e) {
        retryCount++;
        if (retryCount > _settings.maxRetries) {
          throw Exception(
            'HTTP error after ${_settings.maxRetries} retries: ${e.message}',
          );
        }
        await Future.delayed(Duration(seconds: retryCount * 2));
      } on FormatException catch (e) {
        throw Exception('Failed to parse API response: ${e.message}');
      } on MissingApiKeyException catch (e) {
        // Don't retry missing API key errors
        throw Exception('OpenAI API key is missing: ${e.message}');
      } on RequestFailedException catch (e) {
        // Don't retry API failures (rate limits, quota exceeded, etc.)
        throw Exception('OpenAI API request failed: ${e.message}');
      } on OpenAIUnexpectedException catch (e) {
        // Don't retry unexpected API responses
        throw Exception('OpenAI API unexpected response: ${e.message}');
      } catch (e) {
        retryCount++;
        if (retryCount > _settings.maxRetries) {
          throw Exception(
            'Unexpected error after ${_settings.maxRetries} retries: $e',
          );
        }
        await Future.delayed(Duration(seconds: retryCount * 2));
      }
    }

    throw Exception('Maximum retries exceeded');
  }

  /// Creates the message list for the OpenAI chat completion
  List<OpenAIChatCompletionChoiceMessageModel> _createMessages(
    String eventText,
  ) {
    final now = DateTime.now();
    final todayFormatted = DateFormat('EEEE, MMMM d, yyyy').format(now);
    final currentTimeFormatted = DateFormat('h:mm a').format(now);
    final timezoneOffset = now.timeZoneOffset;
    final timezoneOffsetString = _formatTimezoneOffset(timezoneOffset);
    final timezoneName = now.timeZoneName;

    return [
      // System message with instructions
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.system,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(
            _getSystemPrompt(
              todayFormatted,
              currentTimeFormatted,
              timezoneOffsetString,
              timezoneName,
            ),
          ),
        ],
      ),

      // Example 1
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.user,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(
            "Team meeting tomorrow at 10am for 2 hours in conference room A",
          ),
        ],
      ),
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.assistant,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(
            _getExampleResponse1(now),
          ),
        ],
      ),

      // Example 2
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.user,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(
            "Dentist appointment next Tuesday at 2:30pm",
          ),
        ],
      ),
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.assistant,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(
            _getExampleResponse2(now),
          ),
        ],
      ),

      // Actual user input
      OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.user,
        content: [
          OpenAIChatCompletionChoiceMessageContentItemModel.text(eventText),
        ],
      ),
    ];
  }

  /// Generates the system prompt with current date context
  String _getSystemPrompt(
    String todayFormatted,
    String currentTimeFormatted,
    String timezoneOffset,
    String timezoneName,
  ) {
    return '''You are a calendar event extraction assistant. Extract calendar event information from natural language text and return it as JSON.

Current context:
- Today is: $todayFormatted
- Current time is: $currentTimeFormatted
- User timezone: $timezoneName ($timezoneOffset)

Rules:
1. Always return valid JSON with this exact structure:
{
  "Summary": "event title",
  "Description": "additional details (optional)",
  "Location": "event location (optional)", 
  "Start": "ISO 8601 datetime string with timezone",
  "End": "ISO 8601 datetime string with timezone"
}

2. Date/time interpretation:
   - "tomorrow" = next day from today
   - "next Tuesday" = the upcoming Tuesday after today
   - "at 2pm" = 14:00 in 24-hour format
   - If no end time specified, assume 1 hour duration
   - If no date specified, assume today
   - IMPORTANT: All times should be interpreted in the user's local timezone ($timezoneName), unless specified otherwise.
   - Use ISO 8601 format with timezone offset: "2025-05-28T14:00:00$timezoneOffset"

3. Field requirements:
   - Summary: Required, extract main event purpose
   - Description: Optional, include additional context
   - Location: Optional, only if mentioned
   - Start/End: Required, must be valid ISO 8601 datetime with timezone

4. If the text is unclear or missing critical information, make reasonable assumptions based on context.
5. When interpreting times like "4pm", this means 16:00 in the user's local timezone ($timezoneName), not UTC.''';
  }

  /// Generates example response 1 with dynamic dates
  String _getExampleResponse1(DateTime now) {
    final tomorrow = now.add(Duration(days: 1));
    final startTime = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      10,
      0,
    );
    final endTime = startTime.add(Duration(hours: 2));

    return jsonEncode({
      "Summary": "Team meeting",
      "Description": "Weekly team meeting to discuss project progress",
      "Location": "Conference room A",
      "Start": _formatDateTimeWithTimezone(startTime),
      "End": _formatDateTimeWithTimezone(endTime),
    });
  }

  /// Generates example response 2 with dynamic dates
  String _getExampleResponse2(DateTime now) {
    // Find next Tuesday
    DateTime nextTuesday = now.add(Duration(days: 1));
    while (nextTuesday.weekday != DateTime.tuesday) {
      nextTuesday = nextTuesday.add(Duration(days: 1));
    }

    final startTime = DateTime(
      nextTuesday.year,
      nextTuesday.month,
      nextTuesday.day,
      14,
      30,
    );
    final endTime = startTime.add(Duration(hours: 1));

    return jsonEncode({
      "Summary": "Dentist appointment",
      "Description": null,
      "Location": null,
      "Start": _formatDateTimeWithTimezone(startTime),
      "End": _formatDateTimeWithTimezone(endTime),
    });
  }

  /// Formats timezone offset as +HH:MM or -HH:MM
  String _formatTimezoneOffset(Duration offset) {
    final hours = offset.inHours;
    final minutes = offset.inMinutes.remainder(60).abs();
    final sign = hours >= 0 ? '+' : '-';
    return '$sign${hours.abs().toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  /// Formats a DateTime with local timezone offset
  String _formatDateTimeWithTimezone(DateTime dateTime) {
    final offset = dateTime.timeZoneOffset;
    final offsetString = _formatTimezoneOffset(offset);
    return '${dateTime.toIso8601String().split('.')[0]}$offsetString';
  }

  /// Parses JSON response from OpenAI into CalendarEventProperties
  CalendarEventProperties _parseJsonToCalendarProperties(String jsonResponse) {
    try {
      final Map<String, dynamic> json = jsonDecode(jsonResponse);
      return CalendarEventProperties.fromJson(json);
    } catch (e) {
      throw FormatException(
        'Failed to parse JSON response: $e\nResponse: $jsonResponse',
      );
    }
  }
}
