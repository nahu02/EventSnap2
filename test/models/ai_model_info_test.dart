import 'dart:convert';

import 'package:event_snap_2/models/ai_model_info.dart';
import 'package:event_snap_2/models/ai_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiModelInfo', () {
    const full = AiModelInfo(
      id: 'anthropic/claude-sonnet-5-5',
      displayName: 'Claude Sonnet 5.5',
      provider: AiProvider.opper,
      supportsStructuredOutput: true,
      supportsVision: false,
      description: 'Balanced model',
      vendor: 'Anthropic',
      speed: 'fast',
      quality: 'best',
      contextWindow: 200000,
      recommended: true,
    );

    test('displayName falls back to id', () {
      const info = AiModelInfo(id: 'gpt-5', provider: AiProvider.openai);
      expect(info.displayName, 'gpt-5');
      expect(info.supportsStructuredOutput, isNull);
      expect(info.supportsVision, isNull);
      expect(info.recommended, isFalse);
    });

    test('toJson/fromJson round-trip (through a JSON string)', () {
      final decoded = jsonDecode(jsonEncode(full.toJson()));
      final restored = AiModelInfo.fromJson(decoded as Map<String, dynamic>);
      expect(restored, equals(full));
      expect(restored.hashCode, full.hashCode);
    });

    test('fromJson keeps unknown capabilities as null', () {
      final info = AiModelInfo.fromJson({'id': 'x', 'provider': 'openai'});
      expect(info.supportsStructuredOutput, isNull);
      expect(info.supportsVision, isNull);
      expect(info.displayName, 'x');
      expect(info.recommended, isFalse);
      expect(info.provider, AiProvider.openai);
    });

    test('fromJson falls back to id for blank display names', () {
      final info = AiModelInfo.fromJson({
        'id': 'gpt-5',
        'displayName': '  ',
        'provider': 'openai',
      });
      expect(info.displayName, 'gpt-5');
    });

    test('equality covers all fields', () {
      const a = AiModelInfo(id: 'm', provider: AiProvider.openai);
      const b = AiModelInfo(id: 'm', provider: AiProvider.opper);
      const c = AiModelInfo(
        id: 'm',
        provider: AiProvider.openai,
        supportsVision: true,
      );
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
      expect(
        a,
        equals(const AiModelInfo(id: 'm', provider: AiProvider.openai)),
      );
    });
  });
}
