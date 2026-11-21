import 'package:event_snap_2/models/ai_provider.dart';
import 'package:event_snap_2/services/ai/model_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelHeuristics (OpenAI ids)', () {
    test('baseId strips Opper routes and fine-tune decorations', () {
      expect(ModelHeuristics.baseId('openai/GPT-5-mini'), 'gpt-5-mini');
      expect(
        ModelHeuristics.baseId('ft:gpt-4o-mini-2024-07-18:acme::abc123'),
        'gpt-4o-mini-2024-07-18',
      );
      expect(ModelHeuristics.baseId('openai:flex/gpt-6-luna'), 'gpt-6-luna');
    });

    test('chat model filter', () {
      for (final id in [
        'gpt-5-mini',
        'gpt-4.1',
        'gpt-4o-2024-08-06',
        'o3',
        'o4-mini',
        'chatgpt-4o-latest',
        'gpt-3.5-turbo',
        'ft:gpt-4o-mini:acme::x',
      ]) {
        expect(ModelHeuristics.isOpenAiChatModel(id), isTrue, reason: id);
      }
      for (final id in [
        'text-embedding-3-small',
        'tts-1',
        'whisper-1',
        'dall-e-3',
        'gpt-image-1',
        'gpt-4o-audio-preview',
        'gpt-4o-realtime-preview',
        'gpt-4o-transcribe',
        'omni-moderation-latest',
        'gpt-4o-search-preview',
        'computer-use-preview',
        'gpt-3.5-turbo-instruct',
        'gpt-5-codex',
        'o3-pro',
        'gpt-5-pro',
        'o4-mini-deep-research',
        'davinci-002',
      ]) {
        expect(ModelHeuristics.isOpenAiChatModel(id), isFalse, reason: id);
      }
    });

    test('structured output support', () {
      const expected = <String, bool?>{
        'gpt-4o': true,
        'gpt-4o-mini': true,
        'gpt-4o-2024-05-13': false,
        'gpt-4.1-mini': true,
        'gpt-4.5-preview': true,
        'gpt-5-nano': true,
        'gpt-6-luna': true,
        'gpt-7': true,
        'o1': true,
        'o1-mini': false,
        'o1-preview': false,
        'o3-mini': true,
        'o4-mini': true,
        'gpt-3.5-turbo': false,
        'gpt-4': false,
        'gpt-4-0613': false,
        'gpt-4-turbo': false,
        'gpt-3.5-turbo-instruct': false,
        'chatgpt-4o-latest': null,
        'some-new-model': null,
      };
      expected.forEach((id, value) {
        expect(ModelHeuristics.openAiStructuredOutput(id), value, reason: id);
      });
    });

    test('vision support', () {
      const expected = <String, bool?>{
        'gpt-4o-mini': true,
        'gpt-4-turbo': true,
        'gpt-4-turbo-preview': false,
        'gpt-4.1-nano': true,
        'gpt-5-mini': true,
        'gpt-5-codex': false,
        'gpt-6-luna': true,
        'o1': true,
        'o1-mini': false,
        'o3': true,
        'o3-mini': false,
        'o4-mini': true,
        'gpt-3.5-turbo': false,
        'gpt-4': false,
        'mystery': null,
      };
      expected.forEach((id, value) {
        expect(ModelHeuristics.openAiVision(id), value, reason: id);
      });
    });

    test('reasoning models get reasoning_effort and no temperature', () {
      final gpt5 = ModelHeuristics.openAiProfile('gpt-5-mini');
      expect(gpt5.reasoningEfforts, contains('minimal'));
      expect(gpt5.reasoningEffortFor(const ['low']), 'low');
      expect(gpt5.temperatureFor(0.2, sendsReasoning: true), isNull);
      expect(gpt5.acceptsTemperature, isFalse);

      final o3 = ModelHeuristics.openAiProfile('o3');
      expect(o3.reasoningEfforts, ['low', 'medium', 'high']);
      expect(o3.reasoningEffortFor(const ['minimal', 'low']), 'low');

      final gpt41 = ModelHeuristics.openAiProfile('gpt-4.1-mini');
      expect(gpt41.reasoningEfforts, isEmpty);
      expect(gpt41.reasoningEffortFor(const ['low']), isNull);
      expect(gpt41.temperatureFor(0.2, sendsReasoning: false), 0.2);

      expect(
        ModelHeuristics.isOpenAiReasoningModel('gpt-5-chat-latest'),
        false,
      );
      final chat = ModelHeuristics.openAiProfile('gpt-5-chat-latest');
      expect(chat.reasoningEfforts, isEmpty);
      expect(chat.acceptsTemperature, isFalse);
    });

    test('guessProfile for Opper ids', () {
      final routed = ModelHeuristics.guessProfile(
        AiProvider.opper,
        'openai/gpt-5-mini',
      );
      expect(routed.supportsStructuredOutput, isTrue);
      expect(routed.supportsVision, isTrue);
      // Opper quirks unknown → nothing optional is sent.
      expect(routed.reasoningEfforts, isEmpty);
      expect(routed.acceptsTemperature, isFalse);

      final other = ModelHeuristics.guessProfile(
        AiProvider.opper,
        'anthropic/claude-haiku-5-5',
      );
      expect(other.supportsStructuredOutput, isNull);
      expect(other.supportsVision, isNull);
    });
  });

  group('ModelProfile', () {
    test('reasoningEffortFor prefers the list, else the lowest non-none', () {
      const profile = ModelProfile(
        modelId: 'm',
        reasoningEfforts: ['none', 'medium', 'high'],
      );
      expect(profile.reasoningEffortFor(const ['low', 'minimal']), 'medium');
      expect(profile.reasoningEffortFor(const ['low', 'none']), 'none');
      const onlyHigh = ModelProfile(modelId: 'm', reasoningEfforts: ['high']);
      expect(onlyHigh.reasoningEffortFor(const ['low']), 'high');
    });

    test('temperatureFor clamps and is omitted with reasoning', () {
      const profile = ModelProfile(
        modelId: 'm',
        acceptsTemperature: true,
        minTemperature: 0.5,
        maxTemperature: 1,
      );
      expect(profile.temperatureFor(0.2, sendsReasoning: false), 0.5);
      expect(profile.temperatureFor(1.5, sendsReasoning: false), 1);
      expect(profile.temperatureFor(0.2, sendsReasoning: true), isNull);
      expect(
        const ModelProfile.unknown('m')
            .temperatureFor(0.2, sendsReasoning: false),
        isNull,
      );
    });

    test('cache round trip', () {
      const profile = ModelProfile(
        modelId: 'x',
        reasoningEfforts: ['low', 'high'],
        acceptsTemperature: true,
        minTemperature: 0,
        maxTemperature: 1,
      );
      final restored = ModelProfile.fromCache(
        'x',
        profile.toJson(),
        supportsVision: true,
      );
      expect(restored.reasoningEfforts, ['low', 'high']);
      expect(restored.acceptsTemperature, isTrue);
      expect(restored.maxTemperature, 1);
      expect(restored.supportsVision, isTrue);
      expect(const ModelProfile(modelId: 'y').toJson(), isEmpty);
    });
  });
}
