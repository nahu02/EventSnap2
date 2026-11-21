import 'package:event_snap_2/services/ai/ai_cancellation_token.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiCancellationToken', () {
    test('starts not cancelled', () {
      final token = AiCancellationToken();
      expect(token.isCancelled, isFalse);
      expect(token.throwIfCancelled, returnsNormally);
    });

    test('cancel completes whenCancelled and is idempotent', () async {
      final token = AiCancellationToken();
      var completed = false;
      token.whenCancelled.then((_) => completed = true);
      token.cancel();
      token.cancel();
      await token.whenCancelled;
      expect(token.isCancelled, isTrue);
      expect(completed, isTrue);
    });

    test('throwIfCancelled throws AiException(cancelled)', () {
      final token = AiCancellationToken()..cancel();
      expect(
        token.throwIfCancelled,
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.cancelled,
          ),
        ),
      );
    });
  });
}
