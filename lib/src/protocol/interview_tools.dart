import '../domain/interview.dart';
import '../storage/interview_repository.dart';

Map<String, Object?> _tool(
  String name,
  String description,
  Map<String, Object?> properties, {
  bool write = false,
  bool confirmation = false,
  List<String>? required,
}) => {
  'name': name,
  'description': description,
  'inputSchema': interviewObject(
    {
      ...properties,
      if (confirmation) 'confirmed': {'type': 'boolean'},
    },
    [...(required ?? properties.keys.toList()), if (confirmation) 'confirmed'],
  ),
  'annotations': {
    'readOnlyHint': !write,
    'destructiveHint': false,
    'idempotentHint':
        !write ||
        {
          'interview_practice_start',
          'interview_practice_exchange_save',
          'interview_practice_state_set',
        }.contains(name),
    'openWorldHint': name == 'interview_preparation_submit',
  },
};
final _job = {'job_id': interviewId};
final _edit = {
  ..._job,
  'expected_revision': interviewNumber(0, 2147483647, integer: true),
};
final _practice = {'practice_id': interviewId};
final interviewToolDefinitions = <Map<String, Object?>>[
  _tool(
    'interview_get',
    'Read the job interview ladder, research, questions, selected application context (including saved submitted questions/answers in payload.application_answers), revision history, cached company-logo availability/source, and read-only automatic preparation settings. current_stage is the earliest upcoming or ongoing scheduled stage, falling back to the first unfinished stage in ladder order. next_scheduled_stage exposes the next appointment. Scheduled stages automatically become completed after scheduled_at plus duration_minutes, including after reopening; this records elapsed schedule time, not attendance or a hiring outcome. questions.stage_targets reports available versus target primary questions for each active stage.',
    _job,
  ),
  _tool(
    'interview_revision_get',
    'Read an immutable intel, question-bank, or application-context revision belonging to this job.',
    {..._job, 'revision_id': interviewId},
  ),
  _tool(
    'interview_stages_save',
    'Save the complete ordered ladder with stable stage IDs. Removed stages are archived; archived history survives. Explicit user edits only. Set scheduled_at to an ISO date/time with UTC or numeric offset, duration_minutes to its expected length, and status=scheduled to schedule a stage. Times are saved in UTC and displayed in computer local time; timezone is descriptive metadata. Empty scheduled_at removes the time. Use planned, completed, skipped, or cancelled for manual status changes; only scheduled stages auto-complete after their expected end.',
    {..._edit, 'stages': interviewLadderSchema},
    write: true,
    confirmation: true,
  ),
  _tool(
    'interview_materials_list',
    'Read saved resume/cover-letter pairs for explicit selection as interview context. A draft is not automatically a submitted application.',
    _job,
  ),
  _tool(
    'interview_context_save',
    'Select the actual application material set or attach user-provided submitted text. Exactly one of material_set_id and submitted_text. This does not confirm new career facts.',
    {
      ..._edit,
      'material_set_id': interviewId,
      'submitted_text': interviewText(150000, 1),
      'attribution': interviewEnum([
        'user_confirmed_submitted',
        'selected_for_practice',
      ]),
    },
    required: ['job_id', 'expected_revision', 'attribution'],
    write: true,
    confirmation: true,
  ),
  _tool(
    'interview_preparation_submit',
    'Atomically save sourced interview intel and a stage-specific question bank. May populate an untouched empty ladder, never replaces user edits. Uses the active interview-preparation scope or explicit user confirmation. Research predictions must not claim user confirmation. No profile changes. intel requires sources, assertions, roster, and gaps; stage_proposals is optional when keeping the existing ladder. question_bank requires questions and coverage_gaps. Inspect the nested input schema before constructing the payload. $interviewQuestionPreparationInstructions',
    {
      ..._edit,
      'intel': interviewIntelSchema,
      'employer_logo_url': {
        ...interviewText(3000, 1),
        'description':
            'Optional actual company logo discovered on the employer website or listing. Public HTTPS PNG/JPEG/WebP URL, not an ATS/platform logo or guessed URL. Cached locally; failures return logo_warning without losing research. Omit if already cached or blocked; never retry an explicitly blocked URL.',
      },
      'question_bank': interviewQuestionsSchema,
      'confirmed': {'type': 'boolean'},
    },
    required: ['job_id', 'expected_revision', 'intel', 'question_bank'],
    write: true,
  ),
  _tool(
    'interview_questions_get',
    'Read question-bank coverage and questions, including user overrides and archived questions. Optionally filter by stage and paginate. stage_targets exposes the larger multi-session bank target. Optional depends_on lists prerequisite question IDs within the same stage.',
    {
      ..._job,
      'stage_id': interviewId,
      'offset': interviewNumber(0, 1000000, integer: true),
      'limit': interviewNumber(1, 1000, integer: true),
    },
    required: ['job_id'],
  ),
  _tool(
    'interview_question_save',
    'Save a user question edit/addition/archive using a stable ID. Overrides survive regenerated question banks. Optional depends_on must reference active questions in the same stage; missing prerequisites and cycles are rejected.',
    {..._edit, 'question': interviewQuestionSchema},
    write: true,
    confirmation: true,
  ),
  _tool(
    'interview_practice_start',
    'Start a user-requested practice. Omit stage_id to use the current stage (earliest upcoming/ongoing scheduled stage, otherwise first unfinished stage in ladder order); practice never advances the real interview ladder. Omit settings.difficulty for automatic progression: level 2 initially, +1 per two completed practices for this job/stage, capped at 5. Set it only for a user-requested fixed level. Paused/abandoned attempts do not advance; retries/resumes retain the pinned level. Pins stage, research, selected application documents, confirmed resume evidence, a randomized dependency-respecting question order, exposure counts, settings, and rubric. New runs prefer difficulty-appropriate questions, randomizing among equally suitable least-practiced eligible questions; resumes keep their order. Use a time-appropriate subset and keep prerequisite questions before dependents. client_request_id makes retries safe. Authorizes routine checkpoints and state changes for this practice.',
    {
      ..._job,
      'stage_id': interviewId,
      'client_request_id': interviewId,
      'settings': interviewPracticeSettingsSchema,
    },
    required: ['job_id', 'client_request_id', 'settings'],
    write: true,
    confirmation: true,
  ),
  _tool(
    'interview_practice_context_get',
    'Read the pinned context, difficulty_progression guidance, rubric, prior exchanges, and current revision before conducting or resuming a mock interview. Voice is provided by the user-selected harness; store only text actually exposed to you. Ask one question or follow-up, then wait for an answer. Tool results and incidental sounds do not close the pending question. Save silently between questions, before asking the next; defer spoken evaluation unless coaching is enabled.',
    _practice,
  ),
  _tool(
    'interview_practice_exchange_save',
    'Silently checkpoint one question and its follow-ups with speaker-attributed turns and feedback. Save completed questions before asking the next question, never mid-question. A successful save needs no spoken announcement and does not answer any pending question. New exchange expected_revision is -1. Same ID/payload retries are safe. Mark transcript as verbatim, partial, or summary. Unassessed dimensions are omitted; grade only completed lines with cited answer evidence. No audio-dependent grading.',
    {
      ..._practice,
      'exchange_id': interviewId,
      'expected_revision': interviewNumber(-1, 2147483647, integer: true),
      'exchange': interviewExchangeSchema,
    },
    write: true,
  ),
  _tool(
    'interview_practice_state_set',
    'Pause, resume (active), abandon, or complete a requested practice. Completion requires a debrief and complete exchanges. CareerShopper computes the official score from assessments. Completed and abandoned practices are immutable.',
    {
      ..._practice,
      'expected_revision': interviewNumber(0, 2147483647, integer: true),
      'status': interviewEnum(['active', 'paused', 'abandoned', 'completed']),
      'debrief': interviewText(16000),
    },
    write: true,
  ),
  _tool(
    'interview_practices_list',
    'Read paginated practice history and computed score/coverage. Filter by job, stage, or state.',
    {
      ..._job,
      'stage_id': interviewId,
      'status': interviewEnum(['active', 'paused', 'abandoned', 'completed']),
      'offset': interviewNumber(0, 1000000, integer: true),
      'limit': interviewNumber(1, 200, integer: true),
    },
    required: [],
  ),
  _tool(
    'interview_statistics_get',
    'Read completed-practice chart series. Separate groups by job, stage, rubric weights, difficulty, personality, coaching, and known harness/model; missing assessments are not zero. Scores are practice feedback, not hiring probabilities.',
    {..._job, 'stage_id': interviewId},
    required: [],
  ),
];

class InterviewTools {
  InterviewTools(this.repository);
  final InterviewRepository repository;
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args, {
    String? workOrderId,
  }) async {
    final spec = interviewToolDefinitions.singleWhere((t) => t['name'] == name);
    validateInterview(args, interviewMap(spec['inputSchema']));
    final write = interviewMap(spec['annotations'])['readOnlyHint'] != true;
    if (workOrderId != null) {
      if (!{
        'interview_get',
        'interview_revision_get',
        'interview_questions_get',
        'interview_preparation_submit',
        'interview_materials_list',
      }.contains(name)) {
        throw StateError('This tool is outside interview research scope.');
      }
      await repository.checkScope(
        args['job_id']! as String,
        workOrderId,
        write: false,
      );
    } else if (write &&
        !{
          'interview_practice_exchange_save',
          'interview_practice_state_set',
        }.contains(name) &&
        args['confirmed'] != true) {
      throw const FormatException('confirmed must reflect the user request.');
    }
    String str(String key) => args[key]! as String;
    int getInt(String key, [int value = 0]) => (args[key] as int?) ?? value;
    return switch (name) {
      'interview_get' => repository.get(str('job_id')),
      'interview_revision_get' => {
        'revision': await repository.revision(
          str('job_id'),
          str('revision_id'),
        ),
      },
      'interview_stages_save' => repository.saveStages(
        str('job_id'),
        getInt('expected_revision'),
        interviewMaps(args['stages']),
      ),
      'interview_materials_list' => {
        'materials': await repository.materials(str('job_id')),
      },
      'interview_context_save' => repository.saveContext(
        str('job_id'),
        getInt('expected_revision'),
        materialSetId: args['material_set_id'] as String?,
        submittedText: args['submitted_text'] as String?,
        attribution: str('attribution'),
      ),
      'interview_preparation_submit' => repository.submitPreparation(
        str('job_id'),
        getInt('expected_revision'),
        interviewMap(args['intel']),
        interviewMap(args['question_bank']),
        workOrderId: workOrderId,
        employerLogoUrl: args['employer_logo_url'] as String?,
      ),
      'interview_questions_get' => repository.questions(
        str('job_id'),
        stageId: args['stage_id'] as String?,
        offset: getInt('offset'),
        limit: getInt('limit', 100),
      ),
      'interview_question_save' => repository.saveQuestion(
        str('job_id'),
        getInt('expected_revision'),
        interviewMap(args['question']),
      ),
      'interview_practice_start' => repository.startPractice(
        str('job_id'),
        args['stage_id'] as String?,
        str('client_request_id'),
        interviewMap(args['settings']),
      ),
      'interview_practice_context_get' => repository.practice(
        str('practice_id'),
      ),
      'interview_practice_exchange_save' => repository.saveExchange(
        str('practice_id'),
        str('exchange_id'),
        getInt('expected_revision'),
        interviewMap(args['exchange']),
      ),
      'interview_practice_state_set' => repository.setPracticeState(
        str('practice_id'),
        getInt('expected_revision'),
        str('status'),
        str('debrief'),
      ),
      'interview_practices_list' => repository.practices(
        jobId: args['job_id'] as String?,
        stageId: args['stage_id'] as String?,
        status: args['status'] as String?,
        offset: getInt('offset'),
        limit: getInt('limit', 100),
      ),
      'interview_statistics_get' => repository.statistics(
        jobId: args['job_id'] as String?,
        stageId: args['stage_id'] as String?,
      ),
      _ => throw StateError('Unknown interview tool.'),
    };
  }
}
