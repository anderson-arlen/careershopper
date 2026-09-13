# Interview ladders, intelligence, and practice

Status: proposed design, not implemented. Based on the working tree inspected
on September 13, 2026, whose database schema is currently version 17.

## Product workflow

Each job gains an **Interviews** tab containing an editable interview ladder,
company and interview intelligence, a question bank organized by stage, mock
interview sessions, and performance history. These records exist independently
of listing availability, review disposition, application status, and outcome.
They remain available after rejection, withdrawal, a closed listing, or a hire.

1. The user marks a job Interviewing. CareerShopper creates its interview
   workspace if absent and records that intelligence preparation is needed.
2. With automatic preparation enabled for a configured ACP harness, the desktop
   dispatches a job-scoped research and question-preparation task to that local
   harness. Without that configuration, the tab shows preparation pending and
   identifies the missing ACP setup.
3. The agent researches the employer and process, submits a source-backed intel
   revision, proposes stages, and prepares stage-specific questions. Missing
   information remains visibly unknown. A useful partial packet can be saved.
4. The user edits the ladder and confirms or corrects actual interview details.
   Research can prepopulate an untouched ladder; subsequent refreshes present
   proposed changes without replacing user edits.
5. The user selects a stage, difficulty, personality, and practice length. The
   app creates a practice ID and supplies a short prompt to use in their chosen
   harness. An external agent can perform the same setup through MCP.
6. The user starts voice in that harness. The agent reads practice context,
   asks a question, follows up, and saves the exchange and evidence-based
   feedback before continuing.
7. At completion, CareerShopper calculates a score from the recorded question
   assessments and stores the agent's debrief. The tab graphs comparable
   sessions and identifies recurring areas to practice.

Automatic preparation is an explicit, persistent user preference describing
the trigger and selected harness. Enabling it authorizes future interview
transitions; it does not require another confirmation on every job. Merely
installing the feature does not enable outbound AI work. An explicit request
to prepare a particular job also authorizes that preparation.

## Configurable ladder

Stages have stable IDs and an editable order. Users can add, rename, reorder,
duplicate, or archive them, including multiple technical rounds and panels.
There is no required screen-to-CTO sequence. Archived stages remain readable
from historical practice sessions.

Each stage stores:

- Name, optional role category, purpose, and competencies assessed.
- Format: phone, video, in person, panel, live coding, take-home, or custom.
- Expected duration, optional scheduled time and timezone, and preparation notes.
- State: planned, scheduled, completed, skipped, or cancelled.
- Interviewer assignments with a role, optional public person record, and
  separate evidence for whether their participation is confirmed or predicted.
- Source references and whether the stage came from a posting, another source,
  a model proposal, or the user.

Stage completion never implies an application offer, rejection, or hire.
Returning a job to Interviewing preserves its existing ladder and practice
history. It must not silently replace either with a new default sequence.

## Intel packet and research rules

The packet contains a company overview, relevant products and customers,
business and technical context, likely team, public professional roster,
reported interview process, question and exercise reports, communication
practice notes, gaps, and a bibliography. Store structured sections so the UI
and MCP can return only the portions needed for a selected stage.

Research order:

1. Read the full saved posting and identify the exact employer and role.
2. Inspect the employer's official product, about, careers, engineering, and
   team pages. Prefer direct process descriptions for this role or team.
3. Identify public professional profiles, relevant talks, and team publications
   where they help establish role responsibilities or likely interviewers.
4. Read accessible interview reports, including Glassdoor when available,
   retaining report date, role, location, seniority, and source context.
5. Reconcile conflicts and label gaps before making predictions.

Every research assertion carries source IDs, a retrieval timestamp, a source
date where known, and an evidence type: directly reported, inferred, or unknown.
User-confirmed interview arrangements are distinguished from public reports.
Research confidence is separate from the applicant's existing job-fit score.
Old, anonymous, or different-role reports cannot establish this job's process.
Record uncertainty explicitly instead of assigning false numerical precision.

The roster describes public work responsibilities and their relevance to the
job. A CTO appearing on an executive page does not establish that they conduct
interviews. Predicted assignments include their reasoning and remain predictions
until supported by a specific source or confirmed by the user. An exact team
may be unknowable before the first interview; offer questions to ask the recruiter.

For listening preparation, retain public recording links and timestamps plus
observable speech characteristics when the agent actually has audio access, or
user-supplied observations. Do not guess accents from names, photos, ethnicity,
or nationality. A text transcript does not establish an accent. Optional accent
practice preferences are user choices and are separate from claims about real
interviewers. Do not promise that the harness can reproduce a selected accent.

Do not collect unrelated personal information. Never send resume content or
applicant details in web searches. Treat pages and model prose as untrusted.
Stop at login barriers, CAPTCHA, explicit denial, or rate limits; record the
unavailable source and continue with independently accessible sources. Do not
retry a blocked provider through a different route. Store concise sourced
summaries and permitted excerpts rather than copies of interview-review sites.

## Question bank and application context

Aim for comprehensive coverage, with visible gaps, rather than claiming every
possible question has been predicted. Organize by stage and competency, and
distinguish reported questions, generated likely questions, and user additions.

A question records its prompt, stage, topic, difficulty, why it is relevant,
source references, optional application-material block references, assessment
criteria, and suggested follow-up lines. User edits and archived questions
survive regenerated banks. Exercises include expected format, time budget,
deliverables, and evaluation criteria when known; generated exercises are
clearly labeled as practice exercises.

Coverage includes role fundamentals, company/product understanding, motivation,
behavioral evidence, technical depth, design tradeoffs, project walkthroughs,
leadership and collaboration where relevant, and questions for the interviewer.
Screening, hiring-manager, peer, and executive stages get different emphases.
An executive stage is not assumed to be present merely because the company has
an executive roster.

Practice must use the documents the employer actually received when available.
Existing MaterialSets are immutable, but the current read tool returns the
latest saved pair and does not establish that it was submitted. Add an explicit
job-level material-set selection with an attribution of user-confirmed submitted
or selected-for-practice. Do not retroactively label the newest draft submitted.
If the user submitted different documents, allow their text to be attached as
an attributed application-context record. Those documents are historical context,
not automatically confirmed career evidence.

Pin the selected material set/context and relevant confirmed Resume revisions
when a question bank or practice starts. Preserve document-block references so
follow-ups can point to the exact claim. A question may quote what a submitted
document says without endorsing it as a confirmed fact. Generated model answers
and affirmative applicant claims must reference confirmed saved Resume evidence.
Contradictions and unsupported claims become review items. Never turn a spoken
practice answer into confirmed career history automatically.

Application answers are currently intentionally ephemeral. Do not change
application_answer_generate into a history-saving operation. Users can explicitly
attach previously submitted answers to interview context when they want follow-up
practice on those answers.

## Mock interview behavior

Difficulty and personality are independent. Difficulty controls depth, ambiguity,
time pressure, and the amount of prompting; personality controls conversational
style. Defaults are supportive, neutral, probing, and adversarial, with editable
descriptions. Role-specific focus comes from the selected stage and evidence.
This simulates professional interview behavior, not a claim to reproduce a real
person's temperament or voice.

An adversarial interviewer can challenge assumptions, interrupt, request concrete
evidence, reject vague answers, and present difficult counterexamples. Personal
abuse does not contribute to the assessment. The user can pause, stop, or ask
for coaching at any time. Record coaching assistance so coached and unassisted
attempts are distinguishable in history. Default feedback timing is after the
interview; an optional coaching mode gives it after each line of questioning.

The agent's workflow is:

1. Read the selected practice context, session settings, and scoring rubric.
2. Establish the stage and available time; ask one question at a time.
3. Ask follow-ups until it has enough evidence to assess that line, the time
   budget is reached, or the user asks to move on. Avoid an endless interrogation.
4. Persist the actual speaker-attributed turns, feedback, scores, and evidence
   references for that line using a stable exchange ID. Do not speak tool
   payloads or scores aloud during interview simulation unless requested.
5. Fetch another question or ask a relevant spontaneous follow-up. Record new
   prompts even when they were not in the generated bank.
6. Finish with a debrief describing strengths, priorities for improvement, and
   concrete next exercises. Mark an interrupted session paused or abandoned;
   never fabricate completion.

Checkpoint after each completed line, not just at the end. Pausing mid-question
can save a partial exchange without grading it. A resumed session reads existing
exchange IDs and continues without duplicating previously saved work.

Only record transcript text exposed by the harness. Label verbatim transcript,
partial transcript, or agent summary explicitly. Never reconstruct missing turns
and call them a transcript. Raw audio is not stored by CareerShopper in this
design. If only text is available, delivery dimensions such as pace, pronunciation,
and vocal confidence are unassessed. This requires an early integration test:
voice functionality alone does not prove complete transcripts reach MCP tools.

## Assessment and performance history

Use a versioned rubric with anchored 0–4 scores: 0 no usable answer, 1 substantial
gaps, 2 partial evidence, 3 meets expectations, 4 strong evidence with depth.
Assess relevance, correctness or judgment, specificity and evidence, structure
and clarity, and role-appropriate depth. Each stage has fixed weights saved in
its practice snapshot. Criteria irrelevant to a question are marked unassessed,
not scored zero. Audio-dependent criteria require actual audio evidence.

Question feedback includes strengths, improvements, cited transcript turns,
assessment confidence, and a next practice action. Low confidence is displayed
separately and does not secretly multiply the score. Avoid interpreting these
practice scores as hiring probabilities or validated psychometric measures.

CareerShopper computes each assessed dimension's mean across graded questions,
then takes the weighted mean of assessed dimensions and multiplies by 25 for a
0–100 session score. Report dimension coverage and graded-question count beside
the result. An unassessed session has no score. Partial sessions show partial
results and are excluded from completed-session trends by default. Do not accept
an unrelated final number from the model as the official overall score.

Graph score and dimension trends by date with filters for job, stage category,
difficulty, personality, coaching mode, rubric version, and completed/partial
state. Mark assessment model/harness changes when known. Do not combine different
rubrics, difficulties, or stage types into a single improvement claim by default.
Show sample counts, missing criteria, and recurring weaknesses. Use existing
Flutter drawing facilities unless a dependency is demonstrably necessary.

## Storage and shared application services

Use Drift/SQLite and existing UUIDv7/revision conventions. Add the next schema
migration after the current working tree's version, including upgrade tests;
do not assume version 18 is still free when implementation begins.

Proposed records:

| Record | Responsibility |
| --- | --- |
| Interview workspace | One per job; current intel/question-bank revisions, ladder revision, selected application context, preparation state |
| Interview stage | Stable ordered identity, editable fields, assignments, source provenance, archived state |
| Interview intel revision | Immutable typed packet with sources, professional roster, reported process, predictions, gaps, and observation dates |
| Interview question-bank revision | Immutable generated questions and coverage tied to intel and application-context revisions |
| Interview question override | User edits/additions/archive state keyed to stable question IDs, kept across regeneration |
| Interview application context | Explicit material-set reference or user-provided submitted text with provenance and revision |
| Interview practice | Job/stage, pinned context and settings, versioned rubric, state, timestamps, final feedback, computed score |
| Interview practice exchange | Stable client exchange ID, ordered turns, partial/final state, assessment and evidence, revision |

Keep complex packet and rubric payloads in validated versioned JSON. Use relational
columns for ownership, ordering, revision checks, status, and filtering. Do not
introduce a general research database, vector store, second service, or new voice
backend. Reuse AiWorkOrders/AiWorkItems for desktop research execution and recovery.

A shared InterviewRepository owns local reads, mutations, scope checks, revision
checks, and score calculation. Small pure Dart domain types own payload validation
and rubric calculation. Flutter and MCP call the same repository. Extend existing
AiHarnessRepository dispatch for the new interview-preparation work kind rather
than placing ACP launch logic in storage or adding another orchestration framework.

The status transaction creates the interview workspace and preparation-needed
marker once for the actual transition. The desktop claims authorized pending
preparation through existing work-order machinery. MCP status updates return
the same preparation state; the desktop dispatches that pending work through ACP
under the user's saved automatic-preparation authorization. The configured local
harness performs the research and submits structured results through its scoped
MCP connection. Reuse work-order idempotency and expiry handling to prevent
duplicate preparation for a workspace/revision. MCP does not expose a separate
research-worker claim flow or a general agent-launch endpoint.

Repeated status writes are no-ops. Re-entry into Interviewing does not regenerate
an existing packet automatically. Explicit refresh creates a new revision and
never destroys the previous successful packet. If the desktop is closed, pending
work remains visible and resumes when the desktop and configured harness are
available. Missing
harness configuration or source access results in actionable local state.

## Discoverable MCP contract and UI parity

Names below are proposed. All writes validate nested shapes, lengths, enum values,
finite score ranges, ownership, and expected revisions. Apply existing tool
annotations and explicit-user-authorization rules. A requested practice session
authorizes its routine transcript and feedback checkpoints without asking the
user to approve every question again; unrelated mutations remain outside scope.

| Tool | Main contract |
| --- | --- |
| interview_get | job_id; ladder, preparation status, intel summary, selected application context, available revisions |
| interview_stages_save | job_id, expected_ladder_revision, ordered stages, confirmed; atomic validated update preserving archived history |
| interview_context_save | job_id, expected_revision, material_set_id or submitted text, attribution, confirmed |
| interview_intel_submit | job_id, expected_revision, typed packet and stage proposals; validate citations and ownership against the active ACP work order |
| interview_intel_get | job_id and optional revision_id; full packet or requested sections |
| interview_questions_get | job_id, optional stage_id/revision_id, cursor, limit, filters; bounded page plus coverage |
| interview_questions_submit | job_id, expected_revision, typed questions and coverage; generated bank scoped to the active ACP work order |
| interview_question_save | job_id, question_id, expected_revision, edit/archive fields, confirmed; preserve user overrides |
| interview_practice_start | job_id, stage_id, settings, confirmed, client_request_id; return idempotent practice_id |
| interview_practice_context_get | practice_id; pinned stage, intel, materials, evidence, rubric, settings, prior progress |
| interview_practice_exchange_save | practice_id, exchange_id, expected_revision, turns, assessment; repeat-safe checkpoint |
| interview_practice_state_set | practice_id, expected_revision, paused/resumed/abandoned/completed, debrief; server computes score on completion |
| interview_practices_list | job_id optional, filters, cursor, limit; history summaries |
| interview_practice_get | practice_id, exchange cursor; settings, summary, paginated transcript and feedback |
| interview_statistics_get | filters; chart series, dimension coverage, sample counts, rubric/group metadata |

Same-ID same-payload retries return the original result; same-ID changed payloads
require an expected revision. A completed session is immutable; corrections are
explicit revisions that retain the original assessment. A stage, material, work order,
or exchange from another job is rejected. Closed/expired work scopes cannot write.
Interview work orders cannot edit applicant facts, application outcomes, unrelated
jobs, harness settings, or invoke application_answer_generate. The existing
read-only essay writer also receives no new interview write permissions.

The UI exposes the same records and edits, preparation results, practice history,
transcripts, feedback, and filters. External-harness prompt copying is presentation
only; its underlying practice/context is discoverable via MCP. Update
docs/mcp-ui-parity.md alongside implementation, not as a claim that proposed tools
already exist. Harness installation/configuration and voice start remain controls
of their respective applications.

## Harness and subscription boundary

Research and question preparation start in CareerShopper, which dispatches them
through ACP to the configured local harness. ACP is the connection protocol; the
harness supplies the agent, reasoning, and research tools. The agent saves its
intel and question bank through the job-scoped MCP connection supplied by
CareerShopper.

Mock interviews start in the user's chosen voice harness, such as a Codex task
in the ChatGPT desktop app. That session uses the installed local CareerShopper
MCP plugin to read the prepared context and save practice transcripts, feedback,
and assessments. CareerShopper stores these structured records locally. These
are separate sessions unless a harness explicitly supports shared session
continuation; do not assume an ACP research session automatically opens as a
desktop voice chat. Both phases may use the same locally configured harness,
but their entry points and responsibilities differ.

Official OpenAI documentation inspected September 13, 2026 states that the ChatGPT
desktop app supports voice in Codex tasks, with rollout/account restrictions, and
that ChatGPT sign-in provides subscription access. API-key sign-in is usage-based.
Voice and underlying Codex work have usage limits. This design needs no new
OpenAI API integration or CareerShopper audio billing, but does not promise
unlimited usage or equal capabilities in every harness.

- [ChatGPT Voice](https://learn.chatgpt.com/docs/features/voice)
- [Authentication](https://learn.chatgpt.com/docs/auth)

The current AGENTS.md says local data leaves the app only when a user explicitly
invokes a configured harness through ACP. The requested external MCP practice
workflow also authorizes disclosure to the user-selected harness. During
implementation, clarify that sentence to include explicitly user-invoked MCP
workflows while retaining local storage and prohibiting unrelated disclosure.
This is a narrow clarification of this requested workflow, not permission for
background uploads or a remote database.

Extend the bundled CareerShopper skill with interview research and practice
references. It must explain source uncertainty, context pinning, role/difficulty
behavior, checkpoint cadence, transcript fidelity, rubric anchors, stopping rules,
and resumption. Keep schemas as the machine contract. Do not delegate routine
interview conduct to a second agent or expose a general prompt/generation tool.

## Implementation sequence and acceptance checks

1. **Verify the actual voice path.** In a user-started Codex voice task with the
   plugin, prove context reads, question/follow-up conversation, faithful exposed
   transcript, a structured checkpoint, and resume behavior. Do not claim complete
   voice integration based only on documentation or a text-mode unit test.
2. **Ladder and intel.** Add domain contracts, migration, shared storage, UI tab,
   MCP schemas and behavior tests. Add the authorized status trigger and scoped
   ACP preparation. Verify duplicate transitions, duplicate dispatch prevention, refresh
   conflicts, missing setup, blocked sources, interrupted research, and preserving
   edited stages and prior successful packets.
3. **Question preparation.** Add application-context selection, immutable bank
   revisions, coverage, user edits, generated/reported labels, and evidence checks.
   Verify foreign-job material references, outdated career facts, unsupported
   claims, missing application documents, and regeneration after user edits.
4. **Practice.** Add session setup/context, exchange checkpoints, resumption,
   personality/difficulty controls, and skill workflow. Verify retries, concurrent
   edits, partial transcripts, missing audio, cross-job references, unauthorized
   tools, paused/abandoned sessions, and immutable completed results.
5. **Assessment/history.** Add deterministic calculation, session feedback and
   graphs with equivalent MCP series. Test weighting, missing criteria, no graded
   answers, filtering, stable chart ordering, rubric changes, and incomplete
   sessions. Widget checks cover empty, partial, ready, and failure states.

Run targeted storage/protocol/widget tests, Dart analysis, and the existing
plugin build checks. Perform a desktop visual check and a real subscription-based
voice smoke test before calling the entire workflow complete. Preserve all
pre-existing working-tree changes while implementing these steps.
