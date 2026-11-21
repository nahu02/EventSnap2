import 'package:event_snap_2/models/ai_provider.dart';
import 'package:event_snap_2/models/event_model.dart';
import 'package:event_snap_2/models/extraction.dart';
import 'package:event_snap_2/models/shared_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InputImage', () {
    test('defaults to JPEG and round-trips through JSON', () {
      const image = InputImage(path: '/tmp/a.jpg');
      expect(image.mimeType, 'image/jpeg');
      expect(InputImage.fromJson(image.toJson()), image);
      expect(
        InputImage.fromJson({'path': '/tmp/b.png', 'mimeType': 'image/png'}),
        const InputImage(path: '/tmp/b.png', mimeType: 'image/png'),
      );
    });
  });

  group('ExtractionInput', () {
    test('empty by default', () {
      const input = ExtractionInput();
      expect(input.hasText, isFalse);
      expect(input.hasImages, isFalse);
      expect(input.isEmpty, isTrue);
    });

    test('whitespace-only text does not count', () {
      expect(const ExtractionInput(text: '  \n ').hasText, isFalse);
      expect(const ExtractionInput(text: '  \n ').isEmpty, isTrue);
    });

    test('text and/or images make it non-empty', () {
      expect(const ExtractionInput(text: 'Lunch at 12').isEmpty, isFalse);
      const withImage = ExtractionInput(images: [InputImage(path: '/x.jpg')]);
      expect(withImage.hasImages, isTrue);
      expect(withImage.hasText, isFalse);
      expect(withImage.isEmpty, isFalse);
    });

    test('value equality', () {
      expect(
        const ExtractionInput(
          text: 'a',
          images: [InputImage(path: '/x')],
        ),
        const ExtractionInput(
          text: 'a',
          images: [InputImage(path: '/x')],
        ),
      );
      expect(
        const ExtractionInput(text: 'a'),
        isNot(const ExtractionInput(text: 'b')),
      );
    });
  });

  group('ExtractionResult', () {
    final event = EventModel(
      title: 'Lunch',
      startDateTime: DateTime(2025, 5, 25, 12),
      endDateTime: DateTime(2025, 5, 25, 13),
    );

    test('defaults', () {
      final result = ExtractionResult(
        events: [event],
        input: const ExtractionInput(text: 'Lunch at 12'),
        provider: AiProvider.opper,
        model: 'openai/gpt-5-mini',
      );
      expect(result.usedStructuredOutput, isFalse);
      expect(result.warnings, isEmpty);
      expect(result.rawResponse, isNull);
    });

    test('may contain no events', () {
      const result = ExtractionResult(
        events: [],
        input: ExtractionInput(text: 'hello'),
        provider: AiProvider.openai,
        model: 'gpt-5-mini',
      );
      expect(result.events, isEmpty);
    });

    test('value equality', () {
      ExtractionResult make(String model) => ExtractionResult(
        events: [event],
        input: const ExtractionInput(text: 'Lunch at 12'),
        provider: AiProvider.openai,
        model: model,
        usedStructuredOutput: true,
        warnings: const ['note'],
        rawResponse: '{}',
      );
      expect(make('gpt-5-mini'), make('gpt-5-mini'));
      expect(make('gpt-5-mini').hashCode, make('gpt-5-mini').hashCode);
      expect(make('gpt-5-mini'), isNot(make('gpt-5')));
    });
  });

  group('SharedContent', () {
    test('isEmpty', () {
      expect(const SharedContent().isEmpty, isTrue);
      expect(const SharedContent(text: '   ').isEmpty, isTrue);
      expect(const SharedContent(text: 'Party on Friday').isEmpty, isFalse);
      expect(
        const SharedContent(images: [InputImage(path: '/a.jpg')]).isEmpty,
        isFalse,
      );
    });

    test('value equality', () {
      expect(
        const SharedContent(
          text: 'a',
          images: [InputImage(path: '/a.jpg')],
        ),
        const SharedContent(
          text: 'a',
          images: [InputImage(path: '/a.jpg')],
        ),
      );
      expect(
        const SharedContent(text: 'a'),
        isNot(
          const SharedContent(
            text: 'a',
            images: [InputImage(path: '/a.jpg')],
          ),
        ),
      );
    });
  });
}
