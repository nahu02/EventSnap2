# EventSnap2

A Flutter mobile application that converts natural language text into calendar events using OpenAI's GPT models. EventSnap2 intelligently extracts event details from plain text descriptions and generates standard iCalendar (.ics) files that integrate seamlessly with calendar applications.

The current implementation targets Android only, but it may work on other platformsa as well.

## Description

EventSnap2 leverages AI-powered natural language processing to transform conversational event descriptions into structured calendar entries. The app features Android sharing integration, allowing users to share text from any application directly to EventSnap2 for instant event creation. Built with Flutter for cross-platform compatibility, it uses secure storage for API keys and implements robust error handling with retry logic.

## Interesting Techniques

The codebase demonstrates several advanced Flutter development patterns:

- **Provider State Management**: Uses the [Provider pattern](https://pub.dev/packages/provider) with `ChangeNotifier` for centralized app state management, implementing reactive UI updates across screens
- **Method Channel Integration**: Implements bidirectional communication between Flutter and native Android code using [MethodChannel](https://docs.flutter.dev/platform-integration/platform-channels) for calendar file sharing
- **Secure Storage**: Leverages [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) for encrypting sensitive data like API keys at rest
- **JSON Schema Validation**: Implements structured JSON parsing with error handling for AI responses using Dart's built-in `jsonDecode`
- **RFC 5545 Compliance**: Generates standards-compliant iCalendar files using the [ical package](https://pub.dev/packages/ical) with proper timezone handling
- **Prompt Engineering**: Sophisticated AI prompt design with dynamic date context injection and few-shot learning examples
- **Exponential Backoff**: Implements retry logic with exponential backoff for API resilience

## Technologies and Libraries

- **[dart_openai](https://pub.dev/packages/dart_openai)**: Official OpenAI SDK for Dart providing structured API access
- **[ical](https://pub.dev/packages/ical)**: RFC 5545 iCalendar format generation and serialization
- **[flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)**: AES encryption for sensitive data storage
- **[shared_preferences](https://pub.dev/packages/shared_preferences)**: Persistent key-value storage for app settings
- **[path_provider](https://pub.dev/packages/path_provider)**: Cross-platform file system path access
- **[url_launcher](https://pub.dev/packages/url_launcher)**: Platform-specific URL and file launching
- **[provider](https://pub.dev/packages/provider)**: Dependency injection and state management
- **[intl](https://pub.dev/packages/intl)**: Internationalization and date formatting
- **[mocktail](https://pub.dev/packages/mocktail)**: Mock generation for unit testing

## Project Structure

```
/
├── android/                     # Android-specific platform code
│   └── app/src/main/kotlin/     # Kotlin implementation for method channels
├── assets/                      # Static assets and app icons
├── lib/                         # Flutter application code
│   ├── models/                  # Data models and JSON serialization
│   ├── navigation/              # App routing and navigation logic
│   ├── providers/               # State management providers
│   ├── screens/                 # UI screens and user interfaces
│   ├── services/                # Business logic and external API integration
│   ├── themes/                  # App theming and design system
│   └── widgets/                 # Reusable UI components
├── test/                        # Unit and integration tests
└── web/                         # Progressive Web App support
```

**Interesting Directories:**

- **[`lib/services/`](lib/services/)**: Contains the AI interpretation layer with [OpenAI integration](lib/services/openai_calendar_event_interpreter.dart) and [iCalendar file generation](lib/services/icalendar_creator.dart)
- **[`android/app/src/main/kotlin/`](android/app/src/main/kotlin/)**: Kotlin implementation for native Android file sharing and calendar integration
- **[`lib/models/`](lib/models/)**: Data transfer objects with bidirectional JSON serialization for AI communication
