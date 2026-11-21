/// Sample events with AI evidence for the review screen / widget tests.
library;

import 'package:event_snap_2/models/models.dart';

import '../../helpers/fakes.dart';

const planningText =
    'Hi all! Our quarterly planning meeting is on Friday, June 6 from 2pm '
    'to 4:30pm in Room 4B at the Oslo office.\n\nPlease bring your Q3 numbers.';

/// "Quarterly planning" with evidence for every field (description: low).
EventModel planningEvent({String title = 'Quarterly planning meeting'}) {
  return EventModel(
    title: title,
    description: 'Bring your Q3 numbers.',
    location: 'Room 4B, Oslo office',
    startDateTime: DateTime(2025, 6, 6, 14),
    endDateTime: DateTime(2025, 6, 6, 16, 30),
    evidence: const {
      EventField.title: FieldEvidence(
        quote: 'quarterly planning meeting',
        reasoning: 'Named in the first sentence.',
        confidence: EvidenceConfidence.high,
      ),
      EventField.start: FieldEvidence(
        quote: 'Friday, June 6 from 2pm',
        reasoning: 'Date and start time are stated explicitly.',
        confidence: EvidenceConfidence.high,
      ),
      EventField.end: FieldEvidence(
        quote: 'to 4:30pm',
        reasoning: 'End time follows the start time.',
        confidence: EvidenceConfidence.medium,
      ),
      EventField.location: FieldEvidence(
        quote: 'ROOM 4B   at the Oslo office',
        reasoning: 'Room and office are mentioned together.',
        confidence: EvidenceConfidence.medium,
      ),
      EventField.description: FieldEvidence(
        quote: 'Please bring your Q3 numbers',
        reasoning: 'A request to attendees, used as the description.',
        confidence: EvidenceConfidence.low,
      ),
    },
  );
}

const lunchText = 'Lunch with Sam next Tuesday at noon';

/// "Lunch with Sam" whose end was inferred (null quote, low confidence).
EventModel lunchEvent() {
  return EventModel(
    title: 'Lunch with Sam',
    startDateTime: DateTime(2025, 6, 10, 12),
    endDateTime: DateTime(2025, 6, 10, 13),
    evidence: const {
      EventField.title: FieldEvidence(
        quote: 'Lunch with Sam',
        reasoning: 'Stated directly.',
        confidence: EvidenceConfidence.high,
      ),
      EventField.start: FieldEvidence(
        quote: 'next Tuesday at noon',
        reasoning: 'Relative date resolved from today.',
        confidence: EvidenceConfidence.medium,
      ),
      EventField.end: FieldEvidence(
        reasoning: 'No end time given; assumed one hour.',
        confidence: EvidenceConfidence.low,
      ),
    },
  );
}

/// An [ExtractionResult] over [planningText] with [planningEvent] (or
/// [events]).
ExtractionResult planningResult({
  List<EventModel>? events,
  String text = planningText,
  List<InputImage> images = const [],
  List<String> warnings = const [],
  String? rawResponse,
}) {
  return sampleResult(
    events: events ?? [planningEvent()],
    text: text,
    images: images,
    warnings: warnings,
    rawResponse: rawResponse,
  );
}
