import '../../models/extraction.dart';
import 'ai_cancellation_token.dart';

/// Extracts calendar events from text and/or images using an AI model.
abstract class CalendarEventInterpreter {
  /// Throws [AiException]. Never throws other exception types.
  Future<ExtractionResult> extractEvents(
    ExtractionInput input, {
    AiCancellationToken? cancellationToken,
  });
}
