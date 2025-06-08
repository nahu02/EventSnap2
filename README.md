# EventSnap2

EventSnap2 is a Flutter mobile app that converts natural language text into calendar events using OpenAI's GPT models. Effortlessly extract event details from plain text and generate iCalendar (.ics) files that integrate with your favorite calendar applications.

> **Currently targets Android, but may work on other platforms with slight tweaks.**

---

## 🚀 Features

- **AI-Powered Event Parsing:** Transforms conversational text into structured calendar entries.
- **Android Sharing Integration:** Share text from any app directly to EventSnap2 for instant event creation.
- **iCalendar (.ics) Export:** Generates RFC 5545-compliant files for seamless calendar integration.
- **Secure API Key Storage:** Uses AES encryption to protect your OpenAI API keys.
- **Robust Error Handling:** Includes retry logic with exponential backoff for resilient API calls.

---

## 🛠️ Technologies & Libraries

- `dart_openai` – Official OpenAI SDK for Dart
- `ical` – iCalendar file generation
- `flutter_secure_storage` – Secure local storage
- `shared_preferences` – Persistent key-value storage
- `path_provider` – File system path access
- `url_launcher` – Open files/URLs on device
- `provider` – State management
- `intl` – Internationalization and date formatting
- `mocktail` – Unit testing mocks

---

## 📦 Project Structure

```
├── android/             # Android-specific platform code (Kotlin for method channels)
├── assets/              # App icons and static assets
├── lib/                 # Main Flutter app code
│   ├── models/          # Data models & JSON serialization
│   ├── navigation/      # Routing and navigation logic
│   ├── providers/       # State management
│   ├── screens/         # UI screens
│   ├── services/        # Business logic & OpenAI/iCalendar integration
│   ├── themes/          # App theming
│   └── widgets/         # Reusable UI components
├── test/                # Unit and integration tests
└── web/                 # PWA support
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

4. **Configure API Key**
   - Obtain an OpenAI API key.
   - The app will prompt you to enter it securely on first launch.

5. **Share Text to EventSnap2**
   - On Android, select text in any app, tap "Share," and choose EventSnap2.

---

## 🙋‍♂️ Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

---

## 📬 Contact

For questions or support, open an issue on GitHub.