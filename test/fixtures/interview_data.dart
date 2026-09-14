import 'package:careershopper/src/domain/interview.dart';

Map<String, Object?> interviewStage() => {
  ...newInterviewStage('technical', 'Technical interview'),
  'category': 'technical',
};
Map<String, Object?> interviewIntel() => {
  'sources': [
    {
      'id': 'company',
      'title': 'Example careers',
      'url': 'https://example.test/careers',
      'retrieved_at': '2026-09-13T12:00:00Z',
      'published_at': '',
      'context': 'Official process for this role',
    },
  ],
  'assertions': [
    {
      'id': 'process',
      'section': 'process',
      'text': 'A technical discussion is reported.',
      'evidence': 'reported',
      'source_ids': ['company'],
    },
  ],
  'roster': <Object?>[],
  'gaps': ['Interviewer identity is unknown.'],
  'stage_proposals': [interviewStage()],
};
Map<String, Object?> interviewQuestion() => {
  'id': 'tradeoffs',
  'stage_id': 'technical',
  'prompt': 'Describe a technical tradeoff you made.',
  'topic': 'Judgment',
  'kind': 'generated',
  'difficulty': 3,
  'rationale': 'Explore reasoning.',
  'criteria': ['Explains alternatives and consequences.'],
  'follow_ups': ['What would change your choice?'],
  'source_ids': <String>[],
  'application_reference': '',
  'archived': false,
};
Map<String, Object?> interviewBank() => {
  'questions': [interviewQuestion()],
  'coverage_gaps': ['Add role-specific exercises.'],
};
Map<String, Object?> practiceSettings({
  int difficulty = 3,
  bool coaching = false,
}) => {
  'difficulty': difficulty,
  'personality': 'neutral',
  'personality_instructions': 'Professional and direct.',
  'minutes': 30,
  'coaching': coaching,
  'harness': 'Test',
  'model': 'test-model',
};
Map<String, Object?> practiceExchange({int score = 3, bool complete = true}) =>
    {
      'question_id': 'tradeoffs',
      'complete': complete,
      'transcript_kind': 'verbatim',
      'turns': [
        {'id': 'q', 'speaker': 'interviewer', 'text': 'Describe a tradeoff.'},
        {
          'id': 'a',
          'speaker': 'applicant',
          'text': 'I compared two alternatives and measured their costs.',
        },
      ],
      'coached': false,
      'assessments': complete
          ? [
              {
                'dimension': 'evidence',
                'score': score,
                'reason': 'The answer provides an example.',
                'turn_ids': ['a'],
              },
            ]
          : <Object?>[],
      'strengths': ['Concrete example.'],
      'improvements': ['Explain the measurements.'],
      'next_action': 'Practice quantifying the outcome.',
      'confidence': 'medium',
    };
