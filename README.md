# EventSnap2

EventSnap2 is a Flutter mobile app that turns natural language text, and photos or screenshots of event details, into calendar events. It uses AI models from OpenAI or Opper to extract event details and generates iCalendar (.ics) files that open in your favourite calendar app.

> **Currently targets Android, but may work on other platforms with slight tweaks.**

---

## 📱 Quick Install (Android)

**Download Pre-built APK:**
1. Go to the [Releases](https://github.com/nahu02/EventSnap2/releases) section of this repository
2. Download the APK file from the v3.0.0 release (or the most recent release)
3. Enable "Install from Unknown Sources" in your Android settings:
   - Go to Settings > Security > Unknown Sources (or Settings > Apps > Special Access > Install Unknown Apps)
   - Allow installation from your browser or file manager
4. Open the downloaded APK file and follow the installation prompts

**Note:** You'll need an API key from OpenAI or Opper. Enter it in the app's Settings when you first launch it.

---

## 🚀 Features

- **AI-Powered Event Parsing:** One request finds all events in your text, from zero to many.
- **Photos & Screenshots:** Share up to 4 images from any app to EventSnap2, or add photos from the gallery or camera inside the app. Images are sent to vision-capable models.
- **Evidence for Every Field:** Each extracted field comes with the verbatim quote it was taken from, a one-sentence explanation and a confidence level. Low-confidence fields are flagged with a "Check" badge, and quotes are highlighted in the original text.
- **Structured Output:** When the selected model supports it, results are requested as strict JSON, with automatic fallbacks for models that don't.
- **Review & Edit:** Adjust titles, times and locations, mark events as all-day, and delete events with undo. Edited fields are marked "Edited by you".
- **Android Sharing Integration:** Share text or images from any app directly to EventSnap2.
- **iCalendar (.ics) Export:** Generates RFC 5545-compliant files and opens them with your calendar app.
- **Secure API Key Storage:** Each provider's API key is stored with `flutter_secure_storage`. Keys are never shown in full.
- **Robust Error Handling:** Retries with exponential backoff for transient failures, and error messages that tell you what to do next.
- **Material 3 Design:** Light, dark or system theme, with dynamic colour on supported devices.

---

## 🤖 AI Providers

EventSnap2 supports two providers. Pick one in Settings.

| Provider | Endpoint | Default model | Notes |
|----------|----------|---------------|-------|
| **OpenAI** | `https://api.openai.com/v1` | `gpt-5-mini` | Direct access to OpenAI models. Get a key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys). |
| **Opper** | `https://api.opper.ai/v3/compat` | `openai/gpt-5-mini` | EU-hosted gateway. One key gives access to hundreds of models from many vendors. Get a key at [platform.opper.ai](https://platform.opper.ai). |

- Each provider keeps its own API key and its own selected model, so switching providers doesn't lose your settings.
- Existing v2 users keep their OpenAI key and model.
- The model picker is searchable and shows **Structured output** and **Vision** badges. You can also enter a custom model ID.
- Your text and images are sent to the selected provider for processing.

---

## 🛠️ Technologies & Libraries

- **Flutter 3.50 / Dart 3.14**
- `material_ui` – Material 3 widgets
- `http` – Thin OpenAI-compatible API client
- `provider` – State management
- `flutter_secure_storage` – Secure storage for API keys (pinned to 10.x for data migration)
- `shared_preferences` – Persistent key-value storage
- `image_picker` – Gallery and camera input
- `dynamic_color` – Dynamic Material colour
- `intl` – Internationalization and date formatting
- `url_launcher` – Open files/URLs on device
- `path_provider` – File system path access
- `package_info_plus` – App version information
- `flutter_lints`, `mocktail`, `flutter_dotenv` – Lints, test mocks and optional live-test configuration

---

## 📦 Project Structure

```
├── android/             # Android-specific platform code (Kotlin for method channels)
├── assets/              # App icons and static assets
├── docs/                # Design and implementation notes (v3_plan.md)
├── lib/                 # Main Flutter app code
│   ├── models/          # Data models (events, settings, AI providers, evidence)
│   ├── navigation/      # Routing and navigation logic
│   ├── providers/       # State management
│   ├── screens/         # UI screens (home, review, settings)
│   ├── services/
│   │   ├── ai/          # AI client, prompts, schemas, parsing, model catalog
│   │   ├── calendar/    # iCalendar serializer and Android hand-off
│   │   └── platform/    # Shared content and image input
│   ├── themes/          # App theming
│   ├── ui/              # Shared UI helpers
│   └── widgets/         # Reusable widgets (home, review, settings, event form)
├── test/                # Unit and widget tests (helpers in test/helpers)
```

---

## 📖 Usage

1. **Clone the Repository**
   ```bash
   git clone https://github.com/nahu02/EventSnap2.git
   cd EventSnap2
   ```

2. **Install Dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the App**
   ```bash
   flutter run
   ```

4. **Configure Your AI Provider**
   - Open **Settings**.
   - Choose **OpenAI** or **Opper**.
   - Paste your API key and tap **Verify**.
   - Pick a model. The default is pre-selected.

5. **Create Events**
   - Type or paste text on the home screen, optionally attach images, and tap **Find events**.
   - Review the extracted events, make any changes, and tap **Add to calendar**.

6. **Share to EventSnap2**
   - On Android, select text or one or more images in any app, tap "Share," and choose EventSnap2.
   - If "Auto-process shared content" is on in Settings, extraction starts automatically.

7. **Run Tests**
   ```bash
   flutter test
   ```
   Live API smoke tests run only when `OPPER_API_KEY` and/or `OPENAI_API_KEY` are set in the environment (see `.env.example`), for example:
   ```bash
   env OPPER_API_KEY=... flutter test test/services/ai/live_api_test.dart
   ```

8. **Build an APK**
   ```bash
   flutter build apk
   ```
   Release builds use `android/key.properties` when it is present. Otherwise they use debug signing, so local builds work without a keystore.

---

## 🙋‍♂️ Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

See [`design_doc.md`](design_doc.md) for the architecture and [`docs/v3_plan.md`](docs/v3_plan.md) for the detailed v3 plan and contracts.

---

## 📬 Contact

For questions or support, open an issue on GitHub.
