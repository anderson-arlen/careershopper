import 'dart:convert';
import 'dart:math';

Map<String, Object?> interviewObject(
  Map<String, Object?> properties, [
  List<String>? required,
]) => {
  'type': 'object',
  'properties': properties,
  'required': required ?? properties.keys.toList(),
  'additionalProperties': false,
};
Map<String, Object?> interviewText([int max = 12000, int min = 0]) => {
  'type': 'string',
  'minLength': min,
  'maxLength': max,
};
Map<String, Object?> interviewEnum(List<String> values) => {
  'type': 'string',
  'enum': values,
};
Map<String, Object?> interviewList(
  Map<String, Object?> item, [
  int max = 200,
]) => {'type': 'array', 'items': item, 'maxItems': max};
Map<String, Object?> interviewNumber(
  num min,
  num max, {
  bool integer = false,
}) => {'type': integer ? 'integer' : 'number', 'minimum': min, 'maximum': max};
final interviewId = interviewText(120, 1);
final interviewStrings = interviewList(interviewText(2000), 100);
const interviewDimensions = [
  'relevance',
  'correctness',
  'evidence',
  'clarity',
  'depth',
];
final interviewWeights = interviewObject({
  for (final dimension in interviewDimensions)
    dimension: interviewNumber(0, 10),
});
final interviewEvidence = interviewEnum([
  'reported',
  'inferred',
  'unknown',
  'user_confirmed',
]);
final interviewStageSchema = interviewObject({
  'id': interviewId,
  'name': interviewText(200, 1),
  'category': interviewEnum([
    'screen',
    'manager',
    'technical',
    'executive',
    'panel',
    'other',
  ]),
  'purpose': interviewText(),
  'competencies': interviewStrings,
  'format': interviewText(200),
  'duration_minutes': interviewNumber(1, 480, integer: true),
  'scheduled_at': interviewText(80),
  'timezone': interviewText(100),
  'status': interviewEnum([
    'planned',
    'scheduled',
    'completed',
    'skipped',
    'cancelled',
  ]),
  'notes': interviewText(),
  'archived': {'type': 'boolean'},
  'interviewers': interviewList(
    interviewObject({
      'name': interviewText(200),
      'role': interviewText(200),
      'evidence': interviewEvidence,
      'reason': interviewText(2000),
      'source_ids': interviewList(interviewId, 30),
    }),
    30,
  ),
  'weights': interviewWeights,
});
final interviewLadderSchema = interviewList(interviewStageSchema, 60);
final interviewIntelSchema = interviewObject(
  {
    'sources': interviewList(
      interviewObject({
        'id': interviewId,
        'title': interviewText(500, 1),
        'url': interviewText(3000, 1),
        'retrieved_at': interviewText(80, 1),
        'published_at': interviewText(80),
        'context': interviewText(2000),
      }),
      150,
    ),
    'assertions': interviewList(
      interviewObject({
        'id': interviewId,
        'section': interviewEnum([
          'company',
          'team',
          'process',
          'questions',
          'exercises',
          'listening',
        ]),
        'text': interviewText(8000, 1),
        'evidence': interviewEvidence,
        'source_ids': interviewList(interviewId, 30),
      }),
      300,
    ),
    'roster': interviewList(
      interviewObject({
        'id': interviewId,
        'name': interviewText(200, 1),
        'role': interviewText(300, 1),
        'relevance': interviewText(3000, 1),
        'evidence': interviewEvidence,
        'source_ids': interviewList(interviewId, 30),
      }),
      100,
    ),
    'gaps': interviewStrings,
    'stage_proposals': {
      ...interviewLadderSchema,
      'description':
          'Optional new stage proposals. Omit or use [] when keeping the existing ladder; questions must use its stage IDs.',
    },
  },
  ['sources', 'assertions', 'roster', 'gaps'],
);
final interviewQuestionSchema = interviewObject(
  {
    'id': interviewId,
    'stage_id': interviewId,
    'prompt': {
      ...interviewText(8000, 1),
      'description':
          'The actual interviewer utterance, ready to ask. Include referenced code, data, alternatives, symptoms, and necessary scenario details here, not only in grading notes. Ask a specific concept or bounded decision. Do not submit topic labels, instructions to invent a question, or unspecified project assignments. Deliberate ambiguity is allowed when clarification answers are prepared in follow_ups.',
    },
    'topic': interviewText(300, 1),
    'kind': interviewEnum(['reported', 'generated', 'user']),
    'difficulty': interviewNumber(1, 5, integer: true),
    'rationale': interviewText(4000),
    'criteria': {
      ...interviewStrings,
      'description':
          'Question-specific expected concepts, acceptable alternatives, and concrete errors to watch for. For code or query questions include the defensible result and reasoning. Avoid generic grading phrases repeated across topics.',
    },
    'follow_ups': {
      ...interviewStrings,
      'description':
          'Ready-to-ask probes for this question. For intentionally withheld facts, also specify what the interviewer reveals when asked; do not leave the scenario for the practice agent to invent.',
    },
    'source_ids': interviewList(interviewId, 30),
    'application_reference': interviewText(4000),
    'archived': {'type': 'boolean'},
    'depends_on': interviewList(interviewId, 100),
  },
  [
    'id',
    'stage_id',
    'prompt',
    'topic',
    'kind',
    'difficulty',
    'rationale',
    'criteria',
    'follow_ups',
    'source_ids',
    'application_reference',
    'archived',
  ],
);

final interviewQuestionsSchema = interviewObject({
  'questions': interviewList(interviewQuestionSchema, 1000),
  'coverage_gaps': interviewStrings,
});
final interviewPracticeSettingsSchema = interviewObject(
  {
    'difficulty': {
      ...interviewNumber(1, 5, integer: true),
      'description':
          'Optional explicit override. Omit for automatic progression: start at 2/5 and advance one level per two completed practices for this job/stage, capped at 5. Resumes keep their saved level.',
    },
    'personality': interviewText(100, 1),
    'personality_instructions': interviewText(3000),
    'minutes': interviewNumber(5, 180, integer: true),
    'coaching': {'type': 'boolean'},
    'harness': interviewText(200),
    'model': interviewText(200),
  },
  [
    'personality',
    'personality_instructions',
    'minutes',
    'coaching',
    'harness',
    'model',
  ],
);
final interviewExchangeSchema = interviewObject({
  'question_id': interviewText(120),
  'complete': {'type': 'boolean'},
  'transcript_kind': interviewEnum(['verbatim', 'partial', 'summary']),
  'turns': interviewList(
    interviewObject({
      'id': interviewId,
      'speaker': interviewEnum(['interviewer', 'applicant', 'coach']),
      'text': interviewText(16000, 1),
    }),
    200,
  ),
  'coached': {'type': 'boolean'},
  'assessments': interviewList(
    interviewObject({
      'dimension': interviewEnum(interviewDimensions),
      'score': interviewNumber(0, 4, integer: true),
      'reason': interviewText(4000, 1),
      'turn_ids': interviewList(interviewId, 100),
    }),
    5,
  ),
  'strengths': interviewStrings,
  'improvements': interviewStrings,
  'next_action': interviewText(4000),
  'confidence': interviewEnum(['low', 'medium', 'high']),
});

void validateInterview(
  Object? value,
  Map<String, Object?> schema, [
  String path = 'input',
]) {
  final type = schema['type'];
  final valid = switch (type) {
    'object' => value is Map<String, Object?>,
    'array' => value is List,
    'string' => value is String,
    'boolean' => value is bool,
    'integer' => value is int,
    'number' => value is num && value.isFinite,
    _ => false,
  };
  if (!valid) {
    throw FormatException('$path must be $type.');
  }
  if (schema['enum'] case final List allowed) {
    if (!allowed.contains(value)) {
      throw FormatException('$path has an unsupported value.');
    }
  }
  if (value is String &&
      (value.trim().length < ((schema['minLength'] as int?) ?? 0) ||
          value.length > ((schema['maxLength'] as int?) ?? 100000))) {
    throw FormatException('$path has an invalid length.');
  }
  if (value is num &&
      (!value.isFinite ||
          value < (schema['minimum'] as num) ||
          value > (schema['maximum'] as num))) {
    throw FormatException('$path is out of range.');
  }
  if (value is Map) {
    final properties = schema['properties']! as Map;
    for (final key in schema['required']! as List) {
      if (!value.containsKey(key)) {
        throw FormatException('$path.$key is required.');
      }
    }
    for (final key in value.keys) {
      if (!properties.containsKey(key)) {
        throw FormatException('Unknown field $path.$key.');
      }
      validateInterview(
        value[key],
        (properties[key] as Map).cast<String, Object?>(),
        '$path.$key',
      );
    }
  }
  if (value is List) {
    if (value.length > (schema['maxItems']! as int)) {
      throw FormatException('$path has too many entries.');
    }
    for (final item in value) {
      validateInterview(
        item,
        (schema['items'] as Map).cast<String, Object?>(),
        '$path[]',
      );
    }
  }
}

Map<String, Object?> interviewMap(Object? value) =>
    (value as Map).cast<String, Object?>();
List<Map<String, Object?>> interviewMaps(Object? value) =>
    (value as List).map(interviewMap).toList();
String interviewCanonical(Object? value) {
  Object? sorted(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sorted(item[key])};
    }
    if (item is List) {
      return item.map(sorted).toList();
    }
    return item;
  }

  return jsonEncode(sorted(value));
}

void uniqueInterviewIds(
  List<Map<String, Object?>> records, [
  String field = 'id',
]) {
  final values = records.map((r) => r[field]).toSet();
  if (values.length != records.length) {
    throw FormatException('Duplicate $field.');
  }
}

void validateInterviewLadder(List<Map<String, Object?>> stages) {
  validateInterview(stages, interviewLadderSchema);
  uniqueInterviewIds(stages);
  for (final stage in stages) {
    if (interviewMap(
      stage['weights'],
    ).values.cast<num>().every((v) => v == 0)) {
      throw const FormatException(
        'At least one rubric weight must be positive.',
      );
    }
    final scheduled = stage['scheduled_at']! as String;
    if (scheduled.isNotEmpty && DateTime.tryParse(scheduled) == null) {
      throw const FormatException('scheduled_at must be an ISO date/time.');
    }
  }
}

Map<String, Object?> newInterviewStage(String id, String name) => {
  'id': id,
  'name': name,
  'category': 'other',
  'purpose': '',
  'competencies': <String>[],
  'format': 'video',
  'duration_minutes': 45,
  'scheduled_at': '',
  'timezone': '',
  'status': 'planned',
  'notes': '',
  'archived': false,
  'interviewers': <Object?>[],
  'weights': {for (final d in interviewDimensions) d: 1},
};

Map<String, Object?>? currentInterviewStage(
  List<Map<String, Object?>> stages,
) => stages
    .where(
      (s) =>
          s['archived'] != true &&
          ['planned', 'scheduled'].contains(s['status']),
    )
    .firstOrNull;

const interviewPersonalities = {
  'supportive':
      'Warm and patient. Offer space to think and ask clear follow-ups.',
  'neutral':
      'Professional and even-handed. Ask direct questions without coaching.',
  'probing':
      'Demand concrete evidence, explore tradeoffs, and challenge vague claims.',
  'adversarial':
      'Apply professional pressure, challenge assumptions, and present counterexamples. Never use personal abuse.',
};

Map<String, Object?> scoreInterview(
  List<Map<String, Object?>> exchanges,
  Map<String, Object?> weights,
) {
  final totals = <String, double>{};
  final counts = <String, int>{};
  var graded = 0;
  var coached = false;
  for (final exchange in exchanges) {
    coached |= exchange['coached'] == true;
    if (exchange['complete'] != true) continue;
    final assessments = interviewMaps(exchange['assessments']);
    if (assessments.isNotEmpty) graded++;
    for (final assessment in assessments) {
      final dimension = assessment['dimension']! as String;
      totals[dimension] =
          (totals[dimension] ?? 0) + (assessment['score']! as num).toDouble();
      counts[dimension] = (counts[dimension] ?? 0) + 1;
    }
  }
  final means = {for (final d in totals.keys) d: totals[d]! / counts[d]!};
  double weighted = 0, totalWeight = 0;
  for (final entry in means.entries) {
    final weight = (weights[entry.key]! as num).toDouble();
    weighted += entry.value * weight;
    totalWeight += weight;
  }
  return {
    'score': totalWeight == 0 ? null : weighted / totalWeight * 25,
    'dimension_means': means,
    'dimension_counts': counts,
    'graded_questions': graded,
    'unassessed_dimensions': interviewDimensions
        .where((d) => !means.containsKey(d))
        .toList(),
    'coached': coached,
  };
}

const interviewQuestionPreparationInstructions =
    r'''Build a substantial practice bank from the FULL saved job description, not a handful of sample questions. First inventory every stated skill, technology, responsibility and experience requirement. Distribute questions across difficulty levels 1–5 for each active stage, with usable easy fundamentals and genuinely harder variants; do not label every question difficulty 3. For each material technical requirement, create distinct fundamentals, code/query-reading or debugging, and applied design/tradeoff questions where relevant. Put the specific posting requirement being tested in each question's rationale. Include explicit expected concepts and common mistakes in criteria, plus probing follow-ups. Cover requirements even when the applicant's resume does not mention them. Do not substitute behavioral stories or generic system design for concrete technical knowledge. Use questions.stage_targets from interview_get: each active stage needs at least 40 distinct primary questions or five times its estimated session capacity, whichever is larger. This is a bank for many practice sessions, not a script sized to one interview. Follow-ups and superficial paraphrases do not count as distinct primary questions. A 60-minute stage targets 60 primary questions, plus follow-ups. Read the sourced interview-question-patterns.md reference; cover its relevant families with multiple variants, not just vague questions. Research additional company/role-specific formats from accessible sources. Record specific coverage and count shortfalls for partial banks. Scale to actual coverage, avoid duplicates, and list specific uncovered requirements in coverage_gaps.
Write each primary question individually as an actual interviewer utterance. Do not generate the bank by looping over topic names and substituting them into stock fundamentals/reading/debug/design/tradeoff sentences. Code may serialize independently authored questions, but must not manufacture their substance. A question must name a specific concept, comparison, symptom or bounded decision; include any referenced snippet, query, input data, alternatives and necessary constraints in prompt. 'Read a small example' without the example and 'choose between two approaches' without the approaches are unfinished templates. Do not turn nontechnical requirements such as leadership into technical placeholders. Design questions are valid when appropriate to the stage, but need a concrete scenario and a scoped question that can be discussed in minutes; take-home project briefs belong in intel exercises, not as replacements for oral questions. Supply question-specific expected answers/concepts and concrete failure modes in criteria. On refresh, inspect and rewrite existing template-like questions; a previous coverage claim or a filled quota is not evidence of quality. Audit each question by asking whether an interviewer could use it as written and grade its specific answer. Meet the bank target with substantive distinct questions; if unable, save a useful partial bank and report its shortfall rather than padding the count.
Use the reported interview format and user observations to allocate questions. Initial AI/automated screens can be predominantly technical; do not assume stage 1 is recruiter small talk or reserve all technical questions for later rounds. When format is unknown, include both relevant technical fundamentals and introductory questions in the first stage. For a posting requiring PostgreSQL, TypeScript and Node.js, examples of suitable specificity include NULL comparison semantics, any versus unknown with narrowing, and event-loop execution ordering with concrete code. For code-order questions specify the runtime context (such as CommonJS versus ESM and top-level versus an I/O callback); criteria must account for contextual differences. These are examples, not a universal stack checklist.
Read application_context from interview_get, which uses the latest saved application documents unless the user selected an override. Follow up directly on passages the interviewer has read: identify the resume/cover-letter passage in application_reference and naturally reference it in the spoken question (for example, 'Your resume mentions migrating a service. What tradeoffs did you make?'). Do not disguise known resume stories as generic behavioral prompts. Mix these follow-ups with independent technical questions driven by the listing. Never invent applicant claims or model answers.
Include a realistic mix of deliberate ambiguity and interview pressure: a broad 'Tell me about yourself', underspecified technical problems, skeptical follow-ups, interruptions, conflicting priorities, and changed constraints. Record the intended ambiguity/pressure in rationale and criteria, and prepare concrete answers to likely clarification requests in follow_ups. A vague opening can be intentional; an absent referenced code sample or undefined alternatives are not a pressure tactic. For the introductory question, relevant professional experience and fit are the target, not a life history; allow the applicant to clarify the scope. Reward useful clarification and explicit assumptions. Do not mark a reasonable clarifying question as failure or withhold essential facts indefinitely. Vary pressure by difficulty/personality while staying professional. Do not claim every vague question is a deliberate trick or that a particular employer uses these tactics without evidence.
Distinguish reported questions from generated practice predictions. Include company understanding, project discussions, leadership where relevant, and questions for the interviewer alongside technical coverage. Generated questions are not guaranteed interview questions. Before submitting, audit the bank against the posting inventory and every active stage; fill substantive gaps rather than stopping at a token sample. Use optional depends_on with stable same-stage question IDs for genuine prerequisite relationships. Do not chain independent questions merely to impose a script; follow-ups stay attached to their parent. Cover independently selectable variants. Preserve user edits and cite sources for reported questions.''';

int interviewQuestionTarget(Map<String, Object?> stage) {
  final capacity = ((stage['duration_minutes'] as int? ?? 30) / 5).ceil();
  return capacity * 5 < 40 ? 40 : capacity * 5;
}

String interviewQuestionFingerprint(String prompt) =>
    prompt.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

void validateInterviewQuestionDependencies(
  List<Map<String, Object?>> questions,
) {
  final active = {
    for (final q in questions.where((q) => q['archived'] != true)) q['id']: q,
  };
  final visited = <Object?>{}, visiting = <Object?>{};
  void visit(Object? id) {
    if (visited.contains(id)) return;
    if (!visiting.add(id)) {
      throw const FormatException('Question prerequisites contain a cycle.');
    }
    final q = active[id]!;
    final dependencies = q['depends_on'] as List? ?? const [];
    if (dependencies.toSet().length != dependencies.length) {
      throw const FormatException('Question prerequisites must be unique.');
    }
    for (final dependency in dependencies) {
      final parent = active[dependency];
      if (parent == null || parent['stage_id'] != q['stage_id']) {
        throw const FormatException(
          'Prerequisites must be active questions in the same stage.',
        );
      }
      visit(dependency);
    }
    visiting.remove(id);
    visited.add(id);
  }

  for (final id in active.keys) {
    visit(id);
  }
}

List<Map<String, Object?>> randomizedInterviewQuestions(
  List<Map<String, Object?>> questions,
  Map<String, int> exposureCounts, {
  required Random random,
  int? difficulty,
}) {
  validateInterviewQuestionDependencies(questions);
  final remaining = questions.where((q) => q['archived'] != true).toList();
  final ordered = <Map<String, Object?>>[], used = <Object?>{};
  while (remaining.isNotEmpty) {
    final eligible = remaining
        .where(
          (q) => (q['depends_on'] as List? ?? const []).every(used.contains),
        )
        .toList();
    int count(Map<String, Object?> q) =>
        exposureCounts[interviewQuestionFingerprint(q['prompt']! as String)] ??
        0;
    int distance(Map<String, Object?> q) {
      if (difficulty == null) return 0;
      final level = q['difficulty']! as int;
      return level > difficulty ? 5 + level - difficulty : difficulty - level;
    }

    final closest = eligible.map(distance).reduce(min);
    final appropriate = eligible.where((q) => distance(q) == closest).toList();
    final leastUsed = appropriate.map(count).reduce(min);
    final pool = appropriate.where((q) => count(q) == leastUsed).toList();
    final chosen = pool[random.nextInt(pool.length)];
    ordered.add(chosen);
    used.add(chosen['id']);
    remaining.remove(chosen);
  }
  return ordered;
}
