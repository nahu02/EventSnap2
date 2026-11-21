import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiException', () {
    test('every kind has a friendly, provider-agnostic message', () {
      for (final kind in AiErrorKind.values) {
        final message = AiException(kind, 'detail').userMessage;
        expect(message, isNotEmpty, reason: kind.name);
        expect(message, isNot(contains('OpenAI')), reason: kind.name);
        expect(message, isNot(contains('Opper')), reason: kind.name);
        expect(message, isNot(contains('detail')), reason: kind.name);
      }
    });

    test('carries technical details', () {
      final cause = Exception('boom');
      final e = AiException(
        AiErrorKind.server,
        'HTTP 502 from upstream',
        statusCode: 502,
        cause: cause,
      );
      expect(e.kind, AiErrorKind.server);
      expect(e.message, 'HTTP 502 from upstream');
      expect(e.statusCode, 502);
      expect(e.cause, cause);
      expect(e.toString(), contains('server'));
      expect(e.toString(), contains('502'));
      expect(e, isA<Exception>());
    });

    test('const constructible', () {
      const e = AiException(AiErrorKind.cancelled, 'x');
      expect(e.userMessage, AiException.userMessageFor(AiErrorKind.cancelled));
    });
  });
}
