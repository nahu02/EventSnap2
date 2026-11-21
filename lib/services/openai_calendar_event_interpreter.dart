import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_openai/dart_openai.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/event_model.dart';
import '../models/settings.dart';
import 'ai/ai_exceptions.dart';

/// Output of [OpenAiCalendarEventInterpreter.extractEventsFromText].
class LegacyOpenAiExtraction {
  final List<EventModel> events;
  final List<String> warnings;
  final String rawResponse;

  const LegacyOpenAiExtraction({
    required this.events,
    required this.warnings,
    required this.rawResponse,
  });
}

/// TEMPORARY v2 OpenAI interpreter (dart_openai, JSON mode, text only).
///
/// Used only through `LegacyAiServiceFactory`. Workstream B replaces it with
/// the `http`-based multi-provider client and deletes this file together with
/// the `dart_openai` dependency.
class OpenAiCalendarEventInterpreter {
  final Settings _settings;

  /// Creates an interpreter for the OpenAI key/model in [settings].
  ///
  /// Throws [ArgumentError] if no OpenAI API key is configured.
  OpenAiCalendarEventInterpreter(this._settings) {
    if (_settings.openAiApiKey.trim().isEmpty) {
      throw ArgumentError('Settings must contain a valid OpenAI API key');
    }
    OpenAI.apiKey = _settings.openAiApiKey.trim();
  }

  String get _model => _settings.openAiModel.trim();

  /// Reasoning models reject non-default `temperature` and `max_tokens`.
  @visibleForTesting
  static bool isReasoningModel(String model) {
    final id = model.toLowerCase();
    return RegExp(r'^o\d').hasMatch(id) ||
        id.startsWith('gpt-5') ||
        id.startsWith('gpt-6');
  }

  /// Extracts zero or more events from [eventText].
  ///
  /// Throws [ArgumentError] for blank text and [AiException] for everything
  /// else.
  Future<LegacyOpenAiExtraction> extractEventsFromText(String eventText) async {
    if (eventText.trim().isEmpty) {
      throw ArgumentError('Event text cannot be empty');
    }

    final reasoning = isReasoningModel(_model);
    var attempt = 0;
    while (true) {
      try {
        final chatCompletion = await OpenAI.instance.chat
            .create(
              model: _model,
              messages: _createMessages(eventText),
              temperature: reasoning ? null : 0.3,
              maxTokens: reasoning ? null : 1500,
              responseFormat: {"type": "json_object"},
            )
            .timeout(_settings.timeoutDuration);

        final raw = chatCompletion.choices.first.message.content?.first.text;
        if (raw == null || raw.trim().isEmpty) {
          throw const AiException(
            AiErrorKind.invalidResponse,
            'Empty response from OpenAI API',
          );
        }
        return parseEventsResponse(raw);
      } on AiException {
        rethrow;
      } on RequestFailedException catch (e) {
        final mapped = mapRequestFailure(e);
        if (!_isRetryable(mapped.kind) || attempt >= _settings.maxRetries) {
          throw mapped;
        }
      } on TimeoutException catch (e) {
        if (attempt >= _settings.maxRetries) {
          throw AiException(
            AiErrorKind.timeout,
            'OpenAI request timed out after ${_settings.timeoutSeconds}s',
            cause: e,
          );
        }
      } on SocketException catch (e) {
        if (attempt >= _settings.maxRetries) {
          throw AiException(AiErrorKind.network, e.message, cause: e);
        }
      } on HttpException catch (e) {
        if (attempt >= _settings.maxRetries) {
          throw AiException(AiErrorKind.network, e.message, cause: e);
        }
      } on MissingApiKeyException catch (e) {
        throw AiException(AiErrorKind.notConfigured, e.message, cause: e);
      } on OpenAIUnexpectedException catch (e) {
        throw AiException(AiErrorKind.invalidResponse, e.message, cause: e);
      } catch (e) {
        if (attempt >= _settings.maxRetries) {
          throw AiException(AiErrorKind.unknown, e.toString(), cause: e);
        }
      }
      attempt++;
      await Future<void>.delayed(Duration(seconds: attempt * 2));
    }
  }

  static bool _isRetryable(AiErrorKind kind) =>
      kind == AiErrorKind.rateLimited ||
      kind == AiErrorKind.server ||
      kind == AiErrorKind.network ||
      kind == AiErrorKind.timeout;

  /// Maps a dart_openai HTTP failure to an [AiException].
  static AiException mapRequestFailure(RequestFailedException e) {
    final message = e.message;
    final lower = message.toLowerCase();
    final status = e.statusCode;
    final AiErrorKind kind;
    if (status == 401 || status == 403) {
      kind = AiErrorKind.auth;
    } else if (status == 404 ||
        lower.contains('model_not_found') ||
        (lower.contains('model') && lower.contains('does not exist'))) {
      kind = AiErrorKind.modelNotFound;
    } else if (status == 429) {
      kind = lower.contains('quota') || lower.contains('billing')
          ? AiErrorKind.quotaExceeded
          : AiErrorKind.rateLimited;
    } else if (status >= 500) {
      kind = AiErrorKind.server;
    } else if (status == 400 &&
        (lower.contains('image') || lower.contains('vision'))) {
      kind = AiErrorKind.unsupportedInput;
    } else {
      kind = AiErrorKind.unknown;
    }
    return AiException(kind, message, statusCode: status, cause: e);
  }

  /// Parses the model's JSON (`{"events": [...]}`, a bare array or a single
  /// event object). Events that cannot be converted are skipped with a
  /// warning. Throws `AiException(invalidResponse)` for non-JSON content.
  @visibleForTesting
  static LegacyOpenAiExtraction parseEventsResponse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(_stripCodeFences(raw));
    } on FormatException catch (e) {
      throw AiException(
        AiErrorKind.invalidResponse,
        'Failed to parse JSON response: ${e.message}',
        cause: e,
      );
    }

    final List<Object?> items;
    if (decoded is Map && decoded['events'] is List) {
      items = List<Object?>.from(decoded['events'] as List);
    } else if (decoded is List) {
      items = List<Object?>.from(decoded);
    } else if (decoded is Map) {
      items = [decoded];
    } else {
      throw AiException(
        AiErrorKind.invalidResponse,
        'Unexpected JSON structure: ${decoded.runtimeType}',
      );
    }

    final events = <EventModel>[];
    final warnings = <String>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map) {
        warnings.add('Skipped event ${i + 1}: not a JSON object.');
        continue;
      }
      try {
        events.add(_eventFromJson(Map<String, dynamic>.from(item)));
      } catch (e) {
        warnings.add('Skipped event ${i + 1}: $e');
      }
    }
    return LegacyOpenAiExtraction(
      events: events,
      warnings: warnings,
      rawResponse: raw,
    );
  }

  static String _stripCodeFences(String raw) {
    final trimmed = raw.trim();
    final fence = RegExp(r'^```[a-zA-Z]*\s*([\s\S]*?)\s*```$');
    final match = fence.firstMatch(trimmed);
    return match != null ? match.group(1)! : trimmed;
  }

  static String? _str(Map<String, dynamic> json, String key) {
    final value = json[key] ?? json[key.toLowerCase()];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static EventModel _eventFromJson(Map<String, dynamic> json) {
    final title = _str(json, 'Summary') ?? _str(json, 'Title');
    final startRaw = _str(json, 'Start');
    if (startRaw == null) {
      throw const FormatException('missing start time');
    }
    final start = DateTime.parse(startRaw).toLocal();
    final endRaw = _str(json, 'End');
    var end = endRaw != null ? DateTime.parse(endRaw).toLocal() : null;
    if (end == null || !end.isAfter(start)) {
      end = start.add(const Duration(hours: 1));
    }
    return EventModel(
      title: title ?? 'Untitled event',
      description: _str(json, 'Description'),
      location: _str(json, 'Location'),
      startDateTime: start,
      endDateTime: end,
    );
  }

  /// Creates the message list for the OpenAI chat completion
  List<OpenAIChatCompletionChoiceMessageModel> _createMessages(
    String eventText,
  ) {
    final now = DateTime.now();
    final todayFormatted = DateFormat('EEEE, MMMM d, yyyy').format(now);
    final currentTimeFormatted = DateFormat('h:mm a').format(now);
    final timezoneOffsetString = _formatTimezoneOffset(now.timeZoneOffset);
    final timezoneName = now.timeZoneName;

    OpenAIChatCompletionChoiceMessageModel message(
      OpenAIChatMessageRole role,
      String text,
    ) => OpenAIChatCompletionChoiceMessageModel(
      role: role,
      content: [OpenAIChatCompletionChoiceMessageContentItemModel.text(text)],
    );

    return [
      message(
        OpenAIChatMessageRole.system,
        _getSystemPrompt(
          todayFormatted,
          currentTimeFormatted,
          timezoneOffsetString,
          timezoneName,
        ),
      ),
      message(
        OpenAIChatMessageRole.user,
        "Team meeting tomorrow at 10am for 2 hours in conf room A. Also, Dentist appointment next Tuesday at 2:30pm.",
      ),
      message(
        OpenAIChatMessageRole.assistant,
        _getMultipleEventsExampleResponse(now),
      ),
      message(OpenAIChatMessageRole.user, eventText),
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
  YOU MUST ALWAYS RETURN A VALID JSON OBJECT WITH A SINGLE KEY "events", WHICH IS AN ARRAY WITH ONE OBJECT PER DISTINCT EVENT. EACH OBJECT MUST USE THIS EXACT STRUCTURE:
  {
    "Summary": "event title",
    "Description": "additional details (optional)",
    "Location": "event location (optional)",
    "Start": "ISO 8601 datetime string with timezone",
    "End": "ISO 8601 datetime string with timezone"
  }
  IF NO EVENTS ARE FOUND, RETURN AN EMPTY ARRAY: {"events": []}

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
  1. **IDENTIFY** the distinct calendar events. Distinct times, dates, or locations are a good indicator of separate events. The input may contain a single event.
  2. **FOR EACH EVENT**:
     a. **UNDERSTAND** the user's input and identify time-related phrases for that specific event.
     b. **PARSE DATE/TIME** using local timezone context, resolving:
        - "tomorrow", "next Tuesday", etc.
        - vague expressions like "in the afternoon" (assume 14:00)
        - "this weekend" = nearest upcoming Saturday at 10:00
     c. **IDENTIFY** core details: event title, date/time, optional location/notes for that specific event.
     d. **BUILD** JSON for that specific event using extracted components and valid fallback defaults.
  3. **AGGREGATE** all event objects into the "events" array.
  4. **VERIFY** all fields for all events are consistent and complete before returning the final JSON structure.

  ### EDGE CASE HANDLING ###
  - "around 4pm" → treat as 16:00
  - "by 3pm" → treat as 14:00 to 15:00
  - "early morning" → default to 08:00
  - "evening" → default to 18:00
  - "this weekend" → Saturday 10:00–11:00
  - "end of the month" → last calendar day at 17:00–18:00
  - "early next week" = Monday or Tuesday of the upcoming week
  - "late next week" = Thursday or Friday of the upcoming week
  - IF date/time are ambiguous for an event and **cannot be reasonably resolved**, return an error note in its Description field and assume today at 09:00 for that event.

  ### WHAT NOT TO DO ###
  - DO NOT RETURN INVALID OR INCOMPLETE JSON
  - DO NOT OMIT REQUIRED FIELDS (Summary, Start, End) FOR EACH EVENT
  - DO NOT GUESS LOCATION IF NOT MENTIONED
  - DO NOT USE UTC TIME OR OMIT TIMEZONE OFFSET
  - DO NOT USE RELATIVE PHRASES (e.g., "tomorrow") in the output – ALWAYS RESOLVE TO CONCRETE DATETIME
  - DO NOT GROUP MULTIPLE SEPARATE EVENTS INTO A SINGLE JSON OBJECT''';
  }

  /// Generates an example response for multiple events with dynamic dates
  String _getMultipleEventsExampleResponse(DateTime now) {
    final tomorrow = now.add(const Duration(days: 1));
    final event1StartTime = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      10,
      0,
    );
    final event1EndTime = event1StartTime.add(const Duration(hours: 2));

    var nextTuesday = now.add(const Duration(days: 1));
    while (nextTuesday.weekday != DateTime.tuesday) {
      nextTuesday = nextTuesday.add(const Duration(days: 1));
    }
    final event2StartTime = DateTime(
      nextTuesday.year,
      nextTuesday.month,
      nextTuesday.day,
      14,
      30,
    );
    final event2EndTime = event2StartTime.add(const Duration(hours: 1));

    return jsonEncode({
      "events": [
        {
          "Summary": "Team meeting",
          "Description": "Weekly team meeting to discuss project progress",
          "Location": "Conference room A",
          "Start": _formatDateTimeWithTimezone(event1StartTime),
          "End": _formatDateTimeWithTimezone(event1EndTime),
        },
        {
          "Summary": "Dentist appointment",
          "Description": "",
          "Location": "",
          "Start": _formatDateTimeWithTimezone(event2StartTime),
          "End": _formatDateTimeWithTimezone(event2EndTime),
        },
      ],
    });
  }

  /// Formats timezone offset as +HH:MM or -HH:MM
  static String _formatTimezoneOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final hours = abs.inHours.toString().padLeft(2, '0');
    final minutes = abs.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$sign$hours:$minutes';
  }

  /// Formats a DateTime with local timezone offset
  static String _formatDateTimeWithTimezone(DateTime dateTime) {
    final offsetString = _formatTimezoneOffset(dateTime.timeZoneOffset);
    return '${dateTime.toIso8601String().split('.')[0]}$offsetString';
  }
}
