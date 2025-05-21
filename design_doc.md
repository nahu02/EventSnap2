# EventSnap Design Document for Flutter Implementation

## Project Overview

EventSnap is a mobile application designed to create calendar events from natural language text. It leverages AI (specifically OpenAI's GPT models) to interpret a user's textual description of an event and transform it into a structured calendar event, which can then be exported as an iCalendar (.ics) file for import into various calendar applications.

## Core Features

1. **Natural Language Processing of Event Text**
   - Accept text input describing events in natural language
   - Process text using OpenAI's GPT models to extract event details
   - Support for event properties: title, description, location, start time, end time

2. **Event Editing**
   - Display extracted event details in an editable form
   - Allow users to modify any incorrectly extracted information
   - Validate event data (e.g., require title, ensure end time is after start time)

3. **Calendar Integration**
   - Generate standard iCalendar (.ics) files from event data
   - Allow adding events to the device's calendar app

4. **Android Share Integration**
   - Receive shared text from other applications
   - Process shared text as event descriptions

5. **Settings Management**
   - Store and retrieve OpenAI API keys
   - Configure AI model settings

## Architecture

The application should be structured using a clean architecture approach with three main modules:

### 1. UI Module (Flutter Application)

**Responsibilities:**
- Present user interface for event input, display, and editing
- Handle navigation between screens
- Receive and process shared text from other apps
- Manage application settings
- Coordinate between AI and iCalendar services

**Key Components:**
- **Screens:**
  - `EventTextScreen`: Main screen showing natural language text input field
  - `EventDetailsScreen`: Screen showing event form and edit capabilities
  - `SettingsScreen`: Configuration for API keys and model selection
  - `LoadingScreen`: Display during AI processing or file operations

- **State Management:**
  - Manage application state for event data, settings, and processing status
  - Handle loading states during API calls

- **Platform Integration:**
  - Implement Android Intent filters to receive shared text
  - Integrate with device calendar applications

### 2. AI Communication Module

**Responsibilities:**
- Send natural language text to OpenAI API via the dart_openai SDK
- Parse API responses into structured event data
- Handle API errors and retries

**Key Components:**
- **CalendarEventInterpreter Interface:**
  - Define contract for event interpretation services
  - Allow for potential future AI service providers beyond OpenAI

- **OpenAI Implementation using dart_openai:**
  - Configure the SDK with API keys and model settings
  - Construct appropriate prompts and messages
  - Process responses into event objects

### 3. iCalendar Creation Module

**Responsibilities:**
- Generate valid iCalendar (.ics) files from event data
- Handle date/time formatting according to iCalendar standards

**Key Components:**
- **CalendarCreator Interface:**
  - Define contract for calendar file creation
  - Allow for potential future calendar format support

- **iCalendar Implementation:**
  - Format event data according to RFC 5545 (iCalendar spec)
  - Generate and save .ics files

## Data Models

### EventModel
```dart
class EventModel {
  String title;          // Required
  String? description;   // Optional
  String? location;      // Optional
  DateTime startDateTime;
  DateTime endDateTime;
}
```

### CalendarEventProperties
```dart
class CalendarEventProperties {
  String? summary;       // Event title
  String? description;
  String? location;
  String? start;         // ISO 8601 formatted datetime
  String? end;           // ISO 8601 formatted datetime
}
```

### Settings
```dart
class Settings {
  String openAiApiKey;
  String openAiModel;    // Default: "gpt-4.1"
}
```

## Technical Implementation Details

### Flutter UI Implementation

1. **Material Design 3 (MD3) UI**
   - Use Flutter's Material widgets for consistent design
   - Implement form validation for event details

2. **Shared Text Handling**
   - Register app as share target on Android using `android:exported="true"` and `<intent-filter>` in AndroidManifest.xml
   - Process incoming shared text in `MainActivity` and pass to Flutter using method channels

3. **iCalendar File Handling**
   - Generate .ics files in app's cache directory
   - Use platform-specific file sharing mechanisms to open the file with the default calendar app

4. **Settings Persistence**
   - Use Flutter's `shared_preferences` package for storing settings
   - Securely store API keys using flutter_secure_storage

### AI Integration with dart_openai SDK

1. **SDK Setup and Configuration**
   - Add `dart_openai: ^x.y.z` to pubspec.yaml
   - Configure the SDK with the user's API key:
     ```dart
     OpenAI.apiKey = settings.openAiApiKey;
     ```

2. **Chat Completion Implementation**
   - Use the SDK's structured API to create chat completions:
     ```dart
     final chatCompletion = await OpenAI.instance.chat.create(
       model: settings.openAiModel,
       messages: [
         OpenAIChatCompletionChoiceMessageModel(
           role: OpenAIChatMessageRole.system,
           content: [
             OpenAIChatCompletionChoiceMessageContentItemModel.text(
               systemPrompt,
             ),
           ],
         ),
         // Add example messages here
         OpenAIChatCompletionChoiceMessageModel(
           role: OpenAIChatMessageRole.user,
           content: [
             OpenAIChatCompletionChoiceMessageContentItemModel.text(
               eventText,
             ),
           ],
         ),
       ],
     );
     ```

3. **Prompt Engineering**
   - Include specific system instructions to generate structured JSON output
   - Provide examples showing input text and expected JSON output
   - Design prompts to handle date/time interpretation relative to current date

### iCalendar Generation

1. **iCalendar Format Implementation Using `ical` Package**
   - Use the `ical` package for handling iCalendar format and generation
   - Handle timezone information correctly
   - Include all required iCalendar properties (UID, DTSTAMP, etc.)
   - Utilize the ICalendar, IEvent, and related classes for structured calendar creation

2. **File Integration**
   - Create temporary .ics files in app cache using the serialized output from the ical library
   - Use platform-specific intent/URL launching to open files with default calendar app

## API and Service Interfaces

### AI Service Interface

```dart
abstract class CalendarEventInterpreter {
  Future<CalendarEventProperties> eventToCalendarPropertiesAsync(String eventText);
}

class OpenAiCalendarEventInterpreter implements CalendarEventInterpreter {
  final String apiKey;
  String modelName = "gpt-4.1";
  
  OpenAiCalendarEventInterpreter(this.apiKey) {
    OpenAI.apiKey = apiKey;
  }
  
  @override
  Future<CalendarEventProperties> eventToCalendarPropertiesAsync(String eventText) async {
    // Implementation using dart_openai SDK
    final chatCompletion = await OpenAI.instance.chat.create(
      model: modelName,
      messages: createMessages(eventText),
      temperature: 0.2,
    );
    
    // Parse the response
    final jsonResponse = chatCompletion.choices.first.message.content;
    return parseJsonToCalendarProperties(jsonResponse);
  }
  
  List<OpenAIChatCompletionChoiceMessageModel> createMessages(String eventText) {
    // Create system and example messages here
    // Return structured messages for the chat completion
  }
}
```

### iCalendar Service Interface

```dart
import 'package:ical/ical.dart';
import 'package:ical/serializer.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

abstract class CalendarCreator {
  Future<String> createIcalFile(CalendarEventProperties properties);
}

class ICalendarCreator implements CalendarCreator {
  @override
  Future<String> createIcalFile(CalendarEventProperties properties) async {
    // Implementation using the ical package
    final ICalendar calendar = ICalendar();
    
    // Create event from properties
    final event = IEvent(
      summary: properties.summary,
      description: properties.description,
      location: properties.location,
      start: DateTime.parse(properties.start ?? DateTime.now().toIso8601String()),
      end: DateTime.parse(properties.end ?? DateTime.now().add(Duration(hours: 1)).toIso8601String()),
      uid: '${DateTime.now().millisecondsSinceEpoch}@eventsnap.app',
      status: IEventStatus.CONFIRMED,
    );
    
    // Add the event to calendar
    calendar.addElement(event);
    
    // Serialize to iCalendar format
    final String icalContent = calendar.serialize();
    
    // Save to a temporary file
    final directory = await getTemporaryDirectory();
    final filePath = '${directory.path}/event.ics';
    final file = File(filePath);
    await file.writeAsString(icalContent);
    
    return filePath;
  }
}
```

## User Flow

1. **App Launch**
   - User opens app directly or shares text to the app from another application
   - If launched via share, text is automatically processed
   - If launched directly, user can type in their text, must press submit to begin processing

2. **Event Processing**
   - App shows loading indicator
   - Shared or entered text is sent to OpenAI via dart_openai SDK
   - Response is parsed into event details

3. **Event Review and Edit**
   - Extracted event details are displayed in editable form
   - User can modify any fields as needed
   - Form validates required fields

4. **Calendar Addition**
   - User taps "Add to Calendar" button
   - App generates .ics file
   - System dialog opens to choose calendar app
   - Event is imported into chosen calendar

5. **Settings Management**
   - User can access settings screen to configure API keys
   - Settings are saved securely and persisted between app launches

## Android Platform-Specific Implementation

### AndroidManifest.xml Configuration

```xml
<manifest ...>
    <application ...>
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTask"
            ...>
            
            <!-- Normal activity intent filters -->
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            
            <!-- Share text intent filter -->
            <intent-filter>
                <action android:name="android.intent.action.SEND"/>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <data android:mimeType="text/plain"/>
            </intent-filter>
        </activity>
    </application>

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
</manifest>
```

### Receiving Shared Text in Flutter

Set up method channel to receive shared text from native Android code:

```dart
const platform = MethodChannel('app.eventsnap/shared_text');

platform.setMethodCallHandler((call) async {
  if (call.method == 'handleSharedText') {
    final String sharedText = call.arguments;
    // Process shared text
    processEventText(sharedText);
  }
});
```

## OpenAI Prompt Engineering

This is a critical part of the implementation. The OpenAI API needs specific prompting to ensure it returns properly structured event data. Here's the recommended prompt structure to use with the dart_openai SDK:

```dart
final systemPrompt = """
You are an assistant helping the user create calendar events.
The user will tell you about an event they want to add to their calendar and you create the event for them.
The events must be in a JSON format, and may include a Summary, a Start, an End, a Location and a Description.
If the JSON includes a Start, it must also include an End.
The JSON can be incomplete but must be a valid JSON object with at least one key-value pair.
You only ever respond with valid JSONs. You do not say anything else.
""";

// Example messages to include in the chat completion request
final exampleMessages = [
  OpenAIChatCompletionChoiceMessageModel(
    role: OpenAIChatMessageRole.user,
    content: [
      OpenAIChatCompletionChoiceMessageContentItemModel.text(
        "Tomorrow evening I have a meeting with John at 5pm at the office",
      ),
    ],
  ),
  OpenAIChatCompletionChoiceMessageModel(
    role: OpenAIChatMessageRole.assistant,
    content: [
      OpenAIChatCompletionChoiceMessageContentItemModel.text(
        """
        {
          "Summary": "Meeting with John",
          "Start": "2025-05-22T17:00:00",
          "End": "2025-05-22T18:00:00",
          "Location": "Office"
        }
        """,
      ),
    ],
  ),
  // Additional examples...
];
```

The examples should use datetime values relative to the current date, and the actual implementation should update these dates dynamically.
The AI must be provided the current datetime at the time of the user's message.

## Potential Challenges and Solutions

1. **dart_openai SDK Integration**
   - **Challenge**: Ensuring proper configuration and error handling with the SDK.
   - **Solution**: Follow the SDK documentation carefully and implement proper exception handling.

2. **Date/Time Interpretation**
   - **Challenge**: Converting relative time references ("tomorrow", "next week") to actual dates.
   - **Solution**: Let OpenAI handle this conversion, but verify results for reasonableness.

3. **Calendar Integration Across Platforms**
   - **Challenge**: Different platforms handle calendar files differently.
   - **Solution**: Use platform-specific code to open .ics files.

4. **API Key Security**
   - **Challenge**: Securely storing OpenAI API keys.
   - **Solution**: Use flutter_secure_storage package and avoid storing keys in plain text.

5. **API Rate Limits and Costs**
   - **Challenge**: Managing OpenAI API usage within rate limits and budget constraints.
   - **Solution**: Implement caching for similar requests, add rate limiting, and monitor API usage.

6. **SDK Version Updates**
   - **Challenge**: Handling changes in the dart_openai SDK API across versions.
   - **Solution**: Lock the SDK version in pubspec.yaml and test thoroughly when updating.

## Testing Strategy

1. **Unit Tests**
   - Test the dart_openai SDK integration with mock responses
   - Test iCalendar file generation
   - Test event data validation

2. **Widget Tests**
   - Test UI form behavior
   - Test loading states
   - Test error displays

3. **Integration Tests**
   - Test end-to-end flow with mock AI responses
   - Test sharing integration on real devices

4. **Manual Testing Focus Areas**
   - Testing a variety of natural language inputs
   - Testing with different calendar apps
   - Testing share functionality from multiple apps

## Dependencies

1. **dart_openai**: For OpenAI API integration
2. **shared_preferences**: For storing settings
3. **flutter_secure_storage**: For secure API key storage
4. **intl**: For date formatting
5. **path_provider**: For file system access
6. **url_launcher**: For opening the .ics file
7. **ical**: For generating iCalendar (.ics) files
8. **provider** or **flutter_bloc**: For state management

## Conclusion

EventSnap in Flutter should leverage Flutter's cross-platform capabilities (although it should focus on Android with the Share API) and the dart_openai SDK for efficient API integration. The architecture emphasizes modularity to allow for future extensions, such as supporting additional AI providers or calendar formats.

Using the dart_openai SDK provides several advantages over direct HTTP implementation:
- Typed API for better development experience and fewer runtime errors
- Built-in error handling and retries
- Proper request structure and response parsing
- Easier configuration and management of API parameters
- Automatic handling of authentication headers

The key to success is proper implementation of the OpenAI prompt engineering and ensuring robust error handling throughout the app, particularly for API operations and response parsing.