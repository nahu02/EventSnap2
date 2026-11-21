import 'dart:async';

import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/services/ai/ai_cancellation_token.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/services/ai/ai_service_factory.dart';
import 'package:event_snap_2/services/ai/legacy/legacy_ai_service_factory.dart';
import 'package:event_snap_2/services/ai/model_catalog.dart';
import 'package:event_snap_2/services/openai_calendar_event_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher throwsAiError(AiErrorKind kind) =>
    throwsA(isA<AiException>().having((e) => e.kind, 'kind', kind));

void main() {
  const settings = Settings(
    openAiApiKey: 'sk-test1234567890',
    openAiModel: 'gpt-4.1',
  );
  final event = EventModel(
    title: 'Dentist',
    startDateTime: DateTime(2025, 6, 3, 14, 30),
    endDateTime: DateTime(2025, 6, 3, 15, 30),
  );

  group('LegacyAiServiceFactory', () {
    test('implements AiServiceFactory with a ModelCatalog', () {
      final factory = LegacyAiServiceFactory();
      expect(factory, isA<AiServiceFactory>());
      expect(factory.modelCatalog, isA<ModelCatalog>());
      expect(
        factory.createInterpreter(settings),
        isA<LegacyCalendarEventInterpreter>(),
      );
    });

    test('maps the legacy extraction to an ExtractionResult', () async {
      String? receivedText;
      final factory = LegacyAiServiceFactory(
        extractor: (s, text) async {
          receivedText = text;
          return LegacyOpenAiExtraction(
            events: [event],
            warnings: const ['Skipped event 2: missing start time'],
            rawResponse: '{"events": []}',
          );
        },
      );
      const input = ExtractionInput(text: 'Dentist next Tuesday 2:30pm');
      final result = await factory
          .createInterpreter(settings)
          .extractEvents(input);

      expect(receivedText, input.text);
      expect(result.events, [event]);
      expect(result.input, input);
      expect(result.provider, AiProvider.openai);
      expect(result.model, 'gpt-4.1');
      expect(result.usedStructuredOutput, isFalse);
      expect(result.warnings, ['Skipped event 2: missing start time']);
      expect(result.rawResponse, '{"events": []}');
    });

    test('rejects empty input and images', () async {
      final interpreter = LegacyCalendarEventInterpreter(
        settings,
        extractor: (s, t) async => throw StateError('must not be called'),
      );
      await expectLater(
        interpreter.extractEvents(const ExtractionInput(text: '  ')),
        throwsAiError(AiErrorKind.unsupportedInput),
      );
      await expectLater(
        interpreter.extractEvents(
          const ExtractionInput(
            text: 'x',
            images: [InputImage(path: '/a.jpg')],
          ),
        ),
        throwsAiError(AiErrorKind.unsupportedInput),
      );
    });

    test('requires a configured OpenAI provider', () async {
      Future<LegacyOpenAiExtraction> never(Settings s, String t) =>
          throw StateError('must not be called');
      await expectLater(
        LegacyCalendarEventInterpreter(
          Settings.defaults(),
          extractor: never,
        ).extractEvents(const ExtractionInput(text: 'x')),
        throwsAiError(AiErrorKind.notConfigured),
      );
      await expectLater(
        LegacyCalendarEventInterpreter(
          const Settings(provider: AiProvider.opper, opperApiKey: 'op-1'),
          extractor: never,
        ).extractEvents(const ExtractionInput(text: 'x')),
        throwsAiError(AiErrorKind.notConfigured),
      );
    });

    test('passes AiExceptions through and wraps anything else', () async {
      final auth = LegacyCalendarEventInterpreter(
        settings,
        extractor: (s, t) async => throw const AiException(
          AiErrorKind.auth,
          'bad key',
          statusCode: 401,
        ),
      );
      await expectLater(
        auth.extractEvents(const ExtractionInput(text: 'x')),
        throwsAiError(AiErrorKind.auth),
      );
      final other = LegacyCalendarEventInterpreter(
        settings,
        extractor: (s, t) async => throw StateError('oops'),
      );
      await expectLater(
        other.extractEvents(const ExtractionInput(text: 'x')),
        throwsAiError(AiErrorKind.unknown),
      );
    });

    test('cancellation before the call', () async {
      final interpreter = LegacyCalendarEventInterpreter(
        settings,
        extractor: (s, t) async => throw StateError('must not be called'),
      );
      await expectLater(
        interpreter.extractEvents(
          const ExtractionInput(text: 'x'),
          cancellationToken: AiCancellationToken()..cancel(),
        ),
        throwsAiError(AiErrorKind.cancelled),
      );
    });

    test('cancellation while the request is in flight', () async {
      final pending = Completer<LegacyOpenAiExtraction>();
      final interpreter = LegacyCalendarEventInterpreter(
        settings,
        extractor: (s, t) => pending.future,
      );
      final token = AiCancellationToken();
      final future = interpreter.extractEvents(
        const ExtractionInput(text: 'x'),
        cancellationToken: token,
      );
      token.cancel();
      await expectLater(future, throwsAiError(AiErrorKind.cancelled));
      // A late result is ignored.
      pending.complete(
        const LegacyOpenAiExtraction(events: [], warnings: [], rawResponse: ''),
      );
    });
  });

  group('LegacyModelCatalog', () {
    test('Opper returns the default model without a key', () async {
      final catalog = LegacyModelCatalog();
      final models = await catalog.listModels(AiProvider.opper, apiKey: '');
      expect(models.map((m) => m.id), contains(AiProvider.opper.defaultModel));
      expect(models.every((m) => m.provider == AiProvider.opper), isTrue);
      expect(
        await catalog.findModel(
          AiProvider.opper,
          'openai/gpt-5-mini',
          apiKey: '',
        ),
        isNotNull,
      );
      expect(
        await catalog.findModel(AiProvider.opper, 'nope', apiKey: ''),
        isNull,
      );
    });

    test('OpenAI requires a key', () async {
      await expectLater(
        LegacyModelCatalog().listModels(AiProvider.openai, apiKey: ' '),
        throwsAiError(AiErrorKind.notConfigured),
      );
    });

    test('verifyApiKey rejects blank keys', () async {
      for (final provider in AiProvider.values) {
        await expectLater(
          LegacyModelCatalog().verifyApiKey(provider, ''),
          throwsAiError(AiErrorKind.notConfigured),
        );
      }
    });
  });
}
