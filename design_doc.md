# EventSnap Design Document (v3.0.0)

## Overview

EventSnap is a mobile app that creates calendar events from natural language text and from photos or screenshots. The user supplies text, images, or both, either typed in the app or shared from another app. An AI model extracts zero or more events, each field comes with evidence from the source, the user reviews and edits the events, and the app exports them as RFC 5545 iCalendar (.ics) files.

Version 3 adds Opper as a second provider, structured output with graceful fallbacks, image input, per-field evidence in the review UI, and a custom iCalendar writer. It also replaces the `dart_openai` SDK and the `ical` package.

The detailed implementation plan and the binding interface contracts live in [`docs/v3_plan.md`](docs/v3_plan.md). This document describes the resulting architecture and the reasons behind it.

## Goals

- Support multiple AI providers (OpenAI and Opper) through one OpenAI-compatible client.
- Use structured output when the selected model supports it, and degrade gracefully when it does not.
- Accept images as well as text, from the share sheet and from in-app pickers.
- Show, for every extracted field, where it came from and how confident the model is.
- Keep dependencies current and remove abandoned packages.

## Architecture

The app is organised in layers. Models have no UI dependencies. Services talk to the network, the platform and the file system. Providers hold application state. Screens and widgets render state and call services through `provider`.

```
screens / widgets  ──►  providers (AppStateProvider)  ──►  services
                                                             ├── ai/         (provider clients, prompts, parsing, model catalog)
models/  ◄── used by all layers                              ├── calendar/   (iCalendar writer, Android hand-off)
                                                             └── platform/   (shared content, image input)
```

**Rules**

- Models must not import `material_ui` or Flutter UI libraries.
- Screens obtain services with `context.read<…>()`. They never construct services directly. This keeps the UI testable with fakes.
- Services are defined as abstract interfaces with concrete implementations, so tests can substitute fakes.

### Layers

| Layer | Responsibility |
|-------|----------------|
| `models/` | `AiProvider`, `AiModelInfo`, `Settings`, `EventModel`, `FieldEvidence`, `ExtractionInput`/`ExtractionResult`, `SharedContent` |
| `services/ai/` | Provider HTTP client, provider configuration, prompt and JSON schema, lenient parser, model catalog, error mapping |
| `services/calendar/` | `CalendarCreator`, the pure `ICalSerializer`, and the Android method-channel wrapper |
| `services/platform/` | `SharedContentSource` (Android share intents) and `ImageInputService` (gallery and camera) |
| `services/settings_service.dart` | Persistence of `Settings` (secure storage for keys, shared preferences for the rest) |
| `providers/` | `AppStateProvider`: settings, initialisation, theme mode |
| `navigation/` | `AppRouter`: named routes; `openReview` returns a `ReviewOutcome` |
| `screens/` | `HomeScreen` (composer), `ReviewScreen`, `SettingsScreen` |
| `widgets/` | Home, review, settings and event-form widgets |
| `ui/`, `themes/` | Shared UI helpers, error presentation, Material 3 theme |

## Data Models

- **`AiProvider`** (enum: `openai`, `opper`): storage id, display name, default model, API key help URL and hint. Unknown ids map to `openai`.
- **`Settings`** (immutable): the selected provider; one API key and one model per provider; retries, timeout, theme mode, auto-process flag, structured output mode (`auto`/`off`) and debug mode. Its `toString()` never includes keys.
- **`AiModelInfo`**: model id, display name, provider, nullable capability flags (`supportsStructuredOutput`, `supportsVision`; `null` means unknown), vendor, speed, quality, context window and a `recommended` flag.
- **`EventModel`**: title, optional description and location, local `startDateTime` and `endDateTime`, `isAllDay`, a stable local `id`, and an `evidence` map keyed by `EventField`. For all-day events the start and end are midnights, and the end is exclusive.
- **`FieldEvidence`**: verbatim `quote` (or `null` when the value was inferred), one-sentence `reasoning`, and `confidence` (`high`, `medium`, `low`).
- **`ExtractionInput`** (text and images) and **`ExtractionResult`** (events, the original input for the source panel, provider, model, whether structured output was used, warnings, and the raw response for debug mode).

## AI Pipeline

### Provider client

Both providers speak the OpenAI Chat Completions wire format, so one thin `http`-based client serves both. `ProviderConfig` supplies the base URL, the models endpoint, the capability strategy and request quirks. The client is injectable, which allows `MockClient`-based tests. The `dart_openai` SDK was removed because it uses a global static key and has no support for JSON schema or model capabilities.

- **Auth:** bearer token from the active provider's key.
- **Timeout and cancellation:** the request is bounded by the configured timeout. Cancelling closes the request and yields `AiException(cancelled)`.
- **Retries:** exponential backoff with jitter, only for network errors, timeouts, HTTP 429 (honouring `Retry-After`) and 5xx responses.
- **Error mapping:** HTTP status codes and error bodies map to `AiErrorKind` values (`auth`, `modelNotFound`, `rateLimited`, `quotaExceeded`, `unsupportedInput`, `timeout`, and others). Every error reaches the UI as an `AiException`.

### Model catalog and capabilities

- **Opper:** the live model list (`GET /v3/models`, no key required) provides `structured_output` and `vision` capabilities. The list holds roughly 1,280 LLMs, so the picker is searchable.
- **OpenAI:** `GET /v1/models` returns only IDs. Capabilities come from id heuristics, for example `gpt-4.1*`, `gpt-5*` and `o3*` support structured output. Unknown ids are assumed to support it, and the runtime fallback covers mistakes.
- Results are cached in memory and persisted for 24 hours.

### Structured output and the downgrade ladder

One unified schema is used for both providers. It contains no `$ref`s, and every object sets `additionalProperties: false` with all keys required:

```
{ events: [ { title, description|null, location|null, start, end, all_day,
              evidence: { title|description|location|start|end: { quote|null, reasoning, confidence } } } ] }
```

The request tries the most capable mode first and falls back when the provider rejects it:

1. `json_schema` (strict), when the mode is `auto` and the model supports it or its support is unknown.
2. On a 400 that mentions `response_format` or the schema, `json_object` with the schema described in the prompt.
3. On a 400 for that too, no `response_format` and prompt-only instructions.

The downgrade is remembered per model for the session. The parser is lenient: it strips code fences, extracts the outermost JSON object, accepts a bare array or a single event, and accepts the v2 capitalised keys (`Summary`, `Start`, …). Normalisation converts each event to `EventModel` in local time. A single unrecoverable event is skipped with a warning, and the rest of the result is kept.

### Prompt

The prompt includes the current date, weekday, time and time zone offset. It sets the extraction rules: a default duration of one hour, all-day handling for events without a time, and a 09:00 default with `low` confidence when only a date is given. It also sets the evidence rules: quotes must be verbatim and at most 15 words, `null` when a value is inferred, and reasoning in one English sentence. The number of events is not fixed, so one request can return several events. Empty results are allowed.

### Images

- Images are downscaled on device to at most 2048 px on the long edge and sent as base64 data URLs in `image_url` content parts.
- Gallery and camera images are downscaled by `image_picker`. Shared images are downscaled natively on Android, with EXIF orientation applied and JPEG output.
- If the selected model is known to lack vision, the request is refused early with `AiException(unsupportedInput)`.
- The total payload is capped, and the user gets a clear message when it is exceeded.

## Review and Evidence

The review screen shows the source text, with the active field's quote highlighted, and image thumbnails. Each event is a card containing an editable form. Each field has an evidence line with its quote and reasoning. Low-confidence fields carry a "Check" badge. After a user edits a field, the evidence line is replaced by "Edited by you". Debug mode adds an expandable raw response.

Events can be edited, marked as all-day, and deleted with undo. Changing the start time keeps the duration. "Add to calendar" validates every event, creates the `.ics` file and opens it with a calendar app. If no app can handle the file, the user sees an actionable message.

## Calendar Export

- **Serializer:** `ICalSerializer` is a pure function that writes RFC 5545 text. It emits `VCALENDAR` with `VERSION:2.0`, `PRODID`, `CALSCALE:GREGORIAN` and `METHOD:PUBLISH`, and one `VEVENT` per event. Timed events use UTC (`…Z`) values. All-day events use `VALUE=DATE` with an exclusive end. Text is escaped, lines use CRLF, and long lines are folded at 75 octets in a UTF-8-safe way. The UID is `<event.id>@eventsnap.app`.
- **Creator:** `CalendarCreator` writes the file to the temporary directory and hands it to Android through a `FileProvider` chooser. It returns `false` when no handler exists.
- The `ical` package was removed because it pins an old `intl` version and predates Dart 3.

## Settings and Persistence

- API keys are stored per provider with `flutter_secure_storage`. The app uses `flutter_secure_storage` 11, which dropped the older EncryptedSharedPreferences backend, so keys saved by v2 can't be migrated. On first load `checkUpgradeStatus()` runs before any secure read; if it reports lost data, the home screen shows a one-time banner asking the user to re-enter the API key (other settings are kept).
- Other settings are stored in `shared_preferences`, using a `settings_version` key for migration from v1.
- `fromJson` is lenient, so bad values fall back to defaults. `updateSettings` persists only settings whose numeric ranges are valid. Blank keys and models are allowed, so the theme can be changed before setup is complete.

## Application Flow

1. **Launch:** the app opens to the home composer. If the app is not configured, a setup card links to Settings. If the app was launched through a share, the shared content fills the composer. If auto-processing is on and the app is configured, extraction starts automatically.
2. **Input:** the user types or pastes text, attaches images, or both.
3. **Processing:** inputs are disabled, the stage text is shown, and a Cancel action is available.
4. **Result:** zero events produce an inline message. One or more events open the review screen.
5. **Export:** the user adds the events to a calendar. On success the composer is cleared and a snackbar confirms.
6. **Errors:** each `AiErrorKind` maps to a message and an action: open Settings, choose a model, choose a vision model, or retry.

## Android Platform

- **Manifest:** text `SEND`, `SEND_MULTIPLE`/`SEND` for `image/*`, and the `text/calendar` `VIEW` filter.
- **`MainActivity`:** reads the text, subject, and up to 4 images from the intent. It copies and downscales images into the app cache, deletes cached images older than 24 hours on startup, and runs the heavy work off the main thread. It delivers the initial content once through `getInitialSharedContent`, and later content through `onSharedContent` when `onNewIntent` fires.
- **Camera:** uses the system camera intent, so the app does not need the `CAMERA` permission.
- **Web:** platform channels are unavailable. Services degrade gracefully, for example a no-op share source.

## Error Handling

- Every failure reaches the presentation layer as `AiException`, with a technical `message` for logs and a provider-agnostic `userMessage`.
- The UI maps error kinds to actions in one place, `lib/ui/error_presentation.dart`, so the home and settings screens share the same behaviour.

## Testing Strategy

- **Unit tests:** models, `Settings` migration and validation, `EventModel` (all-day normalisation, validation), `ICalSerializer` (escaping, folding, CRLF, UTC and date values), parser edge cases, the downgrade ladder, error mapping, and retry and backoff with fake delays.
- **HTTP tests:** `MockClient` checks request shape, including schema present or absent, image parts, authorization headers, base URLs and reasoning parameters. Catalog mapping uses trimmed JSON fixtures.
- **Widget tests:** composer enable and disable, image chips, share-triggered processing with a fake source, error actions, cancel, evidence rendering, low-confidence badges, delete with undo, all-day toggling, and export success and failure.
- **Live tests:** smoke tests against the real APIs run only when `OPENAI_API_KEY` and/or `OPPER_API_KEY` is set in the environment.
- **Shared fakes:** `test/helpers/fakes.dart` provides fake settings service, interpreter, model catalog, factory, share source, image input and calendar creator. `test/helpers/test_app.dart` wires them the same way `main.dart` does.

## Dependencies

| Package | Purpose |
|---------|---------|
| `material_ui` | Material 3 widgets (replaces `package:flutter/material.dart`) |
| `http` | OpenAI-compatible API client |
| `provider` | State management |
| `flutter_secure_storage` (11.x) | API key storage |
| `shared_preferences` | Other settings and model cache |
| `image_picker` | Gallery and camera input |
| `dynamic_color` | Dynamic Material colour |
| `intl` | Locale-aware dates |
| `url_launcher` | External links |
| `path_provider` | Temporary directory for `.ics` files |
| `package_info_plus` | App version in About |
| `flutter_lints`, `mocktail`, `flutter_dotenv` | Dev: lints, mocks, live-test configuration |

Removed in v3: `dart_openai` (replaced by the `http` client) and `ical` (replaced by `ICalSerializer`).

Build toolchain: Flutter 3.50 with Dart 3.14, Android Gradle Plugin 9.3, Kotlin 2.4, Gradle 9.5 and Java 17.

## Open Items

- Live provider behaviour can vary across the upstream vendors behind Opper. Schema-validation failures surface as `invalidResponse`, and the downgrade ladder and lenient parser handle them.

## Reference

- [`docs/v3_plan.md`](docs/v3_plan.md): goals, research notes, contracts (section 4), phases, workstream specs (section 6) and risks (section 7).
