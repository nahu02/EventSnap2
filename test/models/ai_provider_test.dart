import 'package:event_snap_2/models/ai_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiProvider', () {
    test('has stable storage ids and display names', () {
      expect(AiProvider.openai.id, 'openai');
      expect(AiProvider.opper.id, 'opper');
      expect(AiProvider.openai.displayName, 'OpenAI');
      expect(AiProvider.opper.displayName, 'Opper');
    });

    test('default models', () {
      expect(AiProvider.openai.defaultModel, 'gpt-5-mini');
      expect(AiProvider.opper.defaultModel, 'openai/gpt-5-mini');
    });

    test('API key help URLs are https', () {
      expect(
        AiProvider.openai.apiKeyHelpUrl,
        Uri.parse('https://platform.openai.com/api-keys'),
      );
      expect(AiProvider.opper.apiKeyHelpUrl.scheme, 'https');
      expect(AiProvider.opper.apiKeyHelpUrl.host, 'platform.opper.ai');
    });

    test('API key hints are non-empty', () {
      for (final p in AiProvider.values) {
        expect(p.apiKeyHint, isNotEmpty);
      }
      expect(AiProvider.openai.apiKeyHint, startsWith('sk-'));
    });

    test('fromId parses ids and falls back to openai', () {
      expect(AiProvider.fromId('openai'), AiProvider.openai);
      expect(AiProvider.fromId('opper'), AiProvider.opper);
      expect(AiProvider.fromId(' Opper '), AiProvider.opper);
      expect(AiProvider.fromId(null), AiProvider.openai);
      expect(AiProvider.fromId(''), AiProvider.openai);
      expect(AiProvider.fromId('anthropic'), AiProvider.openai);
    });

    test('fromId round-trips every provider', () {
      for (final p in AiProvider.values) {
        expect(AiProvider.fromId(p.id), p);
      }
    });
  });
}
