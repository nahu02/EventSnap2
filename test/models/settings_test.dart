import 'package:flutter_test/flutter_test.dart';
import 'package:event_snap_2/models/settings.dart';

void main() {
  group('Settings', () {
    const validApiKey = 'sk-test123456789';
    const validModel = 'gpt-4.1';

    group('Constructor', () {
      test('creates settings with required fields', () {
        final settings = Settings(openAiApiKey: validApiKey);

        expect(settings.openAiApiKey, equals(validApiKey));
        expect(settings.openAiModel, equals('gpt-4.1'));
        expect(settings.maxRetries, equals(3));
        expect(settings.timeoutSeconds, equals(30));
        expect(settings.debugMode, isFalse);
      });

      test('creates settings with all fields', () {
        final settings = Settings(
          openAiApiKey: validApiKey,
          openAiModel: 'gpt-3.5-turbo',
          maxRetries: 5,
          timeoutSeconds: 60,
          debugMode: true,
        );

        expect(settings.openAiApiKey, equals(validApiKey));
        expect(settings.openAiModel, equals('gpt-3.5-turbo'));
        expect(settings.maxRetries, equals(5));
        expect(settings.timeoutSeconds, equals(60));
        expect(settings.debugMode, isTrue);
      });

      test('throws error when API key is empty', () {
        expect(() => Settings(openAiApiKey: ''), throwsArgumentError);
      });

      test('throws error when API key is whitespace', () {
        expect(() => Settings(openAiApiKey: '   '), throwsArgumentError);
      });

      test('throws error when model is empty', () {
        expect(
          () => Settings(openAiApiKey: validApiKey, openAiModel: ''),
          throwsArgumentError,
        );
      });

      test('throws error when max retries is negative', () {
        expect(
          () => Settings(openAiApiKey: validApiKey, maxRetries: -1),
          throwsArgumentError,
        );
      });

      test('throws error when max retries is too high', () {
        expect(
          () => Settings(openAiApiKey: validApiKey, maxRetries: 11),
          throwsArgumentError,
        );
      });

      test('throws error when timeout is too low', () {
        expect(
          () => Settings(openAiApiKey: validApiKey, timeoutSeconds: 4),
          throwsArgumentError,
        );
      });

      test('throws error when timeout is too high', () {
        expect(
          () => Settings(openAiApiKey: validApiKey, timeoutSeconds: 301),
          throwsArgumentError,
        );
      });
    });

    group('Factory Constructors', () {
      test('creates default settings', () {
        final settings = Settings.defaults();

        expect(settings.openAiApiKey, equals(''));
        expect(settings.openAiModel, equals('gpt-4.1'));
        expect(settings.maxRetries, equals(3));
        expect(settings.timeoutSeconds, equals(30));
        expect(settings.debugMode, isFalse);
      });
    });

    group('JSON Serialization', () {
      test('converts to JSON correctly', () {
        final settings = Settings(
          openAiApiKey: validApiKey,
          openAiModel: validModel,
          maxRetries: 5,
          timeoutSeconds: 60,
          debugMode: true,
        );

        final json = settings.toJson();

        expect(json['openAiApiKey'], equals(validApiKey));
        expect(json['openAiModel'], equals(validModel));
        expect(json['maxRetries'], equals(5));
        expect(json['timeoutSeconds'], equals(60));
        expect(json['debugMode'], isTrue);
      });

      test('converts from JSON correctly', () {
        final json = {
          'openAiApiKey': validApiKey,
          'openAiModel': validModel,
          'maxRetries': 5,
          'timeoutSeconds': 60,
          'debugMode': true,
        };

        final settings = Settings.fromJson(json);

        expect(settings.openAiApiKey, equals(validApiKey));
        expect(settings.openAiModel, equals(validModel));
        expect(settings.maxRetries, equals(5));
        expect(settings.timeoutSeconds, equals(60));
        expect(settings.debugMode, isTrue);
      });

      test('uses defaults for missing JSON fields', () {
        final json = {'openAiApiKey': validApiKey};

        final settings = Settings.fromJson(json);

        expect(settings.openAiApiKey, equals(validApiKey));
        expect(settings.openAiModel, equals('gpt-4.1'));
        expect(settings.maxRetries, equals(3));
        expect(settings.timeoutSeconds, equals(30));
        expect(settings.debugMode, isFalse);
      });
    });

    group('Validation', () {
      test('validates correctly for valid settings', () {
        final settings = Settings(openAiApiKey: validApiKey);

        expect(settings.validate(), isEmpty);
        expect(settings.isValid, isTrue);
        expect(settings.hasApiKey, isTrue);
        expect(settings.isReadyForUse, isTrue);
      });

      test('validates empty API key', () {
        final settings = Settings.defaults();

        final errors = settings.validate();
        expect(errors, contains('OpenAI API key is required'));
        expect(settings.isValid, isFalse);
        expect(settings.hasApiKey, isFalse);
        expect(settings.isReadyForUse, isFalse);
      });

      test('validates invalid API key format', () {
        final settings = Settings(openAiApiKey: 'invalid-key');

        final errors = settings.validate();
        expect(errors, contains('OpenAI API key should start with "sk-"'));
        expect(settings.isValid, isFalse);
      });

      test('validates empty model', () {
        final settings = Settings(
          openAiApiKey: validApiKey,
          openAiModel: 'valid-model',
        );
        // Manually set invalid model to test validation
        settings.openAiModel = '';

        final errors = settings.validate();
        expect(errors, contains('OpenAI model cannot be empty'));
        expect(settings.isValid, isFalse);
      });

      test('validates invalid retry count', () {
        final settings = Settings(openAiApiKey: validApiKey);
        // Manually set invalid retry count to test validation
        settings.maxRetries = -1;

        final errors = settings.validate();
        expect(errors, contains('Max retries must be between 0 and 10'));
        expect(settings.isValid, isFalse);
      });

      test('validates invalid timeout', () {
        final settings = Settings(openAiApiKey: validApiKey);
        // Manually set invalid timeout to test validation
        settings.timeoutSeconds = 1;

        final errors = settings.validate();
        expect(errors, contains('Timeout must be between 5 and 300 seconds'));
        expect(settings.isValid, isFalse);
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final original = Settings(
          openAiApiKey: validApiKey,
          openAiModel: validModel,
          maxRetries: 3,
          timeoutSeconds: 30,
          debugMode: false,
        );

        final copy = original.copyWith(
          openAiModel: 'gpt-3.5-turbo',
          debugMode: true,
        );

        expect(copy.openAiApiKey, equals(validApiKey));
        expect(copy.openAiModel, equals('gpt-3.5-turbo'));
        expect(copy.maxRetries, equals(3));
        expect(copy.timeoutSeconds, equals(30));
        expect(copy.debugMode, isTrue);
      });
    });

    group('Helper Methods', () {
      test('returns correct timeout duration', () {
        final settings = Settings(
          openAiApiKey: validApiKey,
          timeoutSeconds: 60,
        );

        expect(settings.timeoutDuration, equals(Duration(seconds: 60)));
      });

      test('masks API key correctly for short keys', () {
        final settings = Settings(openAiApiKey: 'sk-123');

        expect(settings.maskedApiKey, equals('******'));
      });

      test('masks API key correctly for long keys', () {
        final settings = Settings(openAiApiKey: 'sk-1234567890abcdef');

        expect(settings.maskedApiKey, equals('sk-*********cdef'));
      });

      test('returns correct hasApiKey status', () {
        final settingsWithKey = Settings(openAiApiKey: validApiKey);
        final settingsWithoutKey = Settings.defaults();

        expect(settingsWithKey.hasApiKey, isTrue);
        expect(settingsWithoutKey.hasApiKey, isFalse);
      });
    });

    group('Equality and HashCode', () {
      test('settings with same properties are equal', () {
        final settings1 = Settings(
          openAiApiKey: validApiKey,
          openAiModel: validModel,
          maxRetries: 3,
          timeoutSeconds: 30,
          debugMode: false,
        );

        final settings2 = Settings(
          openAiApiKey: validApiKey,
          openAiModel: validModel,
          maxRetries: 3,
          timeoutSeconds: 30,
          debugMode: false,
        );

        expect(settings1, equals(settings2));
        expect(settings1.hashCode, equals(settings2.hashCode));
      });

      test('settings with different properties are not equal', () {
        final settings1 = Settings(openAiApiKey: 'sk-key1');
        final settings2 = Settings(openAiApiKey: 'sk-key2');

        expect(settings1, isNot(equals(settings2)));
      });
    });

    group('toString', () {
      test('does not include API key in string representation', () {
        final settings = Settings(openAiApiKey: validApiKey);
        final stringRep = settings.toString();

        expect(stringRep, isNot(contains(validApiKey)));
        expect(stringRep, contains('hasApiKey: true'));
      });
    });
  });
}
