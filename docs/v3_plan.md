# EventSnap2 v3.0 — Implementation Plan

> This is the master plan and **shared spec** for the v3 rewrite. Every agent working on v3 must read this file
> first. Section 4 ("Contracts") is binding: do not change a contract signature without it being changed here first.

## 1. Goals

| # | Requirement | Summary of approach |
|---|-------------|---------------------|
| G1 | Multiple AI providers, specifically **Opper** | Provider abstraction over an OpenAI-compatible Chat Completions HTTP client. OpenAI (`https://api.openai.com/v1`) and Opper (`https://api.opper.ai/v3/compat`) both speak that wire format. Per-provider API keys and model selection. |
| G2 | Use **structured output** when the model supports it | Capability detection per model (Opper: live `capabilities` list; OpenAI: id heuristics), `response_format: json_schema` (strict) when supported, graceful downgrade ladder otherwise. |
| G3 | Share menu also appears for **photos/images** | Android intent filters for `image/*` (`SEND`, `SEND_MULTIPLE`), downscaled images passed to Flutter, sent to vision-capable models. In-app gallery/camera picking too. |
| G4 | Review screen shows **context/justification** per field | Schema asks the model for per-field evidence: verbatim quote from the source + short reasoning + confidence. Shown under each field; quotes highlighted in the original text. |
| G5 | **Dependencies up to date** | Flutter 3.50.1 / Dart 3.14, all packages at latest, `material.dart` → `material_ui`, drop the abandoned `ical` package (custom RFC 5545 writer), drop `dart_openai` (thin `http` client), AGP/Kotlin/Gradle per current Flutter template. |
| G6 | UX evaluation & optimisation | See section 3 (audit) and section 6 (workstream F/D/E specs). |

Version: bump `pubspec.yaml` to **3.0.0** (CI requires a bump; this is a major release).

## 2. Research notes (verified 2026-11-21)

### Opper
- OpenAI-compatible endpoint: `POST https://api.opper.ai/v3/compat/chat/completions`, header `Authorization: Bearer <OPPER_API_KEY>` (`x-api-key` is **not** accepted on OpenAI-shaped routes).
- Structured output: standard `response_format: {"type":"json_schema","json_schema":{"name":..., "schema":{...}}}`. Content comes back as a JSON string. The gateway validates output against the schema and fails with a validation error instead of returning malformed JSON. (`strict` is not documented by Opper; sending it is harmless for OpenAI-routed models — verify with a MockClient-based test and be tolerant.)
- Images: standard content parts `{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,..."}}` to models with the `vision` capability.
- Models: `GET https://api.opper.ai/v3/models` — **no key required**. Paginated (`limit`, `offset`, `has_more`, `next_offset`; `limit<=0` returns all). Useful filters: `type=llm`, `capability=structured_output` (repeatable, AND), `capability=vision`, `featured=true` (short curated list), `q=` substring search, `sort`, `order`. Each item has `id` (e.g. `openai/gpt-5-mini`, `anthropic/claude-sonnet-5-5`, `gemini/gemini-3.8-flash`), `name`, `capabilities` (`text`, `tools`, `vision`, `structured_output`, `reasoning`, `thinking`, `pdf`, …), `speed` (`very_fast|fast|medium|slow`), `quality` (`good|great|high|best`), `cost`, `context_window`, `provider.display_name`, `maker.display_name`, `params.temperature`, `params.reasoning.supported` (e.g. `["none","minimal","low",…]`, wire name `reasoning_effort`). ~1,280 LLMs → the model picker **must** be searchable.
- Legacy `/v3/call` and the `opperai` SDK are being sunset — do not use them.
- OpenAPI spec: `https://api.opper.ai/v3/openapi.json`.
- Recommended default model: `openai/gpt-5-mini` (structured output + vision, fast; used in Opper's own docs).

### OpenAI
- `GET /v1/models` lists ids only (no capabilities) → heuristics needed.
- Structured output (`json_schema`, `strict: true`) supported by: `gpt-4o` (except `gpt-4o-2024-05-13`), `gpt-4o-mini`, `gpt-4.1*`, `gpt-4.5*`, `gpt-5*`, `gpt-6*`, `o1` (not `o1-mini`/`o1-preview`), `o3*`, `o4*`. Not supported: `gpt-3.5*`, `gpt-4`, `gpt-4-turbo*`, `*-instruct`. Unknown/new ids → assume supported (runtime downgrade covers mistakes).
- Vision: `gpt-4o*`, `gpt-4-turbo*`, `gpt-4.1*`, `gpt-4.5*`, `gpt-5*` (not `*-search*`/`*-codex*`/`*audio*`), `gpt-6*`, `o1` (not mini/preview), `o3` (not `o3-mini`), `o4-mini`.
- Reasoning models (`o*`, `gpt-5*`, `gpt-6*`) reject non-default `temperature` and use `max_completion_tokens` instead of `max_tokens`; they accept `reasoning_effort` (`minimal|low|medium|high`). For a snappy UX send `reasoning_effort: "low"` to reasoning models and omit `temperature`/`max_tokens` for them.
- Strict mode rules: every object needs `additionalProperties: false` and all properties listed in `required`; optional values are expressed as nullable (`"type": ["string","null"]`). Avoid `$ref`/`$defs` (inline instead) for maximum cross-provider compatibility through Opper.
- Recommended default model: `gpt-5-mini`.

### Toolchain
- Flutter **3.50.1** stable, Dart **3.14.0** (installed at `/root/sdk/flutter`; add `/root/sdk/flutter/bin` to `PATH`). Android SDK at `/root/sdk/android` (platform 36, build-tools 36) — `flutter build apk --debug` works once the signing fallback (below) is in place.
- `package:flutter/material.dart` is deprecated since Flutter 3.47 → use `package:material_ui/material_ui.dart` (`dart fix --apply --code=migrate_design_widgets`). Third-party packages still on `flutter/material` may need `MaterialUiCompatibilityBridge`.
- Latest packages: `material_ui 1.11.1`, `http 1.6.0`, `image_picker 1.2.4`, `flutter_secure_storage 11.2.0` (v11 with upgrade detection — see 6.A.2), `intl 0.20.3`, `shared_preferences 2.5.6`, `provider 6.1.5+1`, `url_launcher 6.3.3`, `path_provider 2.1.6`, `dynamic_color 2.1.0`, `flutter_lints 6.0.0`, `mocktail 1.0.5`, `flutter_dotenv 6.0.2`, `flutter_launcher_icons 0.14.4`.
- `ical 0.2.2` (2021, pre-Dart-3 SDK constraint) pins `intl 0.17` → remove it and write a small RFC 5545 serializer.
- `dart_openai` is a third-party SDK with a global static API key and no first-class `json_schema`/capabilities support → replace with a thin `http`-based client (also enables `MockClient` tests).

## 3. UX audit of v2.1.1 (findings → fixes)

| # | Finding (v2.1.1) | Fix in v3 | Owner |
|---|------------------|-----------|-------|
| U1 | Home screen is a welcome card + duplicate "Settings" tile; the primary action needs an extra tap. | Home **is** the composer: text field, attach image, paste, one primary "Find events" button. | F |
| U2 | User must tick "The text contains multiple events" — easy to get wrong; two prompts with hacks ("ALWAYS ASSUME MULTIPLE EVENTS"). | One unified schema: `events[]` with 1..n items; model decides. Checkbox removed. | B, F |
| U3 | `resizeToAvoidBottomInset: false` on the input screen hides the button behind the keyboard. | Primary action pinned above the keyboard / in a bottom bar that respects insets. | F |
| U4 | No progress feedback or cancel during the (sometimes 10 s+) AI call. | Progress state with stage text and a Cancel button (cancellation token). | F, B |
| U5 | Error messages from string matching (`contains('API key')`), generic fallback, no next step. | Typed `AiException.kind` → friendly message + action (Open settings / Retry / Choose a vision model). | B, F |
| U6 | Shared text opens the input screen, but the user still has to tap "Create Event". Sharing while the app is already running is ignored (`onNewIntent` never reaches Flutter). | Shared content arrives via a stream (initial + live). Auto-process shared content when configured (setting, default on). | C, F |
| U7 | Multi-event review uses collapsed `ExpansionTile`s; can't remove a wrongly extracted event. | Expanded cards (collapsible), delete with Undo, per-card summary header. | D |
| U8 | No explanation of why fields were filled as they were. | Per-field evidence (quote + reasoning + confidence), low-confidence "Check" badge, source panel with highlighted quotes. | D, B |
| U9 | No all-day events; date-only text becomes 09:00–10:00. | `isAllDay` end-to-end (schema, model, form toggle, iCal `VALUE=DATE`). | B, D, foundation |
| U10 | Changing start time does not move the end time (duration lost). | Changing start shifts end by the same delta (calendar-app convention). | D |
| U11 | Hard-coded formats (`HH:mm`, `MMM dd; HH:mm`) ignore locale / 24 h preference. | Locale-aware `intl` formats + `MediaQuery.alwaysUse24HourFormat`. | D |
| U12 | AI output that fails `toEventModel()` (missing end, end<start) aborts the whole flow. | Lenient normalisation in the parser (missing end → +1 h, missing title → "Untitled event") with a low-confidence evidence note. | B |
| U13 | Review screen shows hard-coded "Sample Event" placeholders when opened without data; error text bug `'\$e'` prints a literal `$e`. | Removed / fixed. | D |
| U14 | Settings: unsearchable dropdown filtered to ids containing "gpt"; "debug mode" secretly forces dark theme; footer text hard-codes "OpenAI". | Provider switch, searchable model picker with capability badges, explicit theme setting, provider-aware copy. | E, F |
| U15 | M2-era styling (primary-coloured app bar, hard-coded `Colors.green/orange/red`), no dynamic colour. | M3 surfaces, colour-scheme roles only, `dynamic_color` (Material You) with seed fallback. | F |
| U16 | After handing off to the calendar the user is left on the form. | Success → return to Home with the composer cleared (`ReviewOutcome.exported`). | D, F |
| U17 | Accessibility: icon-only buttons without tooltips in places, fixed-height cards that overflow at large text scale. | Tooltips/semantics on all icon buttons, no fixed heights around text, verify at 2.0 text scale. | all UI |

## 4. Contracts (binding)

All paths relative to `lib/`. Models must not import `material_ui`/Flutter UI libraries.

### 4.1 Models

```dart
// models/ai_provider.dart
enum AiProvider {
  openai, opper;
  String get id;            // storage value: 'openai' | 'opper'
  String get displayName;   // 'OpenAI' | 'Opper'
  String get defaultModel;  // 'gpt-5-mini' | 'openai/gpt-5-mini'
  Uri get apiKeyHelpUrl;    // where to create a key (OpenAI: https://platform.openai.com/api-keys; Opper: verify — platform.opper.ai)
  String get apiKeyHint;    // placeholder text for the key field
  static AiProvider fromId(String? id); // unknown/null → openai
}

// models/ai_model_info.dart
class AiModelInfo {
  final String id;                       // exact id for API requests
  final String displayName;              // fallback: id
  final AiProvider provider;
  final bool? supportsStructuredOutput;  // null = unknown
  final bool? supportsVision;            // null = unknown
  final String? description;
  final String? vendor;                  // e.g. 'OpenAI', 'Anthropic'
  final String? speed;                   // Opper: very_fast|fast|medium|slow
  final String? quality;                 // Opper: good|great|high|best
  final int? contextWindow;
  final bool recommended;                // curated / featured
  // const ctor, fromJson/toJson (for caching), ==, hashCode
}

// models/settings.dart  (immutable, v2)
enum AppThemeMode { system, light, dark }
enum StructuredOutputMode { auto, off }
class Settings {
  final AiProvider provider;             // default: openai
  final String openAiApiKey;             // default ''
  final String opperApiKey;              // default ''
  final String openAiModel;              // default AiProvider.openai.defaultModel
  final String opperModel;               // default AiProvider.opper.defaultModel
  final int maxRetries;                  // 0..10, default 2
  final int timeoutSeconds;              // 5..300, default 60
  final AppThemeMode themeMode;          // default system
  final bool autoProcessShared;          // default true
  final StructuredOutputMode structuredOutputMode; // default auto
  final bool debugMode;                  // default false; shows raw AI response on review screen
  const Settings({...all named, with defaults...});
  factory Settings.defaults();
  String apiKeyFor(AiProvider p); String modelFor(AiProvider p);
  String get activeApiKey; String get activeModel;
  bool get isConfigured;                 // active key + active model non-blank
  List<String> validate();               // errors (active provider only + ranges)
  List<String> warnings();               // non-blocking, e.g. OpenAI key not starting with 'sk-'
  Duration get timeoutDuration;
  String maskedKeyFor(AiProvider p);
  Settings copyWith({...});
  Map<String, dynamic> toJson(); factory Settings.fromJson(Map<String, dynamic>);
  // ==, hashCode; toString() must NEVER include API keys
}

// models/field_evidence.dart
enum EventField { title, description, location, start, end }
enum EvidenceConfidence { high, medium, low }
class FieldEvidence {
  final String? quote;                  // verbatim excerpt from the source text (or text read from an image); null if inferred/defaulted
  final String reasoning;               // one short sentence: how the value was derived
  final EvidenceConfidence confidence;
  // const ctor, fromJson/toJson (snake_case keys: quote, reasoning, confidence), ==, hashCode
}

// models/event_model.dart  (extend the existing class; keep existing API working)
class EventModel {
  final String id;                      // stable local id (generated when absent); NOT part of ==/hashCode
  String title; String? description; String? location;
  DateTime startDateTime;               // LOCAL time (isUtc == false)
  DateTime endDateTime;                 // LOCAL time; for all-day events: exclusive (day after last day, 00:00)
  bool isAllDay;                        // default false
  Map<EventField, FieldEvidence> evidence; // default const {}
  // keep: validate(), isValid, duration, formatted*, copyWith(+isAllDay, +evidence), toJson/fromJson(+isAllDay, +evidence)
  // all-day events: start and end are midnights; constructor/validate enforce end > start
}

// models/extraction.dart
class InputImage { final String path; final String mimeType; }   // local file, already downscaled (≤ ~2048 px long edge)
class ExtractionInput {
  final String text; final List<InputImage> images;
  bool get hasText; bool get hasImages; bool get isEmpty;
}
class ExtractionResult {
  final List<EventModel> events;        // may be empty
  final ExtractionInput input;          // original input, for the source/context panel
  final AiProvider provider; final String model;
  final bool usedStructuredOutput;
  final List<String> warnings;          // user-presentable notes (e.g. "Model lacks structured output; used JSON mode")
  final String? rawResponse;            // raw model content, shown only in debug mode
}

// models/shared_content.dart
class SharedContent { final String? text; final List<InputImage> images; bool get isEmpty; }
```

`models/calendar_event_properties.dart` is **removed** (the AI DTO is internal to the AI layer now; the calendar layer takes `EventModel`).

### 4.2 Services

```dart
// services/ai/ai_exceptions.dart
enum AiErrorKind { notConfigured, auth, rateLimited, quotaExceeded, network, timeout, modelNotFound,
                   unsupportedInput, invalidResponse, server, cancelled, unknown }
class AiException implements Exception {
  final AiErrorKind kind; final String message;  // message = technical detail (for logs/debug)
  final int? statusCode; final Object? cause;
  const AiException(this.kind, this.message, {this.statusCode, this.cause});
  String get userMessage;                         // friendly, provider-agnostic sentence per kind
}

// services/ai/ai_cancellation_token.dart
class AiCancellationToken { bool get isCancelled; void cancel(); Future<void> get whenCancelled; }

// services/ai/calendar_event_interpreter.dart
abstract class CalendarEventInterpreter {
  /// Throws [AiException]. Never throws other exception types.
  Future<ExtractionResult> extractEvents(ExtractionInput input, {AiCancellationToken? cancellationToken});
}

// services/ai/model_catalog.dart
abstract class ModelCatalog {
  Future<List<AiModelInfo>> listModels(AiProvider provider, {required String apiKey, bool forceRefresh = false});
  Future<AiModelInfo?> findModel(AiProvider provider, String modelId, {required String apiKey});
  Future<void> verifyApiKey(AiProvider provider, String apiKey);   // throws AiException(kind: auth|network|…)
}

// services/ai/ai_service_factory.dart
abstract class AiServiceFactory {
  CalendarEventInterpreter createInterpreter(Settings settings);
  ModelCatalog get modelCatalog;
}

// services/platform/shared_content_source.dart
abstract class SharedContentSource {
  Future<SharedContent?> takeInitialSharedContent();  // content that launched the app (consumed once)
  Stream<SharedContent> get sharedContentStream;      // content shared while the app is running
  void dispose();
}

// services/platform/image_input_service.dart
abstract class ImageInputService {
  bool get isCameraSupported;
  Future<InputImage?> pickFromGallery();
  Future<InputImage?> captureWithCamera();
}

// services/calendar/calendar_creator.dart
abstract class CalendarCreator {
  String buildIcs(List<EventModel> events);                    // pure, RFC 5545
  Future<String> createIcsFile(List<EventModel> events);       // writes to temp dir, returns path
  Future<bool> openInCalendarApp(String filePath);             // Android FileProvider + chooser; false if no handler
}
```

Existing `services/settings_service.dart` keeps its interface (`getSettings`, `updateSettings`, `clearSettings`, …) but persists Settings v2 (see 6.A).

### 4.3 App wiring

```dart
// providers/app_state_provider.dart
class AppStateProvider extends ChangeNotifier {
  AppStateProvider({required SettingsService settingsService});
  Settings get settings; bool get isInitialized; bool get isConfigured; String? get errorMessage;
  ThemeMode get themeMode;            // mapped from settings.themeMode
  Future<void> initialize(); Future<void> updateSettings(Settings s); void clearError();
}

// navigation/app_router.dart
enum ReviewOutcome { exported, discarded }
class AppRouter {
  static const home = '/', review = '/review', settings = '/settings';
  static Route<dynamic>? generateRoute(RouteSettings s);
  static Future<ReviewOutcome?> openReview(BuildContext c, ExtractionResult result);
  static Future<void> openSettings(BuildContext c);
}

// screens: HomeScreen()  ·  ReviewScreen({required ExtractionResult result})  ·  SettingsScreen()
```

`main.dart` registers via `provider`: `SettingsService`, `AiServiceFactory`, `SharedContentSource`, `ImageInputService`, `CalendarCreator`, `AppStateProvider`. Screens obtain services with `context.read<…>()` — never `new` them directly (testability).

### 4.4 Foundation notes (as implemented in Phase 1 — binding)

Compatible additions/clarifications to 4.1–4.3. Signatures above are unchanged.

- **AiProvider**: enhanced enum; `id`/`displayName`/`defaultModel`/`apiKeyHint` are final fields, `apiKeyHelpUrl` a getter (Opper: `https://platform.opper.ai`).
- **Settings**: `const Settings({...})` has literal defaults equal to `AiProvider.<p>.defaultModel` (asserted in tests). Additions: `List<String> validateRanges()` (numeric checks only), `Settings copyWithApiKey(AiProvider p, String key)`, `Settings copyWithModel(AiProvider p, String model)`, `static AppThemeMode themeModeFromName(String?)`, `static StructuredOutputMode structuredOutputModeFromName(String?)`, constants `minRetries`, `maxRetriesLimit`, `minTimeoutSeconds`, `maxTimeoutSeconds`, `defaultMaxRetries`, `defaultTimeoutSeconds`. `fromJson` is lenient (bad types → defaults). Missing key/model → `validate()` error; OpenAI key without `sk-` → `warnings()` only.
- **SettingsService.updateSettings** persists any settings whose `validateRanges()` is empty (blank keys/models are allowed, e.g. changing the theme before setup); throws `ArgumentError` otherwise. `SecureSettingsService` exposes its storage keys as `static const` (`openAiApiKeyKey`, `providerKey`, …) and takes optional `secureStorage` / `preferences` for tests.
- **FieldEvidence**: `const FieldEvidence({String? quote, required String reasoning, required EvidenceConfidence confidence})`; `fromJson` is lenient (blank quote → null, unknown confidence → `low`).
- **EventModel**: `EventModel({String? id, required title, description, location, required startDateTime, required endDateTime, bool isAllDay = false, Map<EventField, FieldEvidence> evidence = const {}})`. The constructor converts UTC inputs to local, throws `ArgumentError` unless `end > start` and title non-blank, and for all-day events **floors start / ceils end to midnight** (10:00–11:00 on May 25 → May 25 00:00 – May 26 00:00). `evidence` is stored unmodifiable (replace the map, don't mutate). Additions: `DateTime get lastDay` (inclusive last day for all-day events), `static String generateId()`. `validate()` also reports non-midnight all-day events. `toJson` writes `id`, `isAllDay`, `evidence` (`{fieldName: FieldEvidence.toJson()}`); `fromJson` accepts the v2 format.
- **InputImage**: `const InputImage({required String path, String mimeType = 'image/jpeg'})` + `fromJson`/`toJson` (`{path, mimeType}` — the share-channel payload shape). `ExtractionInput({text = '', images = const []})`, `ExtractionResult({required events, required input, required provider, required model, usedStructuredOutput = false, warnings = const [], rawResponse})`, `SharedContent({text, images = const []})`: const, value equality.
- **AiException**: + `static String userMessageFor(AiErrorKind kind)`. **AiCancellationToken**: + `void throwIfCancelled()` (throws `AiException(cancelled)`).
- **CalendarCreator**: `ICalendarCreator({DateTime Function()? clock, Future<Directory> Function()? directoryProvider, Future<bool> Function(String)? fileOpener})`; the pure writer is `ICalSerializer.serialize(events, timestamp:)` in `services/calendar/ical_serializer.dart`; UID = `<event.id>@eventsnap.app`. `buildIcs`/`createIcsFile` throw `ArgumentError` for an empty list or invalid events. Android channel wrapper: `services/calendar/android_calendar_service.dart`.
- **AppStateProvider**: `settings` is `Settings.defaults()` until `initialize()` completes; `isInitialized` becomes true even if loading failed (`errorMessage` set). `updateSettings` applies only on success and **rethrows** on failure (also sets `errorMessage`).
- **AppRouter**: `review` requires an `ExtractionResult` argument (otherwise a not-found page). `openReview` completes with `null` when the route is popped without a result (system back) — treat as `discarded`. The Phase 1 `ReviewScreen` pops `exported` after `openInCalendarApp` returns true and `discarded` from its app-bar back button.
- **main.dart**: `const EventSnapApp({settingsService, aiServiceFactory, sharedContentSource, imageInputService, calendarCreator})` — optional overrides (tests); defaults are the Phase 1 adapters below. `DynamicColorBuilder` (dynamic_color 2.1.0 is built on `material_ui`, no bridge needed) feeds `AppTheme.light/dark({ColorScheme? dynamicScheme})`.
- **Temporary adapters (to be replaced)**: `services/ai/legacy/legacy_ai_service_factory.dart` (`LegacyAiServiceFactory`, `LegacyCalendarEventInterpreter`, `LegacyModelCatalog`; OpenAI + text only; uses `services/openai_calendar_event_interpreter.dart` + `dart_openai`) → B. `services/platform/text_only_shared_content_source.dart` (polls the v2 share channel on app resume) and `services/platform/unsupported_image_input_service.dart` → C. `screens/event_text_input_screen.dart` (v2 input screen, pushed from Home with `MaterialPageRoute`) → F deletes it when Home becomes the composer.
- **Test helpers** (reuse them): `test/helpers/fakes.dart` (`InMemorySettingsService`, `FakeCalendarEventInterpreter`, `FakeModelCatalog`, `FakeAiServiceFactory`, `FakeSharedContentSource`, `FakeImageInputService`, `FakeCalendarCreator`, `sampleEvent()`, `sampleResult()`), `test/helpers/test_app.dart` (`TestServices` — registers all fakes like `main.dart`; `services.wrap(screen)` gives a `MaterialApp` with `AppRouter.generateRoute`).
- **material_ui**: import only `package:material_ui/material_ui.dart` (it re-exports `flutter/widgets`); never mix with `package:flutter/material.dart` in one file — the types are distinct copies. Tests import `material_ui` too. Analyzer: `flutter_lints 6` plus private named initializing formals (`AppStateProvider({required this._settingsService})`, Dart 3.14) are in use.

## 5. Phases & agents

```
Phase 1  Foundation (1 agent, sequential)          deps, Android build, iCal writer, all contracts + temp adapters
Phase 2  Feature swarm (5 agents, parallel, worktrees)
         B AI providers & structured output  ·  C Android image sharing & image input
         D Review screen & evidence UI       ·  E Settings & model picker
         F Home/composer, theme, app shell
Phase 3  Integration (orchestrator)              merge B→C→D→E→F, resolve conflicts, analyze/test/build APK
Phase 4  Verification (2 agents, parallel)       correctness code review · visual UX audit (web build + screenshots)
Phase 5  Fix-ups, docs (README, design_doc), version 3.0.0, push
```

### File ownership in Phase 2 (avoid overlapping edits)

| Agent | Owns (may create/modify/delete) | Must not touch |
|-------|---------------------------------|----------------|
| B | `lib/services/ai/**`, `test/services/ai/**`, removing `dart_openai` from `pubspec.yaml`, deleting `lib/services/openai_calendar_event_interpreter.dart` + its test | screens, widgets, models (except bug fixes agreed in this doc) |
| C | `android/app/src/main/**`, `lib/services/platform/**`, `test/services/platform/**` | Dart UI, pubspec (foundation already adds `image_picker`) |
| D | `lib/screens/review_screen.dart`, `lib/widgets/event_form.dart`, `lib/widgets/review/**`, `test/screens/review_screen_test.dart`, `test/widgets/**` | services, settings, home |
| E | `lib/screens/settings_screen.dart`, `lib/widgets/settings/**`, `test/screens/settings_screen_test.dart` | services (use `ModelCatalog` via a fake in tests) |
| F | `lib/main.dart`, `lib/app.dart`, `lib/screens/home_screen.dart`, `lib/widgets/home/**`, `lib/navigation/**`, `lib/providers/**`, `lib/themes/**`, `lib/ui/**` (shared UI helpers e.g. error presentation), `test/screens/home_screen_test.dart`, `test/widget_test.dart` | review/settings screens, services |

Shared rules for every agent:
- `export PATH=/root/sdk/flutter/bin:$PATH`; run `flutter pub get` in your worktree first.
- Definition of done: `flutter analyze` → **No issues found**; `flutter test` → all green; new behaviour covered by tests.
- Only workstream C (and foundation) run Gradle/APK builds (`flutter build apk --debug`), one at a time.
- Commit your work in your worktree (several focused commits are fine). Commit messages: imperative subject line; end with the attribution trailer given in your brief. Do **not** push.
- If a contract is insufficient, implement the smallest compatible addition (new optional parameter / new member), and report it explicitly in your final summary.

Shared files in Phase 2 (the orchestrator resolves merges; keep edits minimal and additive):
- `lib/main.dart` — **only F edits it**. B and C do not wire their implementations; report the class + constructor and the orchestrator swaps `LegacyAiServiceFactory` / `TextOnlySharedContentSource` / `UnsupportedImageInputService` during integration.
- `lib/services/services.dart` (barrel) — update only the export lines for files you add/delete.
- `test/screens/screens_smoke_test.dart` — update only the group for your own screen if your change breaks it (F owns the Home group, D the Review group, E the Settings group).
- `test/helpers/fakes.dart`, `test/helpers/test_app.dart` — do not modify; subclass or add your own helper file next to your tests. Additive changes only if unavoidable (report them).
- `pubspec.yaml` — B removes `dart_openai`; E may add `package_info_plus` (latest). Nobody else changes deps.

## 6.0 Shared UI conventions (D, E, F)

Three agents build UI in parallel; these rules keep the app coherent.
- **Components (M3)**: one primary action per screen as `FilledButton` (or `FilledButton.icon`); secondary `OutlinedButton`/`TextButton`; destructive actions use `colorScheme.error`. Cards: `Card.filled` for content groups, `Card.outlined` for inputs/sections; radius from theme (12). Use `ListTile`s for settings rows, `SegmentedButton` for 2–3 way choices, `Switch` (via `SwitchListTile`) for booleans, `FilterChip` for filters, `InputChip`/`Chip` for attachments and badges, `Badge`/small `Chip` for capability tags.
- **Layout**: 16 px horizontal page padding; spacing scale 4/8/12/16/24/32; section headers `textTheme.titleSmall` in `colorScheme.primary`; max content width 640 (center on tablets). Primary bottom actions in a `SafeArea` bottom bar that stays above the keyboard.
- **Colour**: only `Theme.of(context).colorScheme` roles — never `Colors.*` literals. Status mapping: success → `primary` / `primaryContainer`; warning / "check this" → `tertiary` / `tertiaryContainer`; error → `error` / `errorContainer`. Verify light and dark.
- **Typography**: `textTheme` styles only; no fixed heights around text; must not overflow at `textScaler` 2.0.
- **Copy**: sentence case ("Find events", "Add to calendar", "Choose model"); short; no exclamation marks except success snackbars; provider-aware wording (never hard-code "OpenAI" outside provider-specific copy). Dates via `intl` locale-aware formats.
- **Feedback**: floating `SnackBar`s for transient results (with Undo/Action where useful); inline banners (`MaterialBanner`-like cards) for persistent problems; every icon-only button has a `tooltip`.
- **Icons**: Material `Icons.*` outlined variants where available (`Icons.event_outlined`, `Icons.photo_outlined`, `Icons.content_paste`, `Icons.auto_awesome`, `Icons.format_quote`, `Icons.info_outline`).
- Shared reusable error UI lives in `lib/ui/error_presentation.dart` (F). D and E must not depend on it during Phase 2 (it doesn't exist yet in their worktrees); the orchestrator may unify later.

## 6. Workstream specs

### 6.A Foundation (Phase 1)
1. **Deps**: upgrade every dependency to latest (section 2). Add `http`, `image_picker`, `dynamic_color` (drop it if incompatible with `material_ui` even via the bridge), `material_ui`. Remove `ical`. Keep `dart_openai` only as long as the temporary adapter needs it (B removes it). Run `dart fix --apply --code=migrate_design_widgets`, then fix all analyzer findings under `flutter_lints 6`.
2. **flutter_secure_storage 11**: read the changelog (9→10→11). Existing users' stored OpenAI key (written with `AndroidOptions(encryptedSharedPreferences: true)`) **must remain readable** after the upgrade — use the package's documented migration path.
   *Done:* 11.0.0 **removed** the EncryptedSharedPreferences backend, so v2.x data (written by v9) is unreadable after the upgrade and cannot be migrated. The owner accepted that users re-enter their API key once. v3.0 therefore uses `flutter_secure_storage: ^11.2.0` and calls `checkUpgradeStatus()` before the first secure read; on `legacyDataUnreadable`/`legacyDataDiscarded` the service reports `apiKeysLostInUpgrade` (once, tracked by the `api_key_lost_notice_shown` pref) and Home shows a warning banner "Please re-enter your API key" with an Open-settings action.
3. **Android build**: align AGP / Kotlin / Gradle wrapper / Java target with the Flutter 3.50 template; `ndkVersion = flutter.ndkVersion`; release signing uses `key.properties` when present, otherwise falls back to the debug signing config (CI still creates `key.properties`). Verify `flutter build apk --debug`.
4. **iCal**: implement `CalendarCreator` contract in `services/calendar/icalendar_creator.dart` without `ical`: `VCALENDAR` (`VERSION:2.0`, `PRODID`, `CALSCALE:GREGORIAN`, `METHOD:PUBLISH`), `VEVENT` with `UID`, `DTSTAMP`, `DTSTART`/`DTEND` in UTC (`…Z`) or `;VALUE=DATE` for all-day, `SUMMARY`, `DESCRIPTION`, `LOCATION`; TEXT escaping (`\\`, `;`, `,`, newlines); CRLF line endings; line folding at 75 octets (UTF-8 safe). Thorough unit tests. Move the Android calendar method-channel call into `services/calendar/`.
5. **Contracts**: implement every model in 4.1 fully (with tests), create every interface in 4.2, wire 4.3. Settings persistence v2 with migration from v1 (keys `openai_api_key` [secure], `openai_model`, `max_retries`, `timeout_seconds`, `debug_mode`, `settings_version`); new keys `opper_api_key` [secure], `ai_provider`, `opper_model`, `theme_mode`, `auto_process_shared`, `structured_output_mode`. v1 `debug_mode == true` (which forced dark theme) migrates to `themeMode: dark, debugMode: false`.
6. **Temporary adapters** so the app keeps compiling and working: a `LegacyAiServiceFactory` that adapts the existing OpenAI interpreter to `CalendarEventInterpreter` (multi-event path) and a minimal `ModelCatalog`; a text-only `SharedContentSource` over the existing share channel; a stub `ImageInputService` (`pickFromGallery` returns null). Rename `EventDetailsScreen` → `ReviewScreen(result:)` (file `screens/review_screen.dart`) and route results via `AppRouter.openReview`. Remove `CalendarEventProperties` and its tests (port relevant assertions).
7. Bump version to `3.0.0`. Commit.

### 6.B AI providers & structured output
- `OpenAiCompatibleClient` (package `http`, injectable `http.Client`): `POST {baseUrl}/chat/completions`, bearer auth, timeout, cancellation (close request / ignore result → `AiException(cancelled)`), retries with exponential backoff + jitter for network/timeout/429 (respect `Retry-After`)/5xx only; map status codes and bodies to `AiErrorKind` (401/403 → auth; 404 or "model not found" → modelNotFound; 429 with quota wording → quotaExceeded else rateLimited; 400 mentioning image/vision → unsupportedInput).
- `ProviderConfig` per `AiProvider`: base URL, models endpoint, capability strategy, request quirks (reasoning models: omit `temperature`, use `reasoning_effort: "low"` where supported; Opper: derive from `params.reasoning.supported` / `params.temperature`).
- `DefaultModelCatalog`: Opper — `GET /v3/models?type=llm&limit=0` (no key), map capabilities, mark `featured=true` models as recommended (second request or `featured` field), sort recommended first then by vendor/name; OpenAI — `GET /v1/models` with key, filter out non-chat models (embedding, tts, whisper, dall-e, image, audio, realtime, transcribe, moderation, search, computer-use), apply heuristics (section 2) and recommend a short list (`gpt-5-mini`, `gpt-5`, `gpt-4.1-mini`, …). In-memory cache + persisted cache (shared_preferences JSON, 24 h TTL). `verifyApiKey`: OpenAI `GET /v1/models`; Opper — a cheap authenticated request (e.g. `GET /v3/models?include=route&limit=1`, or a 1-token chat completion; verify which returns 401 for a bad key).
- **One unified schema** (strict-compatible, no `$ref`):
  `{events: [{title: string, description: string|null, location: string|null, start: string, end: string, all_day: boolean, evidence: {title: E, description: E, location: E, start: E, end: E}}]}` where `E = {quote: string|null, reasoning: string, confidence: "high"|"medium"|"low"}`; every object `additionalProperties: false`, all keys required. `start`/`end`: ISO 8601 with the user's UTC offset; for all-day events, `start` = first day, `end` = **last day (inclusive)** — the parser converts to the exclusive model representation.
- Prompt: current date (with weekday), time, IANA-ish zone name + offset; extraction rules (from v2, cleaned up; defaults: 1 h duration; time-less naturally all-day things → `all_day`; otherwise date-only → 09:00 with `low` confidence); evidence rules (quote must be verbatim and short, ≤ 15 words; `null` when inferred; reasoning ≤ 1 sentence, written in English; title/description in the source language); empty `events` when nothing is found; image inputs: read the text in the image (flyers, screenshots, invitations, tickets).
- Downgrade ladder: (1) `json_schema` strict when `structuredOutputMode == auto` and the model supports it (`true` or `null`/unknown); (2) on a 400 that mentions `response_format`/`json_schema`/`strict` → retry with `{"type":"json_object"}` + schema in the prompt; (3) on a 400 for that too → no `response_format`, prompt-only; remember the downgrade per model for the session. Parser is lenient: strips code fences, extracts the outermost JSON object, accepts a bare array or a single event object, accepts v2 capitalised keys (`Summary`, `Start`, …).
- Normalisation → `EventModel` (local time, evidence map, `isAllDay`), never throws for a single bad event (skip it + warning if unrecoverable).
- Images: base64 data URLs; refuse early with `AiException(unsupportedInput)` if the model is known to lack vision; cap total payload (e.g. 8 MB) with a clear error.
- `DefaultAiServiceFactory` replaces `LegacyAiServiceFactory`; delete the old interpreter, `dart_openai`.
- Tests: `MockClient` for request shape (schema present/absent, image parts, auth header, base URLs, reasoning params), downgrade ladder, error mapping, retry/backoff (fake delays), parser edge cases, catalog mapping from a trimmed real Opper JSON fixture (`test/fixtures/`). Optional live smoke tests that run only when `OPENAI_API_KEY` / `OPPER_API_KEY` are set in `.env` (update `.env.example`).

### 6.C Android image sharing & image input
- Manifest: keep text `SEND`; add `SEND` + `SEND_MULTIPLE` for `image/*`; keep the `text/calendar` VIEW filter.
- `MainActivity.kt`: parse `EXTRA_TEXT`, `EXTRA_SUBJECT` (prepend if useful), `EXTRA_STREAM` (single/multiple); copy each image via `ContentResolver` into `cacheDir/shared_images/`, downscale to ≤ 2048 px long edge, honour EXIF orientation (`androidx.exifinterface`), re-encode JPEG q≈85; cap to 4 images; delete files older than 24 h on startup. Do heavy work off the main thread. Deliver to Flutter: method `getInitialSharedContent` (consumed once) and push `onSharedContent` via `MethodChannel.invokeMethod` when `onNewIntent` fires while the engine is running. Payload: `{text: String?, images: [{path, mimeType}]}`.
- `AndroidSharedContentSource` implements `SharedContentSource`; replaces the foundation's text-only adapter. Delete `shared_text_handler.dart` / `android_platform_service.dart` once unused.
- `PickerImageInputService` implements `ImageInputService` with `image_picker` (`maxWidth/maxHeight: 2048`, `imageQuality: 85`); camera via the system camera intent (no CAMERA permission needed — do not declare it).
- Verify with `flutter build apk --debug`. Dart tests with a mocked `MethodChannel` (initial content, stream events, malformed payloads).

### 6.D Review screen & evidence UI
- `ReviewScreen(result)`: app bar "Review events" (`N events` subtitle). Top: collapsible **Source** card — original text (selectable) with the active field's quote highlighted (case/whitespace-insensitive match; fall back to showing the quote) and image thumbnails (tap → full screen). Warnings from `result.warnings` as a subtle banner. Debug mode: "Raw AI response" expandable.
- Event cards: header (title, locale-aware time range, all-day chip), body = `EventForm`; delete with Undo snackbar; ≤ 3 events expanded by default.
- `EventForm`: fields title/description/location; All-day switch; start/end date+time pickers (M3 styling, locale-aware, 24 h aware); changing start shifts end (keeps duration); duration chip. Under each field an **evidence line**: quote icon + “quote” + reasoning, tap to expand / highlight in source; `low` confidence → amber "Check" badge (colour-scheme `tertiary`/`error` roles, not hard-coded colours); after the user edits a field show "Edited by you" instead of the AI reasoning.
- Bottom bar: primary "Add to calendar" / "Add N events to calendar" → validate all → `CalendarCreator.createIcsFile` + `openInCalendarApp` → on success pop with `ReviewOutcome.exported`; on "no calendar app" show actionable message. Back/close with edits → confirm discard dialog.
- Empty result (0 events): friendly empty state with "Edit text" (pop) — F also handles 0 events before navigating, but be robust.
- Widget tests: evidence rendering, low-confidence badge, quote highlight, delete/undo, all-day toggle, duration-preserving start change, export success/failure with a fake `CalendarCreator`.

### 6.E Settings & model picker
- Sections: **AI provider** (`SegmentedButton` OpenAI | Opper, short description of each — Opper: "One key, hundreds of models from many vendors, EU-hosted"); **API key** for the selected provider (obscured, show/hide, paste, "Get a key" link, **Verify** button with inline result; keys for both providers are kept); **Model** tile showing the selected model + capability badges (Structured output, Vision; "unknown" state) → opens the **model picker** (full-screen dialog: search field, filter chips "Structured output", "Vision", recommended section first, rows with vendor, badges, Opper speed/quality; pull-to-refresh; offline/error state with retry; allow entering a custom model id); **Sharing** (Auto-process shared content); **Appearance** (theme System/Light/Dark); **Advanced** (collapsed: structured output Auto/Off, max retries, timeout, debug mode); **About** (version from `package_info_plus` *only if already a dependency* — otherwise a constant, GitHub link, privacy note: "Your text and images are sent to {provider} for processing").
- Save model: changes apply immediately (auto-save, debounce key typing) or a clear Save button — pick one consistently; no lost edits on back navigation.
- Warn (non-blocking) when the chosen model lacks structured output ("results may be less reliable") or vision ("photos won't work with this model").
- Widget tests with a fake `ModelCatalog` and fake `SettingsService`.

### 6.F Home/composer, theme, app shell
- `HomeScreen` = composer: setup card when `!isConfigured` (CTA → settings); multi-line text field with hint + example chips when empty; attached image thumbnails (remove ×); actions: Paste, Gallery, Camera (hidden if unsupported), Clear; status chip "Provider · model" (tap → settings); primary FilledButton **Find events**, pinned above the keyboard. Image attached but model known non-vision → inline warning with "Change model".
- Processing: disable inputs, progress indicator with stage text ("Reading your text…" / "Looking at your image…"), **Cancel**.
- Result: 0 events → inline message ("No events found — try adding a date or time"); ≥1 → `AppRouter.openReview`; on `ReviewOutcome.exported` clear the composer and show a success snackbar.
- Errors: map `AiException.kind` → message + action button (auth/notConfigured → Open settings; modelNotFound → Choose model; unsupportedInput → Choose a vision model; network/timeout/server/rateLimited → Retry). Put this mapping in `lib/ui/error_presentation.dart` so D/E can reuse it.
- Sharing: on start `takeInitialSharedContent()`, and listen to `sharedContentStream`; fill the composer (replace if empty, otherwise ask/append — keep it simple: replace and show "Shared content loaded" snackbar); if `settings.autoProcessShared && isConfigured` start extraction automatically.
- Theme: M3, `dynamic_color` with seed fallback, light/dark from `settings.themeMode`, surface-coloured app bars, no hard-coded status colours; consistent 16 px gutters; text-scale safe.
- `AppStateProvider`/`AppRouter`/`main.dart` per contract 4.3 (replace temp adapters with real implementations once B/C merge — in Phase 2 wire whatever exists; the orchestrator swaps factories during integration).
- Widget tests: composer enable/disable, image chips, share → auto-process (fake source + fake interpreter), error → action, cancel.

## 7. Risks
- **material_ui ecosystem lag**: plugins compiled against `flutter/material` types → use `MaterialUiCompatibilityBridge`; drop `dynamic_color` if it can't interoperate.
- **Secure storage v11 drops v2.x keys** (unmigratable) → detected with `checkUpgradeStatus()`, tested, and surfaced as a re-enter-key banner; other settings are kept.
- **Structured output variance across Opper's upstream vendors** → validation errors surface as `invalidResponse`; downgrade ladder + lenient parser.
- **Image payload size / latency** → downscale on device, cap count and bytes, clear progress UI.
- **No device/emulator here** → Android verified by build only; UI verified by widget tests and a web build screenshot audit (platform channels unavailable on web — services must degrade gracefully, e.g. `kIsWeb` → no-op share source).
