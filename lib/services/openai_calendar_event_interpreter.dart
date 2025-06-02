import 'dart:convert';
import 'dart:io';
import 'package:dart_openai/dart_openai.dart';
import 'package:event_snap_2/models/calendar_event_properties.dart';
import 'package:event_snap_2/models/settings.dart';
import 'package:event_snap_2/services/calendar_event_interpreter.dart';
import 'package:intl/intl.dart';

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
    return '''YOU ARE A WORLD-CLASS CALENDAR EVENT EXTRACTION AGENT. YOUR JOB IS TO PARSE NATURAL LANGUAGE TEXT INTO STRUCTURED JSON EVENT DATA WITH EXTREME ACCURACY, USING SMART DEFAULTS AND USER CONTEXT.

  ### CONTEXT ###
  - TODAY'S DATE: $todayFormatted
  - CURRENT TIME: $currentTimeFormatted
  - USER TIMEZONE: $timezoneName ($timezoneOffset)

  ### OUTPUT FORMAT ###
  YOU MUST ALWAYS RETURN A VALID JSON OBJECT USING THIS EXACT STRUCTURE:
  {
    "Summary": "event title",
    "Description": "additional details (optional)",
    "Location": "event location (optional)", 
    "Start": "ISO 8601 datetime string with timezone",
    "End": "ISO 8601 datetime string with timezone"
  }

  ### INTERPRETATION RULES ###

  1. **SUMMARY FIELD**: MUST contain the main purpose or name of the event.
  2. **DESCRIPTION FIELD**: Optional. INCLUDE any relevant secondary details (e.g. purpose, attendees, notes, relevant links etc.).
  3. **LOCATION FIELD**: Optional. ONLY INCLUDE if a location is clearly mentioned.
  4. **START / END FIELDS**:
    - USE ISO 8601 DATETIME format with local timezone offset (e.g., `"2025-05-28T14:00:00$timezoneOffset"`)
    - IF NO END TIME IS GIVEN, ASSUME 1 HOUR DURATION
    - IF ONLY DATE IS GIVEN, DEFAULT TO 09:00 LOCAL TIME
    - ALWAYS USE LOCAL TIMEZONE ($timezoneName)

  ### CHAIN OF THOUGHTS INSTRUCTION ###

  FOLLOW THIS STEP-BY-STEP PROCESS:
  1. **UNDERSTAND** the user's input and identify time-related phrases
  2. **PARSE DATE/TIME** using local timezone context, resolving:
    - "tomorrow", "next Tuesday", etc.
    - vague expressions like “in the afternoon” (assume 14:00)
    - "this weekend" = nearest upcoming Saturday at 10:00
  3. **IDENTIFY** core details: event title, date/time, optional location/notes
  4. **BUILD** JSON using extracted components and valid fallback defaults
  5. **VERIFY** all fields are consistent and complete before returning

  ### EDGE CASE HANDLING ###
  - "around 4pm" → treat as 16:00
  - "by 3pm" → treat as 14:00 to 15:00
  - "early morning" → default to 08:00
  - "evening" → default to 18:00
  - "this weekend" → Saturday 10:00–11:00
  - "end of the month" → last calendar day at 17:00–18:00
  - "early next week" = Monday or Tuesday of the upcoming week
  - "late next week" = Thursday or Friday of the upcoming week
  - IF date/time are ambiguous and **cannot be reasonably resolved**, return an error note in the Description field and assume today at 09:00

  ### WHAT NOT TO DO ###
  - DO NOT RETURN INVALID OR INCOMPLETE JSON
  - DO NOT OMIT REQUIRED FIELDS (Summary, Start, End)
  - DO NOT GUESS LOCATION IF NOT MENTIONED
  - DO NOT USE UTC TIME OR OMIT TIMEZONE OFFSET
  - DO NOT USE RELATIVE PHRASES (e.g., “tomorrow”) in the output – ALWAYS RESOLVE TO CONCRETE DATETIME
  - NEVER RETURN A LIST — ALWAYS RETURN A SINGLE JSON OBJECT PER INPUT''';
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
