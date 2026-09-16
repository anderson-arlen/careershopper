# Interview research and practice

Use `interview_get` to read the job workspace. Interview stages, research, and
practice history are independent of application stage and outcome. Never mark
an application successful or unsuccessful based on a practice score.

## Research and question preparation

Read [interview-question-patterns.md](interview-question-patterns.md) for the
sourced coverage catalog, bank sizing, and varied-session selection rules. Apply
it during research and practice; the catalog supplements the full job posting.

An ACP interview-preparation order authorizes research and a packet submission
for its one job. Verify the work-order ID with `health_get`. Use `job_get`,
`interview_get`, and `resume_content_get`; the latest saved application documents (or a user-selected override) are
included in the interview workspace. A standalone user can also request research
and authorize `interview_preparation_submit` with `confirmed: true`. There is no
MCP tool to launch an ACP researcher or configure automatic preparation.

Read the full saved posting first. Prefer official employer product, careers,
engineering and team pages. Add accessible professional profiles, talks, and
interview reports where relevant. Include interview-review sites such as
Glassdoor when accessible; never bypass login, CAPTCHA, rate limits or access
denial. Stop requests to a blocked source, record the gap, and continue with
independently accessible sources or user-supplied content. Do not send applicant
names, resume content or other personal facts in web queries.

The packet schema requires sources with retrieval dates, assertions grouped by
section, a professional roster, and gaps. Stage proposals are optional when retaining an existing ladder. Distinguish reported
facts, inference and unknowns. Retain report dates and role/location context.
An executive's public role does not prove they conduct interviews. Explain
predicted interviewer assignments; do not mark research as user-confirmed.
Use brief summaries instead of copying long interview reviews.

For listening preparation, record public audio/video links and timestamps or
user observations. Describe observable speech only if you can actually access
the audio. Never infer accents from names, pictures, ethnicity, nationality, or
text transcripts. Do not claim to reproduce a real person's voice or temperament.

Build the question bank from an inventory of **every material requirement in the
full posting**. For each technical requirement, cover fundamentals, concrete
code/query interpretation or debugging, and applied judgment where relevant.
Name the requirement in each rationale. Include expected concepts, common mistakes
and follow-ups. Follow the ready-to-ask question guidance and examples in
interview-question-patterns.md: include referenced code/data/options, bound design
questions to the interview stage, and author each question individually instead
of filling topic templates. A detailed engineering listing needs dozens of distinct questions,
not a six-question sample. Resume overlap does not limit coverage: test required
skills absent from the resume too. Audit coverage against the inventory and every
active stage before submitting; list specific omissions as coverage gaps.

Use known stage format and the user's actual interview observations. An initial
AI screen may be mostly technical. Do not equate screen with nontechnical recruiter
conversation. When uncertain, include technical fundamentals as well as introductions.
For a relevant stack, questions might test SQL NULL semantics, type safety/narrowing,
or execution order in concrete asynchronous code. Specify runtime assumptions so
questions have defensible answers; avoid ambiguous code-order grading.

Use application_context from interview_get automatically. Its payload.application_answers
contains saved submitted application questions and exact answers. Use them for
follow-ups on what the applicant wrote, preserving their attribution as submitted
text rather than treating them as newly confirmed career facts. Draft answers are
excluded, and an active practice retains the context saved when it began.
For document follow-ups,
set application_reference to the actual passage and **refer to it in the question**:
'Your resume mentions migrating a service. What tradeoffs did you make?'
Do not turn a known story into a coy generic behavioral prompt. Also include
independent technical questions, company understanding, project walkthroughs and
leadership where appropriate. Do not invent applicant answers or career facts.
Distinguish reported questions from generated predictions.

Include deliberately broad questions and realistic pressure: 'Tell me about
yourself', underspecified problems, skeptical challenges, interruptions, shifting
constraints and conflicting priorities. Record intended ambiguity, clarification
paths and scoring expectations in rationale/criteria/follow_ups. These test how
the applicant clarifies, states assumptions and adapts. The introductory question
targets relevant professional experience and fit; clarify that if asked. Do not
claim these tactics are known employer behavior without evidence.

Before constructing a submission, inspect the full nested input schema from tool
discovery. Do not guess field names or discover required fields by submitting an
incomplete packet. `intel` requires `sources`, `assertions`, `roster`, and `gaps`;
`stage_proposals` is optional and defaults to an empty array. `question_bank`
requires `questions` and `coverage_gaps`. All are arrays, including when empty.
Each question needs `id`, `stage_id`, `prompt`, `topic`, `kind`, `difficulty`,
`rationale`, `criteria`, `follow_ups`, `source_ids`, `application_reference`, and
`archived`; `depends_on` is optional. Use the schema for the required fields of
sources, assertions, roster entries, and any proposed stages as well.
Use existing ladder stage IDs whenever a ladder exists. If the ladder is empty,
provide full stage proposals before referring to them in the question bank.

`interview_get.company` reports cached-logo availability and its source URL.
If missing, find the actual employer logo on its website or listing and include
`employer_logo_url` in the submission: a discovered public HTTPS PNG/JPEG/WebP
image URL. Never use a recruiting platform logo, guessed URL, or logo tracking
service. Omit it when unavailable or blocked. CareerShopper caches the image
locally for the report header and job list; opening the report makes no remote
image requests. A `logo_warning` means the research was saved; do not resubmit
the packet or retry a blocked URL just to obtain an image.

Submit intel and question_bank together through `interview_preparation_submit`
with the current workspace revision. Use stable IDs. An empty untouched ladder
can be populated from proposals. If the user has edited the ladder, questions
must reference its existing stage IDs; proposals remain proposals. User question
overrides survive regenerated banks. Refresh after a revision conflict and
preserve the user's edits. A useful partial packet with explicit gaps is valid.

## Application context and ladder

`interview_stages_save` saves the ordered ladder; removed stages are archived.
Only change the ladder when the user requests it. Use `interview_materials_list`
to inspect saved document pairs and `interview_context_save` to select one or
attach user-provided submitted documents/answers. Use user_confirmed_submitted
only when the user confirms that those exact materials were sent; otherwise use
selected_for_practice. By default the workspace uses the latest saved application
documents for this job; no manual selection is required. Use the selection tools
only for an explicit override or additional submitted answers. Historical documents
do not automatically confirm career facts.

`interview_question_save` saves user edits/additions/archive state. Generated
question banks retain the intel and application-context IDs used to prepare them.
Saved revisions remain readable with `interview_revision_get`.

## Conduct a mock interview

A request such as "Let's practice my interview for X" is enough authorization to
create and conduct a practice. Resolve X to the job already in context, or use
`jobs_search` with `view: interviewing` and the employer/role text. If needed,
search retained jobs with `view: all`. Ask a short clarification only when more
than one plausible job remains or the intended job cannot be identified. Do not
make the user configure a session in the UI or answer a setup questionnaire.

If the user supplies a practice ID or explicitly asks to resume an unfinished
practice, read `interview_practice_context_get` and resume it. Otherwise read
`interview_get`, then call `interview_practice_start` with `confirmed: true` and a
stable client_request_id. Omit `stage_id` unless the user asks for a particular
stage: CareerShopper selects `current_stage`, prioritizing the earliest upcoming
or ongoing scheduled stage, then the first unfinished stage in ladder order.
Scheduled stages automatically complete after their start time plus duration;
this reflects the schedule, not proof of attendance. Completed, skipped and cancelled stages do
not qualify. If there is no current stage, ask which stage to practice or help
record the missing ladder; do not silently choose a completed stage. Completing
mock practice never advances the real interview ladder.

Omit `settings.difficulty` unless the user explicitly chooses a fixed level.
Automatic progression starts at 2/5 and increases one level after every two
completed practices for the same job/stage, capped at 5/5. Incomplete, paused and
abandoned sessions do not advance it. All completed practices count, including
coached and fixed-level attempts. Use neutral personality, its standard behavior,
30 minutes and coaching off unless the user requests otherwise. Harness/model
labels may be empty when unknown. State the selected stage and resolved level
briefly, then begin; do not require confirmation of these defaults.

Same-ID same-request retries return the same practice even if the current stage
or completed-practice count has since changed. The start call pins the stage,
research, application context, confirmed resume evidence, difficulty progression,
question order, settings and rubric. Resumes use the pinned level; never
recalculate it from today's history.

Read `difficulty_progression` and `settings.difficulty` from the snapshot. Open
with an easy, stage-relevant warm-up and build toward the saved level as the
applicant settles in. At levels 1–2, emphasize concrete fundamentals and clear,
single-step prompts; level 3 adds applied reasoning and routine tradeoffs; levels
4–5 add deeper mechanisms, competing constraints and stronger follow-up probes.
Let sound answers lead to more demanding follow-ups within the session level;
if the applicant struggles, clarify or ease the next probe. Harder does not mean
abusive. Do not give hints or model answers unless coaching is enabled or requested.

The saved question order favors the current difficulty and then easier questions,
randomizing among equally suitable, less-practiced choices with prerequisites
preserved. Select a time-appropriate subset and use the easier opening even when
the saved order starts near the target level. If the bank lacks suitable easy
questions (`available_at_or_below_level` is zero), use concrete fundamentals
appropriate to the stage rather than asking an unsuitable hard question. Record
new spontaneous questions with an empty question_id, without misattributing them
to a bank entry.

Use voice if the chosen harness supports it and the user enables it. CareerShopper
does not start voice or receive raw audio. Establish whether you can access the
spoken transcript. If you cannot, explain the limitation and offer text practice
or accurately labeled summaries. Never reconstruct missing speech as verbatim.

Keep the spoken conversation in interviewer voice. Ask one question or follow-up,
then yield and wait for the applicant's answer. If a bank prompt has several parts,
deliver them one at a time. Once a question is asked, keep it pending through tool
results or incidental utterances; do not replace it, append another question, or
restart the scenario before the applicant answers. A throat-clear, laugh or other
non-answer is not a completed response. If asked "Are you still there?", briefly
acknowledge and let the applicant continue the pending answer. Clarifications stay
with that question; deliberate pressure must not become accidental topic switching.

Use the applicant's words and any end-of-speech or pause signals actually exposed
by the harness to judge whether they have finished. A complete thought or an
explicit "that's my answer" is enough to continue; do not wait for a longer answer.
Do not treat every brief pause, filler word or breath as the end of the turn. If
there is a prolonged observable pause and completion is unclear, ask once,
"Would you like a moment, or shall we continue?" Then wait for that response.
This checks whose turn it is; it does not grade or close the pending answer or
introduce another interview question. Respect requested thinking time instead of
repeatedly checking. Do not require a completion phrase after every answer. When
the harness exposes only completed text turns, do not invent pause durations or
claim to monitor silence while no turn is being delivered.

When the applicant finishes an answer, respond rather than waiting silently for a
more detailed answer. If more evidence is needed, ask one specific follow-up.
Before a checkpoint, a brief neutral acknowledgment such as "Thanks" lets the
applicant know you heard them; it is not a spoken assessment or a save announcement.
Avoid repeating or polishing their answer merely to fill the gap. If they ask for
time to think, give them that space. Use deliberate silence only for an appropriate
pressure exercise, not as the normal response to each answer. Acknowledge presence
checks promptly rather than treating them as interview answers. Do not promise a
response-time limit or claim to control the harness's speech endpoint detection.

Tailor focus to the stage: a screener explores the actual reported screen format,
including technical depth for an AI/technical
screen; a technical interviewer explores depth and judgment;
a manager or executive explores the responsibilities and evidence appropriate
to that stage. Difficulty controls ambiguity, depth and pressure. Personality
controls style. Adversarial practice can challenge assumptions and weak evidence,
not insult the user. Respect pauses, stops, time limits, and requests for coaching.

Use the sourced pattern catalog, not just vague prompts. Follow the saved
randomized order as the priority for a time-appropriate subset, with prerequisites
covered first and follow-ups attached. Use varied topics and pressure patterns
across sessions; explicit user requests to revisit take precedence.
Use occasional vague prompts and pressure scenarios from the bank. Scale their
frequency and intensity with difficulty and personality, not abuse. When the
applicant asks a useful clarifying question, answer naturally in interviewer voice,
provide the needed scope, and credit the clarification in feedback. Do not reveal
the intended answer or score during non-coaching practice. Never penalize them
for an ambiguity you introduced or silently grade unstated assumptions as wrong.

Follow up until there is enough evidence, time is running out, or the user asks
to move on. Save that completed question and its follow-ups using
`interview_practice_exchange_save` during the transition, before asking the next
question. Finish the save, then ask the next question in one uninterrupted
utterance and yield. Do not start speaking a question, perform bookkeeping, then
resume or replace it. A tool result is not an applicant turn.

Saving is silent bookkeeping: do not announce that an exchange is complete, that
you are checkpointing or grading, or that a tool succeeded. Only explain a saving
problem if it needs the user's attention; never claim a failed save succeeded.
Use a stable exchange_id; a new exchange uses expected_revision -1. Each turn has
a stable ID, speaker and actual text. Use transcript_kind verbatim, partial, or
summary honestly. An unfinished answer may be checkpointed without assessments
when pausing or recovering; that does not close the pending question. Leave
question_id empty for a spontaneous question outside the pinned bank.

Grade relevance, correctness/judgment, specificity of evidence, clarity, and
role-appropriate depth using the pinned 0–4 rubric. Cite recorded turn IDs for
each assessment and explain it. Omit unassessed dimensions instead of scoring
zero. Do not grade pace, accent, pronunciation or vocal confidence from text.
Record strengths, improvements, assessment confidence and a concrete next action.
Mark coached whenever assistance was given. Feedback is normally deferred until
the end; coaching mode allows feedback after each completed question. During
non-coaching practice, use brief natural acknowledgments rather than evaluating,
summarizing, or rewriting every answer aloud. Do not read tool payloads aloud.
Applicant-specific example answers must stay grounded in the pinned confirmed
resume evidence. Practice answers never become confirmed career history.

Before retrying or resuming, read saved exchange IDs and revisions. Identical
checkpoint retries are harmless; corrections require the expected exchange
revision and retain the previous checkpoint. Pause with
`interview_practice_state_set` when interrupted. Resume with status active;
finished sessions are immutable. Abandon only when the user is done with an
unfinished practice. Do not manufacture completion to satisfy a workflow.

Finish with a concise debrief and priority exercises, then call
`interview_practice_state_set` with status completed and the latest practice
revision. All recorded lines must be complete. CareerShopper calculates the
0–100 score from dimension means and the stage's saved weights. Missing scores
remain unassessed. Never substitute a model-invented overall score. These scores
are practice feedback, not hiring probabilities. Use `interview_statistics_get`
for comparable completed-session trends; do not combine different stage,
difficulty, personality, coaching, rubric or known model groups into an
improvement claim.

## Schedule real interviews

Use `interview_get` and `interview_stages_save` for user-requested schedule or
status changes, preserving other stages and the expected revision. Supply
`scheduled_at` as an ISO timestamp with UTC or a numeric offset, the expected
`duration_minutes`, and `status: scheduled`. The desktop shows local dates/times
and sorts Interviews by the next appointment, with unscheduled jobs last.
A past scheduled end completes that stage automatically, including after reopening.
Choose planned, completed, skipped, or cancelled when the user requests a manual
status; planned stages remain open without timed completion. Clearing a schedule
uses an empty scheduled_at and planned status. Do not infer an appointment from
company research or change the application's hiring outcome.
