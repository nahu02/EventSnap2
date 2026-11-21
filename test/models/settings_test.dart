import 'dart:convert';

import 'package:event_snap_2/models/ai_provider.dart';
import 'package:event_snap_2/models/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Settings (v2)', () {
    const openAiKey = 'sk-test1234567890abcdef';
    const opperKey = 'op-key-1234567890';

    group('defaults', () {
      test('match the contract', () {
        final s = Settings.defaults();
        expect(s.provider, AiProvider.openai);
        expect(s.openAiApiKey, '');
        expect(s.opperApiKey, '');
        expect(s.openAiModel, AiProvider.openai.defaultModel);
        expect(s.opperModel, AiProvider.opper.defaultModel);
        expect(s.maxRetries, 2);
        expect(s.timeoutSeconds, 60);
        expect(s.themeMode, AppThemeMode.system);
        expect(s.autoProcessShared, isTrue);
        expect(s.structuredOutputMode, StructuredOutputMode.auto);
        expect(s.debugMode, isFalse);
        expect(s, const Settings());
      });

      test('are not configured', () {
        expect(Settings.defaults().isConfigured, isFalse);
      });
    });

    group('per-provider accessors', () {
      const s = Settings(
        openAiApiKey: openAiKey,
        opperApiKey: opperKey,
        openAiModel: 'gpt-5',
        opperModel: 'anthropic/claude-sonnet-5-5',
      );

      test('apiKeyFor / modelFor', () {
        expect(s.apiKeyFor(AiProvider.openai), openAiKey);
        expect(s.apiKeyFor(AiProvider.opper), opperKey);
        expect(s.modelFor(AiProvider.openai), 'gpt-5');
        expect(s.modelFor(AiProvider.opper), 'anthropic/claude-sonnet-5-5');
      });

      test('active values follow the provider', () {
        expect(s.activeApiKey, openAiKey);
        expect(s.activeModel, 'gpt-5');
        final opper = s.copyWith(provider: AiProvider.opper);
        expect(opper.activeApiKey, opperKey);
        expect(opper.activeModel, 'anthropic/claude-sonnet-5-5');
      });

      test('copyWithApiKey / copyWithModel', () {
        final updated = Settings.defaults()
            .copyWithApiKey(AiProvider.opper, opperKey)
            .copyWithModel(AiProvider.opper, 'gemini/gemini-3.8-flash');
        expect(updated.opperApiKey, opperKey);
        expect(updated.opperModel, 'gemini/gemini-3.8-flash');
        expect(updated.openAiApiKey, '');
        expect(updated.openAiModel, AiProvider.openai.defaultModel);
      });
    });

    group('isConfigured', () {
      test('needs key and model of the active provider only', () {
        expect(const Settings(openAiApiKey: openAiKey).isConfigured, isTrue);
        expect(
          const Settings(
            provider: AiProvider.opper,
            openAiApiKey: openAiKey,
          ).isConfigured,
          isFalse,
        );
        expect(
          const Settings(
            provider: AiProvider.opper,
            opperApiKey: opperKey,
          ).isConfigured,
          isTrue,
        );
      });

      test('blank key or model is not configured', () {
        expect(const Settings(openAiApiKey: '   ').isConfigured, isFalse);
        expect(
          const Settings(
            openAiApiKey: openAiKey,
            openAiModel: ' ',
          ).isConfigured,
          isFalse,
        );
      });
    });

    group('validate', () {
      test('valid settings have no errors', () {
        expect(const Settings(openAiApiKey: openAiKey).validate(), isEmpty);
      });

      test('reports missing key/model for the active provider only', () {
        final errors = const Settings(
          provider: AiProvider.opper,
          openAiApiKey: '',
          opperModel: '',
        ).validate();
        expect(errors, contains('Opper API key is required'));
        expect(errors, contains('Opper model is required'));
        expect(errors.any((e) => e.contains('OpenAI')), isFalse);
      });

      test('range checks', () {
        for (final retries in [-1, 11]) {
          final s = Settings(openAiApiKey: openAiKey, maxRetries: retries);
          expect(
            s.validate(),
            contains('Max retries must be between 0 and 10'),
          );
          expect(s.validateRanges(), hasLength(1));
        }
        for (final timeout in [4, 301]) {
          final s = Settings(openAiApiKey: openAiKey, timeoutSeconds: timeout);
          expect(
            s.validate(),
            contains('Timeout must be between 5 and 300 seconds'),
          );
        }
        expect(
          const Settings(maxRetries: 0, timeoutSeconds: 5).validateRanges(),
          isEmpty,
        );
        expect(
          const Settings(maxRetries: 10, timeoutSeconds: 300).validateRanges(),
          isEmpty,
        );
      });

      test('an OpenAI key without sk- is a warning, not an error', () {
        const s = Settings(openAiApiKey: 'invalid-key-format');
        expect(s.validate(), isEmpty);
        expect(
          s.warnings(),
          contains('OpenAI API keys usually start with "sk-"'),
        );
        expect(const Settings(openAiApiKey: openAiKey).warnings(), isEmpty);
      });

      test('whitespace around keys is a warning', () {
        const s = Settings(opperApiKey: ' op-key ');
        expect(s.warnings().single, contains('Opper'));
      });
    });

    test('timeoutDuration', () {
      expect(
        const Settings(timeoutSeconds: 45).timeoutDuration,
        const Duration(seconds: 45),
      );
    });

    group('maskedKeyFor', () {
      test('short keys are fully masked', () {
        expect(
          const Settings(openAiApiKey: 'sk-123')
              .maskedKeyFor(AiProvider.openai),
          '******',
        );
        expect(Settings.defaults().maskedKeyFor(AiProvider.opper), '');
      });

      test('long keys show prefix and suffix only', () {
        expect(
          const Settings(openAiApiKey: 'sk-test123456789')
              .maskedKeyFor(AiProvider.openai),
          'sk-*********6789',
        );
        expect(
          const Settings(opperApiKey: opperKey).maskedKeyFor(AiProvider.opper),
          'op-*********7890',
        );
      });
    });

    test('copyWith updates only the given fields', () {
      const original = Settings(openAiApiKey: openAiKey);
      final copy = original.copyWith(
        provider: AiProvider.opper,
        opperApiKey: opperKey,
        maxRetries: 5,
        themeMode: AppThemeMode.dark,
        autoProcessShared: false,
        structuredOutputMode: StructuredOutputMode.off,
        debugMode: true,
      );
      expect(copy.provider, AiProvider.opper);
      expect(copy.openAiApiKey, openAiKey);
      expect(copy.opperApiKey, opperKey);
      expect(copy.maxRetries, 5);
      expect(copy.timeoutSeconds, original.timeoutSeconds);
      expect(copy.themeMode, AppThemeMode.dark);
      expect(copy.autoProcessShared, isFalse);
      expect(copy.structuredOutputMode, StructuredOutputMode.off);
      expect(copy.debugMode, isTrue);
      expect(original.copyWith(), original);
    });

    group('JSON', () {
      const full = Settings(
        provider: AiProvider.opper,
        openAiApiKey: openAiKey,
        opperApiKey: opperKey,
        openAiModel: 'gpt-5',
        opperModel: 'openai/gpt-5',
        maxRetries: 4,
        timeoutSeconds: 90,
        themeMode: AppThemeMode.light,
        autoProcessShared: false,
        structuredOutputMode: StructuredOutputMode.off,
        debugMode: true,
      );

      test('round-trip', () {
        final json =
            jsonDecode(jsonEncode(full.toJson())) as Map<String, dynamic>;
        expect(json['provider'], 'opper');
        expect(json['themeMode'], 'light');
        expect(json['structuredOutputMode'], 'off');
        expect(Settings.fromJson(json), full);
      });

      test('missing or malformed values use defaults', () {
        expect(Settings.fromJson({}), Settings.defaults());
        final s = Settings.fromJson({
          'provider': 'unknown',
          'themeMode': 'sepia',
          'structuredOutputMode': 42,
          'maxRetries': 3.0,
          'openAiApiKey': 12,
        });
        expect(s.provider, AiProvider.openai);
        expect(s.themeMode, AppThemeMode.system);
        expect(s.structuredOutputMode, StructuredOutputMode.auto);
        expect(s.maxRetries, 3);
        expect(s.openAiApiKey, '');
      });
    });

    group('equality', () {
      test('equal settings', () {
        const a = Settings(openAiApiKey: openAiKey, opperApiKey: opperKey);
        const b = Settings(openAiApiKey: openAiKey, opperApiKey: opperKey);
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('any field difference breaks equality', () {
        const base = Settings();
        final variants = [
          base.copyWith(provider: AiProvider.opper),
          base.copyWith(openAiApiKey: 'x'),
          base.copyWith(opperApiKey: 'x'),
          base.copyWith(openAiModel: 'x'),
          base.copyWith(opperModel: 'x'),
          base.copyWith(maxRetries: 3),
          base.copyWith(timeoutSeconds: 30),
          base.copyWith(themeMode: AppThemeMode.dark),
          base.copyWith(autoProcessShared: false),
          base.copyWith(structuredOutputMode: StructuredOutputMode.off),
          base.copyWith(debugMode: true),
        ];
        for (final v in variants) {
          expect(v, isNot(base));
        }
      });
    });

    test('toString never includes API keys', () {
      const s = Settings(openAiApiKey: openAiKey, opperApiKey: opperKey);
      final text = s.toString();
      expect(text, isNot(contains(openAiKey)));
      expect(text, isNot(contains(opperKey)));
      expect(text, contains('hasOpenAiKey: true'));
      expect(text, contains('hasOpperKey: true'));
    });
  });
}
