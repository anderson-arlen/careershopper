# UI / MCP parity

CareerShopper data and application operations use shared validation through UI
and MCP. Agents do the work themselves; MCP must not launch another agent.

| UI capability | MCP equivalent |
| --- | --- |
| Job list/details/evaluation/provenance | `jobs_search`, `job_get` |
| Inbox to-do queue, AI failures first, then ranked by fit within each group | `jobs_search(view: "inbox")`; same repository query as the UI. Unscored jobs follow scored jobs within their group; ties use newest then job ID. All jobs retains newest-first ordering. |
| Live inbox navigation count | `jobs_search(view: "inbox").total_count` without a query; includes every actionable job before the result limit, using the same repository inbox stream. |
| Statistics Sankey, funnel and date filters | `statistics_get(period: "today" / "this_month" / "this_year" / "all_time")`; shared `JobRepository.watchStatistics`, with counts plus Sankey nodes/links |
| Stage menu (including application outcome) | `application_status_set`, `application_outcome_set`; shared `JobRepository` writes |
| Add/refresh/evaluate listing | Agent inspects listing, then `job_import_submit`, `job_evaluation_submit` |
| Approve/discard/block/status | `job_review_set`, `employer_block_set`, `application_status_set` |
| Blocked employers list and Unblock | `blocked_employers_list`, `employer_block_set(blocked: false, confirmed: true)`; shared repository reads and writes |
| Open listing | `job_open_listing` |
| Company logo | Import `employer_logo_url`; `employer_logo_get`, `employer_logo_set` |
| Resume-shaped fixed content editor: header, headings, roles/achievements, projects, patents, education | `resume_content_get`, `resume_content_save` with explicit `confirmed: true` and `expected_revision_id`; shared `ResumeContentRepository` |
| Unified profile and matching context | `profile_get` reads saved resume content and preferences; all disabled entries remain matching context. Application scopes receive enabled content only. |
| Preferences: read/edit/rename/delete | `profile_get.preference_entries`, `profile_preference_save`, `profile_preference_delete`; batch upsert retained |
| Searches: list/edit/pause/delete/run | `saved_searches_list`, `saved_search_upsert`, `saved_search_enabled_set`, `saved_search_delete`, `saved_search_run` |
| Search result explanations and persistent run history | `saved_search_runs_list`; `saved_search_run.sources` includes the same diagnostics |
| Sources: list/edit/pause/delete | `source_configs_list`, `source_config_upsert`, `source_config_enabled_set`, `source_config_delete` |
| Blocked indicators on Sources and attached searches; Clear block | `source_configs_list` health state/detail; `source_block_clear` with `source_config_id` and explicit `confirmed: true`, through the shared configuration repository |
| Document tabs/copy/status | `application_materials_get` |
| Check listing availability / clear its check block | `job_availability_check`, `job_availability_block_clear`, with explicit user confirmation; shared preflight also runs before desktop document generation |
| Draft/regenerate | Agent drafts content itself; validate then scoped `application_materials_submit`, or unscoped `application_materials_create` / `application_materials_update` |
| Edit/save/review | `application_materials_update` with expected material ID; reviewed=true only for explicit user review |
| Export DOCX/PDF without applying | `application_documents_export`; same shared-output replacement and validation, no browser launch or status/review changes |
| Apply: export/open listing and ask whether completed | `application_apply` opens without recording submission and returns `completion_confirmation_required`; after the user's answer use `application_status_set(application_status: "applied")`, or ask whether to discard and use `job_review_set(review_state: "discarded")` only if confirmed |
| Layout/prompt/reset | `document_template_get`, `document_template_update`, `document_template_reset` |
| Live search above Inbox / All jobs list | `jobs_search(query, view)`; same word scoring across title, full saved description, and employer name; queried results include `search_score` |
| Read saved AI activity/settings | `ai_conversations_list`, `ai_conversation_get`, `ai_profiles_list` |
| Job chat panel and linked activity | `ai_conversations_list(job_id)` includes directly linked discussions and prior work items, including matching batches; `ai_conversation_get` reads transcript and job/scope association; `job_context_get` reads the same discussion context without launching AI |
| Job notes: read/edit/save | `job_notes_get`, `job_notes_set` with `expected_notes` and explicit confirmation; shared `JobRepository` validation prevents concurrent overwrites |

The job-list search splits on whitespace into distinct case-insensitive words.
Each word earns one point per matching field (title, description, employer),
using literal substring matches so partial typing works. Repeated occurrences
within a field and repeated query words do not inflate scores. Jobs matching any
word appear, highest total first, with the view's existing ordering for ties.
These text scores do not modify saved AI evaluations or eligibility.

Each saved search selects exactly one source. Desktop edits and
`saved_search_upsert` share repository validation; `source_config_ids` contains
exactly one ID (omitting it on edit preserves the source). Schema v17 splits
existing searches with multiple sources, retains their query, threshold and
interval, moves each source's run history to its search, and preserves historical
job matches. Searches without a source are retained but paused.

Scheduling offers daily local time, an interval, or a numeric five-field cron
expression. MCP uses `schedule_cron` (`0 9 * * *` for daily at 09:00), or null
with `poll_interval_minutes` for intervals. Cron accepts wildcards, comma lists,
ranges and steps; Sunday is 0 or 7, and restricted day-of-month and weekday
fields use cron's OR rule. Spring daylight-saving gaps are skipped; repeated
local times run once. `saved_searches_list` returns the schedule,
`schedule_timezone: "local"`, `next_scheduled_at` in UTC, and
`last_schedule_error`, matching the search cards.

The desktop scheduler checks every 30 seconds while the app is running. Missed
occurrences are combined into one run, then the next deadline is calculated
from the current time. Pausing clears the deadline; resuming schedules a future
run. Existing interval searches receive a future deadline on first startup.
Manual runs do not reset the schedule. Provider intervals, backoff and blocks
remain enforced. Scheduled discovery uses the same repository as Run now and
queues eligible jobs through the desktop's configured job-matching AI; missing
AI setup is recorded without contacting a provider. MCP configures and inspects
these searches but does not expose an ACP-launch operation.

On Linux, closing the window hides it in the system tray when a tray host is
connected. The window and Flutter engine remain alive, so schedules and ongoing
work continue. Tray actions open/hide the window or quit the application; launching
CareerShopper again reopens the existing instance. Quit stops the process and its
scheduler. Without a tray host, closing exits normally; losing the host restores
a hidden window. Agent permission prompts also restore the window before asking
for a decision. These are presentation/lifecycle controls, not new data actions:
MCP continues to expose schedules, run history, and AI activity through the
existing read tools, without adding window-control or general ACP-launch tools.
The job-list search updates on every edit. Clear search restores the view;
no matches leaves the search box available. Inbox filtering uses the currently
displayed snapshot so typing does not refresh or reorder incoming listings.
Manual/idle refresh retains the query. The navigation Inbox count remains the
full queue count. Search is disabled while unsaved detail edits protect the
selected job. Filtering is local and does not contact providers or invoke AI.

Chat about this job opens a dedicated chat drawer. Notes are a separate section
in Job details with Add/Edit notes and their own editor. A new job discussion uses current
listing data, remote designation, evaluation, saved notes, and the selected
conversation's visible transcript (up to 60,000 recent characters, with a
truncation flag). It creates a separate ACP session using the selected context's
agent/settings; it does not rerun or change the original task. Later turns resume
the job discussion's session and include current listing data and saved notes.
All discussions remain visible in central AI Activity. Starting/sending ACP chats
is desktop-only under the harness-control exception. MCP exposes context and
transcripts read-only. Notes do not change review/application state or become
confirmed career facts. Schema v15 adds local job notes and the conversation's
optional direct job link; older work remains associated through its work items.
Chat composers send on Enter and retain Shift+Enter for multiline text entry;
this keyboard interaction uses the same desktop-only ACP send actions.

Agent configurations can be duplicated in AI > Agents, preserving their saved
model and effort settings independently. Agents by purpose selects defaults for
Job matching (search analysis and URL imports) and Application writing (resumes,
cover letters and essay answers). Unassigned purposes use the general default;
chat continues to use that default. Existing work orders retain their selected
agent and settings. Deleting a purpose's configuration restores the general
default for new work. Schema v14 adds the two purpose assignment flags, initially
false, preserving existing behavior. `ai_profiles_list` exposes both flags and
saved settings read-only. Configuration and duplication remain desktop-only
under the ACP control exception; no MCP launch or settings mutations are added.

Inbox and Jobs list rows show the original source icon in place of the company
logo: bundled LinkedIn and Indeed icons, or a generic job icon for other sources.
The tooltip and accessible label identify the source. `jobs_search`,
`job_get`, and job resources return the same `source_family`, selected from the
earliest observation with insertion order breaking ties, matching statistics.
Later AI imports do not replace the original source icon. Existing observation
history supplies this field; no database migration is required.

LinkedIn source editing includes **Maximum pages per search** (1–100, default 1).
`source_config_upsert.max_pages` saves the same setting through shared source
validation; `source_configs_list` returns its effective value. Omission on edit
preserves the setting. Values live in the existing source configuration JSON,
so older configurations retain one-page behavior without a schema migration.
Pagination counts raw returned cards for offsets, deduplicates across pages,
and stops early on exhaustion, repeated results, or errors/blocks. Three seconds
separate page requests. Reaching the configured limit does not assert that no
more matches exist.

Searches can be run manually while paused through Run search now or
`saved_search_run`. A manual run leaves the search's enabled setting unchanged
and still respects source enablement, provider backoff, and blocks. The desktop
requires a configured default ACP harness and dispatches an isolated single-job
evaluation for each eligible match, processed sequentially. `saved_search_run` returns `candidate_job_ids` selected by
the same repository rule; the calling MCP agent evaluates those jobs itself with
`job_get`, `profile_get`, and `job_evaluation_submit`. MCP does not launch ACP.
Both paths evaluate complete saved search descriptions directly, including Indeed
API descriptions, without browsing or reimporting the posting. Retrieval is only
needed for empty content, excerpts, visible truncation, or access/error placeholders.
Short or vague postings do not require retrieval just because details are absent.
When retrieval is needed for Indeed, the desktop prompt uses the saved Indeed
source URL rather than the external application URL, which remains saved for applying.
Desktop import/refresh and incomplete-search workflows use `job_posting_fetch`
first when retrieval is needed, also available to MCP callers. The shared listing service retrieves the
saved source URL with Dart HTTP and a Chrome-style User-Agent, strips script and
navigation content, and returns untrusted page text for `job_import_submit`.
The fetch itself does not change the saved description, evaluation, review, or
application state. It records retrieval diagnostics and provider blocks locally.
The tool requires `confirmed: true`, enforces job scope, and permits scoped
retrieval only for import/search work orders. Complete search descriptions still
skip retrieval. Explicit access denial, authentication, or CAPTCHA stops requests
to that host until the user clears the saved block. HTTP 429 instead persists a
host-wide cooldown using Retry-After (seconds or HTTP date), or one hour when
absent/invalid. `job_posting_fetch` returns `blocked: true` and `retry_at` during
that cooldown: end the retrieval turn rather than retrying or switching tools.
The desktop retains the search work item as queued and resumes the same search
conversation after the deadline, including after reopening. The activity shows
the retry time, also readable through `ai_conversation_get`. Other searches may
continue while it waits. Previously saved 429-only blocks expire one hour after
the recorded response; actual access denials remain blocked. Block checks
are shared with listing availability checks; a generic retrieval failure does
not itself establish a block. No JavaScript execution or browser cookies are used.
Initial and resumed import/search ACP turns and MCP descriptions distinguish
provider retrieval blocks from user employer blocks. User-supplied text, screenshots,
or documents can be imported with `job_import_submit` and evaluated with
`job_evaluation_submit` after a provider block, without additional page, company,
or logo retrieval. Source provenance and content limitations are retained; missing
details remain unknown. This does not clear the provider block or permit evaluation
of user-blocked employers.
Explicit Refresh & reanalyze and document-generation availability checks still fetch
the listing. Search evaluation does not fetch logos as a prerequisite to scoring.
Desktop import/search prompts and the MCP evaluation contract share the same
scoring instructions: fit and attainability are integers from 0 through 100;
confidence is a number from 0 through 1 inclusive (78% is submitted as `0.78`).
Both the prompt and discoverable tool descriptions state these scales before
submission. Fit and attainability assess stated requirements against
confirmed applicant evidence. Sparse posting details affect confidence and
unknowns, without a score deduction or ceiling for vagueness alone. Concrete
qualification gaps and conflicting requirements remain valid scoring evidence.
Confidence is stored separately and does not change the 60/40 combined score or
search threshold. A fully retrieved but brief posting can be evaluated; failed
or truncated retrievals are reported separately. Existing evaluations remain
unchanged until the user requests reanalysis.
Search completion opens a result report, with a per-source completed, skipped,
warning, or failed status. Run history & diagnostics reopens persistent records,
including older runs' available errors and observation counts. Schema v13 adds
nullable diagnostics to existing runs; no historical counters are invented.
New records include query parameters, request URLs and HTTP status, page counts,
new/existing observations, search filtering, blocked employers, normalization
failures and AI eligibility. Counts can overlap (e.g. an existing listing can also
be filtered). New runs save actual request method, URL, headers and body plus
response status, headers and body, exposed in UI and `saved_search_runs_list`.
Credential/cookie headers are redacted. Response bodies are captured up to 20 MiB;
truncated or interrupted bodies are explicitly marked. JSON bodies are objects;
non-JSON bodies remain text. Older runs explicitly lack body capture. Provider
content remains untrusted data. Per-record import errors include record number
and reason. Partially imported runs show Completed with skipped records; only
failed requests or wholly unimportable results show Failed. Completed pages are saved
during pagination; later failures retain partial results and candidates. Source
skips are recorded without prolonging the minimum request interval. Explicit
provider blocks stop further requests. AI dispatch errors are shown separately
from discovery results; eligibility counts do not claim AI completion.

Indeed follows the request and parsing approach of
[JobSpy](https://github.com/speedyapply/JobSpy/tree/main/jobspy/indeed), with its
GraphQL endpoint, client protocol headers, country mapping, relevance ordering,
attribute filters, 100-result pages, nextCursor and full HTML descriptions.
CareerShopper reads only the first page, capped at the first 100 results before
deduplication or filtering, and never follows its cursor. Diagnostics report
`more_results_available` when the response indicates further results. This
intentional limit is a normal completion, not a warning or error. Structured empty results are distinct from HTTP,
GraphQL, JSON or response-shape errors. TLS verification remains enabled, and
there is no proxy rotation or block retry. LinkedIn uses the guest HTML adapter
with the provider's past-24-hours filter (`f_TPR=r86400`) for both desktop and MCP
search runs. Unrecognized empty HTML is reported as uncertain rather than
confirmed zero.
The JobSpy MIT notice is bundled as `assets/JobSpy-LICENSE`.
Every returned, normalized listing is considered for AI matching; residual title,
keyword and other local search checks do not hide or disqualify provider results.
Previously search-hidden jobs can be processed and return to pending evaluation
when dispatched. Eligibility excludes current evaluations, blocked employers,
approved/discarded jobs, closed listings, progressed/ended applications, and active
AI work. Overlapping desktop batches claim jobs transactionally. Unchanged source
snippets preserve hydrated postings and evaluations. Changed postings invalidate
the evaluation. Activity records the batch and incomplete or failed work; successful
evaluations enter Inbox only when their score meets the search threshold.

General launching, installing, configuring, selecting or messaging ACP agents remains a
host/UI responsibility. The sole exception is `application_answer_generate`: a
typed essay-question operation using the existing default ACP model/settings,
shared writing style, and confirmed profile. It accepts no job ID, model override,
command, or general prompt. It returns an answer or a structured error without
automatically saving answer history. Separate local answer-save/read tools do not
invoke ACP. The restricted writer MCP exposes only health and confirmed
non-private profile reads, rejects other calls/resources, and cannot invoke
generation recursively. An inherited writer flag and a cross-process lock also
guard against calls through another CareerShopper MCP instance. This does not
sandbox arbitrary third-party ACP harness internals or their own session storage.
Presentation-only state
(tabs, scrolling, clipboard, unsaved edits) maps to saved data access, not UI
automation.

Statistics defaults to All time. Today, This month and This year select jobs by
their last state-change date. The page stays aligned to the top even in tall windows.
Two prominent cards above the funnel show Jobs found per application (found / applied)
and Applications per interview (applied / interviewed). Each card shows only its
label and value, rounded to one decimal without trailing .0, with no ratio suffix
or calculation subtitle. A zero denominator displays an em dash.
`statistics_get.conversion_ratios` exposes the same unrounded values as
`jobs_found_per_application` and `applications_per_interview` (numbers, or null
when the respective denominator is zero). Interviews count distinct jobs reaching
interviews, not interview rounds or mock sessions. The cards, funnel and Sankey
update together with the date filter; the funnel appears above the Sankey.
Sankey input nodes group jobs by their first observation source family (Manual
entry, Indeed, etc.) and merge into Jobs found. Timestamp ties use observation
insertion order; jobs without source observations use Unknown source. Later
sightings cannot inflate counts or change the discovery source. The MCP payload
records `source_attribution: first_observed_source`. Source counts use the same
date cohort. Sankey ribbon widths are proportional to job counts. Branches classify jobs at their furthest recorded stage using current outcomes:

- Before application: AI rejected for below-threshold reviews, user rejected
  for discarded jobs, blocked employers or user withdrawals, or Inbox. User decisions
  take precedence over AI rejection; hidden-by-search is not AI rejection.
- Applied: interviewing, waiting, employer rejected, or user withdrawn.
- Interviewing: offer, employer rejected, waiting, or user withdrawn.
- Offer: employer withdrawn (rejected outcome), user rejected (withdrawn outcome),
  waiting, or Accepted offer. A known hired stage is retained in history and
  counts as Accepted offer when its outcome is active.

User-withdrawn branches appear only when populated. Accepted offer and the
other required branches retain labeled zero counts without drawing zero-count ribbons. Each job
occupies exactly one current-state branch, so flows conserve the distinct job total. The chart
uses the full page width. Narrow windows can scroll the Sankey horizontally using
a visible scrollbar; tooltips and assistive labels qualify
repeated outcome names by their parent stage. `statistics_get.sankey` returns the
same nodes (id, label, count, column, remainder, terminal) and links (source, target, count).
Each column puts progression and pending states before unsuccessful terminal
outcomes. Accepted offer leads the final column, ahead of Waiting and the other
outcomes, while retaining its terminal classification. Ribbon stacking follows
that same order. MCP returns this node and link order.
`remainder` identifies branches off the main progression path. `terminal` is false
for Inbox, Pending processing, and all Waiting nodes, which use the primary color and a clock icon.
It is true only for completed outcomes, including accepted/hired. Inbox uses the same eligibility predicate as the action-only Inbox navigation
queue, restricted to pre-application jobs in the selected state-change date cohort.
Jobs excluded by search keywords are Filtered by search, not AI rejected. Jobs
awaiting evaluation or documents are Pending processing, not Inbox. Failed AI
attempts requiring action are included in Inbox through the same shared rules.
A recorded employer rejection without evidence of application has a separate
pre-application branch.

The existing funnel uses four connected, colored sections
with each stage's label and count inside. Its taper represents stage order;
section size is not proportional to counts, so zero-count stages stay visible.
The date filters use
local calendar boundaries and show those jobs' furthest
recorded progress. The funnel counts distinct jobs found, applied, interviewed and
offered, with later stages including earlier ones and hired counting as an offer.
Current application state, stage history and known application dates preserve
progress even after rejection, withdrawal or a later stage change. Unknown stage
alone does not imply an application. Found includes all retained listings,
including hidden, discarded, blocked and closed ones; repeat observations do not
increase counts. UI watches local changes; MCP reads the same aggregate without
list pagination. Each job is selected by its last state change and counted once, not once per event. No searches or AI work are launched.

New mutations require explicit user authorization and retain work-order
boundaries. Scoped agents cannot use administrative endpoints or unscoped saves
to bypass staged submission. Logo downloads are bounded public HTTPS raster
images cached locally; failures preserve existing logos and never fail imports.

Documents exposes the shared writing-style.md editor, Save, Reload, and an unsaved
Reset to default. MCP equivalents are `writing_style_get`, `writing_style_update`,
and `writing_style_reset` (reset saves immediately). Writes require the revision
returned by the read; stale edits are rejected. Both document generation and the
application writer read this same file, falling back to the bundled default when
no custom file exists. Untouched legacy generation prompts upgrade to structural
instructions; custom prompts and existing drafts are preserved. Shared style takes
precedence for prose, never factual support or action authorization.

Inbox includes unblocked jobs awaiting approval/decline and approved jobs with
saved, non-staged documents while no document generation is running. Applications
that have progressed beyond not-applied/ready-to-apply are excluded. Approval
alone, the stored ready-to-apply status, and staged drafts do not establish
readiness. Saved documents need not be marked reviewed. The derived
`ready_to_apply` field in `job_get` and `jobs_search` exposes document readiness
for approved, unsubmitted applications; employer blocking separately excludes
jobs from Inbox. Inbox sorts by overall score descending, with unscored jobs
last, then last-seen time descending and job ID ascending. Search text and limits
apply after selecting this queue. `jobs_search` defaults to `view: "all"`, retaining
the existing history view and newest-first ordering. Queue membership does not
change availability, review disposition, application status, or stored history.
Approving a job queues documents without changing the current page or opening
the documents tab. As the job leaves Inbox, selection advances to the next row
(or the preceding row if the removed job was last). A job returning with ready
documents does not steal the current selection. This is presentation-only;
MCP uses the same approval/generation workflow and inbox data described above.

Application stage and outcome are independent. Stage retains progress (not
applied, ready to apply, applied, interviewing, offer, hired); `unknown` means the
stage was not recorded. Outcome is active, expired, rejected by employer, or
withdrawn by the applicant. Setting either axis preserves the other, review disposition, and
availability. Closed outcomes are excluded from Inbox even if documents exist.
The list and detail header show both; MCP job reads expose `application_status`
and `application_outcome`. User rejection of a listing remains `discarded` review
disposition. Outcome changes are audited. Stage updates do not invent a submission
date. Both mutations require explicit user instruction and are unavailable to
scoped AI work orders. Legacy rejected/withdrawn arguments to
`application_status_set` update outcome only. Schema v12 moves legacy terminal
statuses to outcome, restores the last recorded stage from application events
(or a known application date), and uses unknown when neither exists. Original
events are preserved.

UI and MCP exports share `~/Documents/CareerShopper`, replacing only that folder's
contents and leaving the former data-directory export folder untouched.
Document reads/writes preserve the same Markdown through UI and MCP: bold and
italic runs, hard line breaks, explicit page breaks, and allowlisted frontmatter
(document_type, subtitle, footer, page_numbers). Preview, DOCX, and PDF use the
same parser; saved content and subtitle metadata retain confirmed fact references.
The section-order setting accepts `direct_match` through both surfaces.
The shared default prompt covers selective work history, coherent bullets,
accurate product audiences, and compact patent bullets with number, classification,
title, and month/year, omitting co-inventor names and attribution boilerplate. Untouched
older defaults upgrade through the shared template repository; custom prompts
remain unchanged. Default recognition ignores whitespace-only differences from
historical paragraph spacing or line endings; edits to the instructions still
prevent automatic replacement. Both export paths keep headings/metadata with following content
and preserve explicit Markdown page breaks rather than adding section breaks.
`document_template_get.cover_letter_settings` exposes the same derived letter
typography/margins shown on Documents and used by both export formats. Pipeline
letters have their own defaults without modifying resume settings; customized
values survive and explicit Markdown page-number preferences take precedence.
The shared writing default requests focused letter prose and conventional letter
structure. ACP supplies the drafting date as document context, not a career fact.
The same prompt includes a recruiter/employer-perspective review for both drafts,
omitting unnecessary adverse context without changing facts or required disclosures.
Resume headlines use the broad target occupation and explicit conventional
seniority, omitting team, product, technology and specialty qualifiers as well
as employer-specific grades. For example, "Senior Software Engineer, Infrastructure"
becomes "Senior Software Engineer". Specialization belongs in supporting content;
official work-history titles and exact role identification in cover letters are
preserved. The shared style and default generation prompt apply this rule; this
writing preference does not rename saved jobs or historical career facts.
Project headings contain only the project name and relevant confirmed technology
stack, formatted as `### **Project Name** · Technology, Technology`. The name is
bold; the spaced middle dot and stack use regular weight. Explicit bold spans in H3
headings control emphasis in preview, DOCX, and PDF; unmarked headings retain
their existing styling. Product type, purpose, audience, and capabilities belong in the summary
below the heading. The shared generation prompt specifies this structure for UI
and MCP workflows; untouched prior defaults upgrade, while custom prompts and
already generated documents remain unchanged.

Apply, Export documents, and the export-format picker live in the job header, above both detail
tabs. The document-readiness indicator links to document review. MCP already
exposes the same saved drafts, reviewed flag and generation status through
`application_materials_get`; the header uses these same states. Unsaved editor
changes are UI-local and disable Apply and Export documents until saved/reverted. Export still checks
original confirmed fact revisions, listing snapshot, latest draft, and employer approval.
Profile edits flag unapplied documents as out of date; Apply allows reuse after confirmation. Review is
optional: generated saved drafts enable Apply through both UI and MCP without
marking them reviewed or requiring a review step.

The desktop recovers expired AI work leases at startup and watches their deadlines
while open. Expired runs and unfinished/submitted work items become failed with an
Activity explanation; completed items, provisional drafts, published documents,
review decisions, and search settings are retained. This is local lifecycle
maintenance, not search polling or a model launch. MCP reads the same persisted
status and explanation through `ai_conversations_list`, `ai_conversation_get`, and
`application_materials_get`. Retry/continue remains a desktop harness action.

Listings with failed AI work that needs user input return to Inbox in the existing
fit-score order. The list shows an error badge; the detail shows the failure and
Retry AI action. This covers approved document generation and unevaluated
import/search analysis. Blocked/discarded listings and ended applications stay out.
A newer running or successful attempt suppresses older failures. `jobs_search`
and `job_get` expose the same `ai_error` text; the MCP workflow uses the existing
import/evaluation/material submission tools, without adding ACP-launch tools.

Inbox has a Refresh button that re-reads the shared local queue. The displayed
list stays stable during window input. After three minutes without mouse,
keyboard, or scrolling activity, it refreshes every three minutes while idle.
A resumed interaction prevents an in-flight automatic read from changing the
list. Modal dialogs, unsaved document edits, and document export also defer
automatic refresh. Manual refresh preserves selection when the job still exists.
User actions update their affected row immediately, advancing selection when it
leaves the queue, without admitting unrelated arrivals or reordering other rows.
MCP clients obtain the current queue with `jobs_search(view: "inbox")`; buffering,
refresh timing, and window activity are presentation state, not new MCP actions.
These reads do not run external searches, enable polling, or launch AI work.

Job header actions show Approve or Apply first only when available. Refresh/reanalyze and Block employer live in More job actions; their existing MCP equivalents and authorization rules are unchanged. Stage and job chat controls sit at the upper right.

Chat views display active work beside the composer and allow Interrupt or Steer
while a turn runs. Steering cancels the active ACP turn, waits for its completion
handlers, then resumes the saved session with the new message and current job
context. If interrupted before a session exists, a chat retains its visible
transcript when starting the replacement session. Interrupted listing workflows
keep unfinished jobs in the actionable inbox; partial document drafts remain
unpublished. ACP launch/messaging/cancellation remain UI-only under the harness
control exception. `ai_conversations_list` and `ai_conversation_get` expose the
saved `interrupted` status and transcript read-only; no MCP control tool is added.

Chats follow new messages and streamed text while the transcript is at the bottom;
scrolling up pauses following until the user returns to the bottom. Clipboard
images can be pasted into new chats, central chats, and job discussions with
Ctrl/Cmd+V or Paste image. Previews can be removed before sending, and image-only
messages are supported. Up to four images (10 MB each) are retained locally in
the existing activity payload and sent as ACP image content only when the user
sends the message. Agents without the image prompt capability return a clear
error. `ai_conversation_get.activity[].images` exposes the same retained images as
content blocks (`type`, `mimeType`, base64 `data`); ACP messaging remains UI-only.


Document generation checks the saved application/listing URL before starting or
resuming a materials writer. HTTP 404/410 and explicit human-visible closure
messages set availability to closed and active pre-application outcomes to expired.
A closed posting does not end an already submitted active application. Existing
rejection/withdrawal outcomes and the furthest application stage are retained.
Network errors, access blocks, server errors, and ambiguous pages pass preflight.
Scripts, hidden elements, and page navigation are excluded from closure matching.
The check and its reason are saved in activity/audit history. Provider blocks are
not retried; clearing a listing-check host block is explicit and sends no request.
Source-config blocks remain controlled through the existing Sources actions.
Expired outcomes leave Inbox and appear as terminal branches at their retained
stage in `statistics_get`. No schema change is needed for the existing text axis.

The desktop writer receives current confirmed non-private facts, exact revision
IDs, listing context, template instructions, and shared writing style up front.
The Markdown parser accepts adjacent individually cited bullets. Validation errors
identify the document, block, and invalid revision IDs. Validation remains
read-only and does not establish semantic support or completeness.

Before publication, a separate ACP recruiting reviewer receives only the listing
and the complete staged pair, in a fresh session and temporary workspace with no
CareerShopper MCP tools. It recommends promoting or declining human review and
explains specific contributing evidence, shortcomings, and red flags. It does
not proofread or suggest editing, additions, removals, or changes in length. The original writer
session receives that report and can revise; `application_materials_submit` can
set `request_second_review=true` for one optional second independent screen.
There are at most two screens per generation. Each review records the material
version it assessed. Recommendations never set user review, job outcome, or an
application stage. Failed/interrupted review or revision leaves prior published
documents active. This is desktop harness orchestration, not a general MCP agent
launch or messaging endpoint. Saved reports are readable in `ai_conversation_get`.

Completed, failed, and interrupted chat turns record a selectable `run_summary`
activity row with elapsed time and distinct ACP tool calls (updates and replayed
history do not count). The count includes recruiting-review activity within the
generation. `ai_conversation_get.activity[].details` exposes `elapsed_ms`,
`tool_call_count`, start/end timestamps and status; recruiting-review rows also
identify the pass and material set. These are measured runtime metrics, not model
estimates. A process crash cannot record a precise end time for that interrupted
process.


ACP authorization requests open an application-wide modal over the current view,
including requests from background work. The dialog identifies the configured
agent and job/conversation task, shows the requested tool action and its supplied
arguments/paths, and offers Allow once, Deny, and Always allow when the agent supplies an allow_always option. The agent option name is shown to explain its scope. Pending requests from concurrent
runs are queued. Cancellation removes that run's prompt, including queued prompts.
No title, URL, job ID, or CareerShopper name match grants permission. Persistent
permissions require the user to explicitly select the agent-provided option;
CareerShopper returns its exact option ID and does not create broader approval
rules. For Codex requests identifying an actual local CareerShopper MCP tool,
CareerShopper persists the explicit allow_always choice by agent command, helper
path, workspace, server and tool name. It applies across jobs and app restarts.
The allow_session choice additionally binds to the ACP session ID, so it survives
a resumed turn but never grants access to a new session. Changed arguments do not
invalidate approval of the same tool. Other tools, servers and shell commands
never inherit the grant; titles alone cannot match. Restricted reviewer/answer
permissions still apply first. Grants are stored locally in agent-permissions,
without draft arguments. Automatic reuse is recorded as Allowed by saved
permission. Unknown agent option scopes remain agent-controlled. Missing UI or invalid/ambiguous options cannot
authorize a request. Recruiting reviewers and prohibited essay-writer operations
remain denied by their narrower capability limits.

Partial permission tool updates are joined with earlier tool_call/tool_call_update
metadata using both session ID and tool-call ID. Current permission fields take
precedence. The dialog shows the tool, command or inputs, directory, and affected
paths, with raw protocol JSON in expandable technical details. Opaque requests
without any action details have approval buttons disabled.

Approval requests and decisions, including tool details and the selected option,
appear in saved AI activity, readable through
`ai_conversation_get`. Granting an ACP permission is harness control, deliberately
UI-only under the parity boundary; there is no MCP tool allowing an agent to
approve its own requests. The prompt covers `session/request_permission` requests
sent by the configured agent, whose own policy determines when it requests one.
Codex ACP is explicitly started in `read-only` ("Ask for approval") mode, with
`approval_policy=on-request` and `approvals_reviewer=user`. Saved profiles and
resumed sessions cannot override this with "Approve for me" or full access.
Agent settings expose only the user-approval mode; if the adapter cannot accept
it, the run stops before prompting the model. This does not require a prompt for
ordinary operations that the harness permits within its sandbox.
Headless essay generation reports an error if an otherwise permitted read requires
interactive authorization. Ordinary tools that require no ACP authorization are
unaffected. npm registry authentication settings do not control this workflow.


### Reusing application drafts and confidential evidence

Scoped `application_materials_validate` and `application_materials_submit` accept
one of a complete Markdown pair, a process-local `draft_id`, or a staged
`base_material_set_id` belonging to the same job and work order. Optional `edits`
replace exact single matches in either document. Validation returns a handle on
success and in `error.data.draft_id` on content errors, without writing the
database. Failed edit batches leave the buffered pair unchanged. Submission
revalidates current factual references and completeness through the same material
repository used by desktop documents. Review corrections can reuse the immutable
staged pair across ACP sessions; no model needs to repeat unchanged documents.

Document-generation and essay-writer profile reads exclude private, unconfirmed,
and explicitly confidential/stealth facts. Shared document/answer validation
rejects references to those facts even when visibility was accidentally set to
`application_only`. Normal profile management still exposes all facts locally.
Private visibility and factual revisions remain editable through the existing
Profile UI and profile MCP tools. No new ACP control tool is exposed.


Generation supplies short `citation_ref` values (F1, F2, etc.) instead of asking
models to reproduce UUIDs. The work order stores the immutable mapping in its
existing scope JSON. Scoped `profile_get` exposes the same references. Material
validation/submission resolves only facts comments and still requires the mapped
revision to be current, confirmed, and disclosable. Saved documents contain the
canonical revision IDs. New generation and edits reject unknown or stale references;
export of an existing saved pair retains its original confirmed evidence, with
optional reuse after a profile-change warning when applying. No fuzzy citation
repair or inferred factual support occurs.

Draft edits accept an explicit `replace_all` boolean for repeated literal text.
The default still requires exactly one match. Failures identify the edit number,
document, match count and text, and preserve the original buffered pair. Reviewer
edits against staged materials can use their original short citation comments.

The normal writer path submits the complete pair directly, since submission
already performs all validation. Standalone validation remains available for
read-only diagnostics; it is not an obligatory extra agent round trip.


### Employer attribution in generated and edited materials

The shared material repository checks employer attribution in both desktop saves
and MCP validation/submission. Saved exports retain the evidence and attribution
validated when the document was saved. A paragraph naming an employer, or a bullet
under an employer work-history heading, cannot cite an achievement belonging to
another employer without explicitly naming that employer. Direct employment
links take precedence; shared technology skills do not transfer achievements
between employers. Unscoped summaries and explicitly attributed comparisons may
use evidence from several employers. Errors identify the document, block, fact,
and employer so the writer can correct the claim without guessing citations.

Generation and post-review revision prompts separately require a clause-level
factual check of employer/project ownership, metrics, chronology, and causality.
The recruiting screen remains blind to the profile and compares the resume and
cover letter for conflicting attribution, metrics, dates, and event ordering.
The deterministic attribution
check is not a general semantic verifier: correctly assigning individual numbers
and preserving causal direction still require the writer's factual check. No new
AI turn is added, and user writing-style files and stored documents are untouched.

The initial writer and post-review writer also select evidence by relevance to
the stated role. Before the first draft, the writer states a brief evidence plan
in the existing activity conversation: the employer's core problem, the strongest
direct accomplishment and its short evidence IDs, and why it beats the best
alternative. Direct work anchors the opening when available; personal context
is included only for specific domain/user familiarity, without displacing that
evidence. This adds no separate AI turn or submission requirement. MCP harnesses
follow the same selection workflow through the bundled skill; saved ACP activity
remains readable through `ai_conversation_get`.
Profile context links do not require including linked facts
together. Broad ownership retains its scope; implementation examples need a
distinct reason to appear, and relevant technical depth should use the supported
design and behavior rather than a generic tooling label. These are writer
responsibilities. The recruiting screen only assesses promotion to human review,
with supporting evidence and material shortcomings or red flags.
Each bullet must represent one coherent accomplishment, with its implementation
or results. Shared employers, technologies, or themes do not justify combining
unrelated work. The writer is instructed to split such bullets or omit the less relevant
accomplishment; the recruiting screen does not prescribe edits.


### Blocked employers and statistics state dates

The Blocked employers navigation page lists employer names, dates, and reasons
through `JobRepository.watchBlockedEmployers`, also used by
`blocked_employers_list`. Unblock calls the same `setEmployerBlocked` service as
`employer_block_set(blocked: false, confirmed: true)`. Unblocking preserves jobs
and review history and does not launch searches or AI work.

Schema 16 records job state-change timestamps. Database triggers cover actual
review/availability, application stage/outcome/approval, and employer block
changes across UI, MCP, and background writers. No-op writes, notes, and content
refreshes do not advance the date. Migration recovers the latest known state date
from existing review, evaluation, application and employer-block history, using
first-seen when no later state date is available. Older unrecorded state dates
cannot be reconstructed. `statistics_get` returns
`date_basis: job_last_state_change` and `changed_since` (replacing `found_since`).
Both chart titles have info buttons explaining date selection and counting;
the same semantics remain discoverable in the MCP statistics tool description.


### Resume document generation after failure

The existing Retry AI / Resume generation action reactivates the latest failed
or interrupted application-materials work order, preserving its frozen citation
map, staged documents, writer ACP session, and completed review passes. Durable
`scope.materials_checkpoint` records review, writer correction, or publication as
the next step. A review failure retries only that pass. A writer correction
failure resumes the writer with saved feedback and requires a valid submission
before advancing. Valid staged documents are checked against current facts and
listing snapshots; changed evidence returns to the writer for repair. Completed
work orders still use normal regeneration when requested.

Older failed reviews can recover their pass from saved review-start activity and
staged materials. Invalid reviewer output and partial output on transport errors
are retained in activity with timing and call counts. Read-only
`ai_conversation_get` exposes the saved scope and activity for inspection. This
is ACP workflow control, so MCP does not gain a general launch/resume tool.
Expired attempts in the current app process are cancelled before reuse. The
normal availability preflight and final publication validation still apply, and
no application is submitted by resuming generation.

Both the central Activity chat and the job chat drawer show Retry for failed or
interrupted document generation. This uses the same resume service and targets
the selected conversation exactly. An older conversation cannot resume over a
newer generation for the job. Unsent chat text is retained while retrying.

Each recruiting screen, including retries and optional second passes, starts a
new ACP session in a distinct temporary workspace. The runner ignores any supplied
existing session ID for reviewers. The prompt contains only the screening role,
current listing, and current staged pair, without earlier reports, drafts, profile,
or writer conversation. The writer may address supported screening shortcomings,
but editorial instructions in a reviewer response are outside that role's scope.


### Codex ACP session storage

Codex ACP subprocesses use `codex-home` inside CareerShopper's data directory for
sessions, SQLite state, and logs. This applies to new chats, matching, drafting,
reviews, essay answers, settings discovery, and resumed turns. Each recruiting
screen still creates a fresh session. Other ACP adapters keep their existing
storage behavior. The supported Codex location controls are documented at
https://developers.openai.com/codex/environment-variables.

Only file-based sign-in is shared through an `auth.json` link. Personal config,
memories, and session indexes are not imported. Users whose platform cannot create
that link can sign in with CareerShopper's Codex home directly; credentials are
never included in activity or MCP responses. CareerShopper agent settings remain
in effect. A requested older CareerShopper session can copy its exact transcript
from the personal sessions or archive into private storage; subsequent writes
stay local to that copy. Originals and the user's recent-chat list are never
archived, deleted, or modified by this migration. Resuming an already imported
session never overwrites its newer context.

This is harness process configuration, not a new application-data operation;
no MCP launch or configuration tool is added. Existing conversation/activity
inspection remains available through the read-only MCP surfaces.


### Sequential search evaluation

Each saved-search run creates one AI conversation titled `Evaluate search: <name>`.
Manual and scheduled searches pass their saved-search ID to the same repository
operation. Candidates are claimed atomically and stored as individual work items
in that conversation, in a durable order. The agent receives one job per turn;
only the current running assignment may fetch, import, or submit an evaluation.
An evaluation and its item completion are saved together in one transaction,
so repeated submissions cannot duplicate a completed search item.

The run retains one ACP session. Later turns send only the current assignment and
a small applicant context version, computed locally from the saved Resume revision
and career preferences. The agent reads `profile_get` once and reuses its content
unless that version changes or context is lost. Eligibility is checked again before
each job; completed, otherwise evaluated, blocked, or discarded jobs are not rerun.
Prompts require individual evidence-based evaluation, not scripted keyword scoring.
Agents without session loading receive the full workflow in a fresh session.

At desktop startup, queued/running search work is recovered before lease expiry
handling, including work whose lease expired while the app was closed. The saved
session and pending items are reused; completed results and activity are retained.
Recovery also recognizes evaluations saved by an older helper before it marked the
item complete. It does not rerun the source search or clear provider blocks. An
explicit Stop leaves the conversation paused; Continue resumes pending work in
that same conversation. A normal agent turn without an evaluation fails only its
item and the queue continues. Harness/transport errors pause the run with its
remaining work retained for an explicit continuation, rather than failing every job.
Before recovery, legacy per-listing queues are consolidated into durable search
conversations. An unambiguous saved match/run association supplies the search name;
otherwise a recovered queue uses `Recovered search`. Different recorded runs and
agent configurations remain separate. Existing work-item identities and completed
evaluations are preserved; old transcripts remain attached to their original
conversations, whose scope links to the continuation. Sending a follow-up to one
of those old conversations routes to the grouped search. Migration is transactional
and idempotent, and explicitly stopped conversations remain stopped. All new search
dispatches use the grouped path, including callers without a saved-search ID.

`ai_conversations_list` exposes the same search-derived title.
`ai_conversation_get` exposes the search identity and queue in `scope`, per-job
`work_items` with `job_id`, `status`, and `error`, plus the saved transcript.
`job_get` and `job_evaluation_submit` retain the per-job data contract. No MCP
operation launches or resumes the ACP harness; startup recovery is desktop-owned.
Search polling and search enablement are unchanged.

## Fixed resume wording

Profile > Resume content owns exact resume wording in its displayed layout. The
first read offers an unsaved draft from confirmed, disclosable resume facts;
private/pending facts are excluded, and achievements are attached only when they
reference exactly one employment entry. No AI rewrites the prefill. The user
edits and saves it explicitly, creating a confirmed, versioned `resume_content`
career fact. Legacy generic facts remain archived for historical references and are not active AI evidence. The editor
supports adding, editing, removing, enabling and reordering entries and nested
work-history achievements. Saving checks the previous revision atomically.

New document generation uses structured `resume_plan` and `cover_letter_plan`.
`resume_content_get` supplies `generation_content`: enabled content with short
`F1`, `F2`, etc. IDs replacing persistent entry/achievement/detail IDs. The same
IDs select fixed content (`selected_ids`) and support generated prose
(`support_ids`). UUIDs and Markdown citation syntax are internal. The active
work order freezes the mapping to its saved revision. If that revision changes,
scoped catalog reads, composition and submission reject stale mappings instead
of silently citing different content. Unscoped reads retain the editable source
and revision alongside the generation catalog; `resume_compose` previews current
content without saving.

The AI supplies `professional_headline`, one `summary` object, `direct_match`
and `core_skills` lists, and flat `selected_ids`. Prose objects contain `text`,
`support_ids`, and an optional plain `label` rendered in bold. Cover-letter
`paragraphs` use the same objects. CareerShopper normalizes whitespace, formats
each paragraph/bullet, resolves evidence and inserts all citation comments.
The cover-letter assembler supplies the fixed applicant header/contact, stored
job title and employer, work-order date, greeting and signoff. The resume assembler supplies all fixed wording and section headings,
retains saved order and title attribution, includes enabled project summaries,
patents and education, and adds required bullets and complete prerequisite chains.
For each uncovered nonempty title it selects the highest-priority achievement;
saved order breaks ties. Empty titles retain their exact title/date without
invented bullets. Unknown and disabled IDs are rejected. Semantic support still
requires checking each generated claim against its cited content.

MCP discovery and writer/resume/reviewer instructions use this structured contract.
Legacy raw documents and exact-text edits remain readable and validatable for
existing drafts; newly generated plans contain neither revision UUIDs nor raw
Markdown. All generated references are stored as canonical saved-content revisions.

Raw generated Markdown, draft-handle edits, reviewer revisions and final
publication are checked against the same fixed assembly. Unknown selections,
wrong-employer achievements, stale content revisions, changed fixed wording,
omissions and added sections are rejected. Scoped writers cannot save fixed
content, and generic fact upserts cannot modify it. Explicit manual document
edits retain their existing UI/MCP path; existing documents are not rewritten
automatically. The saved fixed profile controls future generated resumes.

Work-history entries support `titles: [{title, dates, achievements: [{id, text}]}]`,
with at least one title. The resume editor starts each job with one title and
provides Add title, edit, reorder, and remove controls. Every title has its own
exact date-range text and achievements. Drag handles move achievements within a
title or between titles of the same job, retaining their IDs and wording. Titles
with achievements cannot be removed until those achievements are moved or removed.
The same structure and ordering are read and saved through `resume_content_get`
and `resume_content_save`. Legacy single `title`/`dates`/`achievements` values are
normalized on read without a database rewrite or revision change; saving uses the
new structure. Single-title resume output stays the same. Multiple titles appear
under one employer, each followed by its own selected achievements. Selecting a
job retains all its title sections. The assembler fills uncovered nonempty titles automatically.
Titles with no saved achievements retain their heading and dates without
invented evidence. Structured plans and raw generated Markdown enforce the same
title attribution, wording, order and coverage for nonempty titles. No database schema
change is needed because the structure uses the existing versioned career fact.

Achievement selection supports optional `priority` (integer 0 to 100, default 0)
and `required` (boolean, default false) in both the profile editor and
`resume_content_save`/`resume_content_get`. Points express relative importance
for AI selection among relevant evidence; they do not reorder saved achievements
or force inclusion. The assembler adds required achievements whenever that employment entry is
selected and fills uncovered nonempty titles using priority and saved order. Omitting the whole job remains permitted. Dragging retains these settings.

Projects retain `description` as their fixed, always-included summary. Their
optional `details: [{id, text}]` are individual fixed sentences; the editor can
add, edit, reorder and remove them. `resume_plan.selected_ids` accepts short IDs of optional details; absent selections include summary only. Any subset
is permitted for enabled projects. The shared composer appends selected sentences
verbatim in saved order to the summary paragraph. It rejects unknown or disabled IDs and resolves attribution itself. Raw generated Markdown and later
revisions are validated against the same complete-sentence assembly and required
achievements. Legacy saved content needs no rewrite: missing priority/required
means 0/false and missing project details means no optional sentences. These
fields remain in the existing versioned career-fact JSON; no database schema
change or automatic rewrite of profile facts/documents is involved.

Achievements may also declare `requires: [achievement_id, ...]`, defaulting to
no dependencies. The chain-link button on each achievement enters inline prerequisite selection
mode. Clicking other bullets in the same employment entry toggles their links;
Done linking or Escape exits selection mode. The source and selected rows are
highlighted, and arrows connect the dependent bullet to each prerequisite across
title sections. Connections follow layout, scrolling and reordering. No duplicate
checklist or repeated prerequisite wording appears in the editor. Wording edits
retain links; Save fixed wording persists the draft like other profile changes.
The same IDs are available through `resume_content_get` and editable through
`resume_content_save`. References must be unique, cannot reference themselves,
and must belong to the same job (including its other title sections). Saving
rejects dangling links; the UI explains which dependent bullets must be unlinked
before deleting a prerequisite. Dragging between titles retains links and IDs.

The structured composer automatically adds every prerequisite of a selected
bullet. Raw generated Markdown validation rejects missing prerequisites. Every selected prerequisite's
own links are checked too; mutual dependencies are allowed only when the entire
group is selected. Required achievements retain these prerequisite obligations.
Links do not force the whole job into the resume, merge bullets, change wording,
or override saved order. MCP schemas and generation guidance expose this same
contract. The existing versioned resume-content JSON stores the links, with no
schema migration or automatic profile/document changes.

Inline linking is a presentation change: the existing `requires` IDs and shared
resume-content get/save validation provide full MCP parity. The visible arrows
represent these same directional data links; MCP does not simulate selection
mode or drawing operations. Widget tests cover toggling, cross-title links,
Escape/Done, save/reload, wording edits retaining links, deletion protection and
layout changes.


## Resume content as the sole profile source

The Profile page contains Resume content and Preferences. Generic Career facts
CRUD and its MCP mutation tools have been removed. The existing revision tables
remain intact for document history; saving resume content still creates an
immutable confirmed revision, so no database schema migration is needed.

`profile_get` returns that saved revision in its `facts` evidence envelope and
preferences for matching. Disabled roles, projects, patents and education remain
available to matching, with recorded uncertainty intact. Application writer
scopes, essay writers and material-generation prompts receive enabled content
only, including scoped `resume_content_get`. Every generated section and cover
letter must use enabled content. New document validation rejects archived fact
citations and literal disclosure of disabled entries. Existing document records
and their revision references are retained.

Work-history entries accept optional `verification_status` (`confirmed` by
default, or `pending`). Pending imported records must stay disabled. Their UI
label explains that enabling and saving confirms the displayed wording. This
keeps uncertain historical records available as context without representing
migration as factual confirmation. User-requested migration copies missing
employment and its associated achievements into disabled resume entries and
preserves existing resume wording and selections.


Project detail sentences support the same directional `requires` links as work
achievements. Each ID must name another sentence in the same project. Self-links,
duplicates, dangling references, and links to another project or work achievement
are rejected by `resume_content_save`. `resume_compose` and material validation
require all prerequisites of every selected sentence, including chained links;
mutually dependent sentences must be selected together. Selecting no details is
still valid and keeps the mandatory project summary.

In Profile > Resume content, each detail has a chain button for inline prerequisite
selection with arrows toward the required sentences. Done or Escape exits linking.
Drag handles reorder sentences within their project, replacing up/down buttons;
links follow sentence IDs. A linked prerequisite cannot be deleted until its
incoming links are removed. These changes use the existing save/revision workflow;
MCP reads and writes the same ordered `details` array and `requires` IDs through
`resume_content_get`/`resume_content_save`. No new action or persistence layer is
needed for the presentation interactions.


## Core skills and compact profile sections

Resume content includes `skills: [{id, enabled, name, proficiency, notes}]`.
These are supporting evidence for matching, answers and tailored document prose,
not fixed paragraphs automatically printed on a resume. Enabled skills receive
the same short IDs used for selections and support_ids; disabled skills remain
matching-only. Proficiency and limitations must be respected in generated claims.
Old content defaults to an empty skills list without changing its revision.

Core skills appears above Work history in the editor. When either section has
more than three entries, it starts with three compact summary rows. Show all
reveals editing, ordering, visibility and removal controls; Show fewer restores
the preview. Expansion never changes saved visibility or content. Adding an entry
expands its section. Prerequisite linking prevents collapsing mid-edit.

The explicit Import saved skills action and `resume_content_import_skills`
(confirmed=true, unavailable in work orders) use the same repository import.
It imports confirmed disclosable archived skills, preserving proficiency,
context, experience notes, aliases, last-used information and preference notes.
Existing IDs or names are skipped without overwriting edits. Pending/private
records remain archived, and reads never trigger an import. The entire import
creates one versioned resume-content revision; no database schema change is
needed. `resume_content_get/save` exposes the same editable skill fields.


## Fresh document generation versus resuming

Document panels and stopped document conversations offer separate Resume generation
and Generate from scratch actions. The latter calls queueApplication with
fromScratch=true, creates a new work order and agent session, and uses current
Resume content, writing settings and a fresh evidence catalog. It never reuses
failed checkpoints, prior reviewer feedback or the old ACP session. Both chat
surfaces select the new conversation automatically. Previous conversations and
published/staged documents remain intact; a successful new run replaces active
documents through the existing publication path. An already-running generation
must be interrupted first; fresh requests never silently attach to it.

These buttons control the AI harness, so the existing MCP harness-control
exclusion applies. No general ACP launch tool is added. Saved conversations and
materials remain available through the existing read-only MCP tools.


Permission prompts retain the agent-provided labels for remembered choices.
An ACP provider may offer both Allow for this session and Always allow with
kind=allow_always; these remain distinct buttons returning their exact option IDs.
Provider scope descriptions appear above long tool arguments. Identically named
options are distinguished by their option IDs without inventing permission scope.


Job details show the stable saved job ID with a Copy job ID action. The copied
value is the same `id` returned by `job_get` and `jobs_search`; all job-scoped MCP
tools accept it as `job_id`. Inbox/All jobs text search and MCP `jobs_search.query`
also match the ID, so a copied handle can locate the record again.

Application answers distinguish Codex ACP commentary from final-answer chunks.
Progress announcements are excluded from the JSON payload; valid answers and
structured missing-information responses reach the MCP caller unchanged. The
same factual-support and length checks still apply. Agents without phase metadata
retain the existing JSON-only response contract.

Company-aware evaluation and writing use the same research guidance in desktop
prompts and the MCP skill. A complete posting skips posting retrieval, but does
not suppress research when company products, customers or domain are unclear.
Research uses available harness web/browser tools, prefers official pages, and
records source URLs in activity and evaluation summary/strengths. Applicant
details are never search terms. Blocks stop research; missing context remains an
uncertainty. Personal fit gives meaningful weight to supported domain and personal
connections; attainability remains tied to actual requirements. No automatic
interest bonus or perfect-match score is applied. Evaluation strengths/unknowns
are supplied to the document writer alongside the existing summary.

Profile > Resume content includes **Personal context**, for confirmed interests,
domain connections and credentials. `resume_content_get/save` expose the same
optional `personal_context` list with `id`, `enabled`, `topic`, and `text`. These
entries share saved fact revisions, short generation IDs, validation and disclosure
rules. Enabled entries can support letter/summary prose without being printed as
fixed resume sections; disabled entries remain matching-only. Older saved content
reads as an empty list, requiring no database migration. Untouched structured
document prompts upgrade to the company-aware default; custom prompts remain
intact, with shared factual/research guidance supplied separately. Existing
scores and letters change only when the user requests reanalysis/regeneration.

## Interview preparation and practice

Jobs have an **Interviews** tab backed by `InterviewRepository`. Schema 18 adds
job workspaces, immutable intel/question/context revisions, practice snapshots,
exchange checkpoints with correction history, and desktop preparation settings.
The ordered ladder is validated JSON in its workspace. Removed stages are
archived; user question overrides survive bank refreshes. Job availability,
review state, application stage, and outcome stay independent.

| Desktop/data operation | MCP tool |
| --- | --- |
| Workspace, ladder, preparation state, settings | `interview_get` |
| Historical research/context/bank revision | `interview_revision_get` |
| Add, edit, duplicate, reorder, archive stages and interviewer assignments | `interview_stages_save` |
| Inspect available saved document pairs | `interview_materials_list` |
| Select submitted/practice materials or attach submitted text | `interview_context_save` |
| Save sourced intel and stage question bank | `interview_preparation_submit` |
| Read stage questions and coverage gaps | `interview_questions_get` |
| User question edits/additions/archive | `interview_question_save` |
| Create practice and copy its harness prompt | `interview_practice_start` |
| Pinned context, rubric, transcript, feedback, correction history | `interview_practice_context_get` |
| Save a line of questioning and its assessment | `interview_practice_exchange_save` |
| Pause/resume/abandon/complete practice | `interview_practice_state_set` |
| Practice history | `interview_practices_list` |
| Comparable completed-practice score/dimension series | `interview_statistics_get` |

All writes share nested payload validation, ownership and revision checks with
the UI. A requested practice authorizes its subsequent checkpoints/state changes.
New exchanges use expected_revision -1; identical retries do not duplicate data.
Corrections keep previous exchange payloads. Completed/abandoned practices are
immutable; start a new practice for a new attempt. Applicant-specific guidance
uses pinned confirmed Resume evidence, never treats spoken answers as new facts.

Preparation is one combined intel/question submission so revisions become
visible atomically. Source-backed reports require citation IDs and retrieval
timestamps; predictions and gaps are explicit. Only an untouched empty ladder
is prepopulated. Later stage proposals are visible for user selection. Same-payload
submission retries are safe while the current revision is unchanged.

Moving a job to Interviewing initializes its workspace in the status transaction.
Existing Interviewing jobs gain pending workspaces on migration. Repeated status
writes and later re-entry preserve the workspace. **Automatic preparation** is
on by default: the desktop researches pending Interviewing jobs using the current
default ACP agent. Users can select another research agent or persistently turn
automatic preparation off. Missing default-agent setup leaves work pending until
an agent is configured. **Prepare with AI** starts preparation explicitly. The desktop monitor uses
existing work orders, durable ACP session IDs, and work items. Queued/running
orders resume on reopening; an explicit stop remains paused and a failed attempt
requires retry. Refreshes preserve earlier successful packets. Follow-up messages
continue the same preparation conversation.

Preparation buttons and the saved auto-preparation/agent choice control the
harness, so MCP exposes their resulting state read-only, not agent launch or
configuration tools. A standalone user-requested harness can perform research
and submit it directly through the same data contract. Scoped researchers may
only read the assigned job and relevant profile/documents and submit preparation;
they cannot change career facts, job outcomes, stages, settings, or start other
agents. Expired, finished, and foreign-job scopes cannot mutate records. The
read-only essay writer gets no interview tools.

A practice snapshots stage settings/weights, intel, stage questions, selected
application context, and confirmed resume evidence. By default interview_get
returns the latest non-staged saved application document pair, with attribution
latest_application_documents; explicit context selection overrides it. No manual
selection is required. Banks and practices pin the resolved text/material ID so
later documents do not alter history. Transcript fidelity is explicitly verbatim,
partial, or summary; there is no audio storage or audio-dependent grading.
The official score is 25 times the weighted mean of each assessed dimension's
mean (0–4). Unassessed dimensions are omitted and no assessed weight yields no
score. Confidence stays separate. The UI shows graded-question and criterion
coverage and graphs date-based series grouped by job/stage, rubric weights,
difficulty, personality/instructions, coaching, and known harness/model. Only
completed sessions enter trends; all states remain in practice history.

Voice is supplied by the user's harness. A real voice transcript/checkpoint
smoke test remains necessary before claiming complete voice integration; text
protocol and widget tests do not establish voice transcript fidelity.


## Jobs navigation and interview preparation review

The Jobs destination combines Inbox and All jobs in a segmented control; its
selection survives navigation to another destination. Interviews lists active
applications at the Interviewing stage and opens their Interviews tab directly.
The list shows the next unfinished stage, scheduled date when known, and preparation
state. `jobs_search(view: "interviewing")` uses the same shared predicate;
`interview_get` supplies the ladder and preparation state shown on each card.
Ended interviews remain accessible through All jobs.

The Filters dialog now filters application stage, outcome, review disposition and
availability independently, intersecting the chosen view and text search. The same
optional fields on `jobs_search` use shared JobListFilters matching; omitted fields
mean any. Counts reflect all matching records before MCP pagination. Clearing
filters leaves the selected view and search intact.

Intel is a continuous document with section headings. Company information is
visible initially; More expands the remaining sections together. This is presentation
only; `interview_get` continues to return the entire packet.

ACP prompts, the preparation-submit tool description and the bundled skill require
coverage of each material posting requirement, with technical fundamentals, concrete
code/query/debugging questions and applied tradeoffs. First-stage AI screens can be
technical. Document follow-ups explicitly reference the known passage. Banks also
include deliberate ambiguity and professional pressure, with criteria that reward
clarification and explicit assumptions. Difficulty/personality affect pressure;
uncertain employer tactics are never presented as reported facts.


Interview banks now expose stage_targets through interview_get and
interview_questions_get: at least 40 primary questions per active stage, or five
times estimated capacity (one primary question per five stage minutes). These
are preparation targets, not a restriction on saving a partial packet. The UI
shows actual counts and shortfalls. Agents use the sourced bundled question-pattern
catalog, including multiple variants, plus company/role-specific research.

Question depends_on is optional for compatibility with existing JSON banks.
UI prerequisite checkboxes and MCP saves use the same validation: active same-stage
references, no duplicates, no cycles. Refresh validates the merged bank including
user overrides so it cannot silently remove prerequisites. No database columns
changed. Saved legacy questions with no depends_on remain independent.

New practices pin a randomized topological order and selection_history counts.
Random choices are made among the least-practiced currently eligible questions;
only recorded interviewer turns count as exposure, once per question per practice.
Matching normalizes question text so refreshes with new IDs retain exposure.
Unstarted practice plans do not count as asked. Repeated starts with the same
client request ID and resumed practices preserve their exact original order.
The voice harness takes a time-appropriate subset with prerequisites and follow-ups
intact, using explicit revisit requests when supplied. The full bank remains
available through interview_questions_get; no general ACP control is exposed.


The research button shows Starting research immediately on click, then a spinner
and Queued/In progress labels while the saved preparation state is active. It
prevents duplicate clicks. A workspace subscription updates queued/running/ready/
failed/paused states without waiting for the periodic practice-history refresh.
The same persisted state and errors are readable through interview_get. Starting
is only a transient local dispatch indicator, not a claim that ACP is running.


Preparation activity is derived from the latest interview work order while it is
queued/running, even if a packet has already been saved. Packet submission marks
the work item complete but does not finish the ACP turn; the button stays busy
until the work order finishes. interview_get exposes this effective
preparation_state plus research_activity (work_order_id/status), and the UI
subscription watches both workspace and work-order changes. Saved intel remains
readable during this time. This also covers follow-up messages in the same
research conversation and keeps the Interviews list in sync.

Interview reports show the employer's locally cached logo above the intel document.
`interview_get.company` exposes its name, logo availability, and source URL (as
`job_get` does for job listings). `interview_preparation_submit.employer_logo_url`
accepts an optional discovered company image using the same shared logo cache and
validation as listing import. Image work runs after the atomic research save;
failures return `logo_warning` and preserve the packet and any prior logo. Viewing
the report does not fetch remote images. Duplicate packet retries skip image work.
The optional `intel.stage_proposals` defaults to an empty array; an existing ladder
is retained, and question stage references are still validated. Empty ladders need
proposals before a bank can reference those stages.

The shared preparation instructions and question-field MCP descriptions require
ready-to-ask prompts with concrete scenarios, referenced code/data/alternatives,
and question-specific grading criteria. The bundled skill illustrates complete
questions versus unfinished topic templates and distinguishes bounded oral design
questions from project briefs. Deliberate ambiguity remains supported with prepared
clarification answers. These guide AI authoring; schema validation does not claim
to judge semantic quality or reject user questions by wording patterns. Refresh
instructions audit and rewrite incomplete templates in an existing bank.

### Bounded reads and live updates

Jobs now load 50 rows initially, with Load more jobs expanding the SQL limit.
Text relevance, view eligibility, and Filters are applied before LIMIT/OFFSET by
shared JobRepository queries. Searches cover unloaded jobs; Inbox retains its
existing stable ordering while the user works. Its navigation count is a SQL
aggregate. `jobs_search` accepts offset/limit and returns total_count/next_offset.
Single-job reads constrain the same query by primary key.

AI Activity loads 50 conversation summaries and the newest 100 transcript entries,
with controls to load more conversations or earlier messages. MCP
`ai_conversations_list` now accepts offset/limit and returns next_offset;
`ai_conversation_get` applies its existing pagination in SQL and returns the total
and next_offset. Internal workflows that need full history retain explicit access.

The interview panel refreshes on relevant saved-data changes. A two-second
PRAGMA data_version check detects separate MCP connections; only a changed
version triggers a compact metadata comparison, and only changed interview
metadata reloads the panel. It no longer reloads the full workspace every five
seconds. Navigation rows read only ladder/status summaries. Question
widgets display 50 at a time; banks remain revisioned JSON and are decoded as a
whole when changed, so question pagination limits returned/rendered entries, not
JSON parsing. Practice list/statistics reads use compact snapshot projections and
batched assessments, avoiding per-practice full-context/history loads. Existing
interview_get/questions_get/practices_list/statistics_get expose the same data.
Schema 19 adds indexes for job observations, work items/orders, activity ordering,
materials and interview history; it preserves all saved records.

### Automatic practice stage and difficulty

UI setup defaults to the current stage and automatic difficulty; MCP
interview_practice_start uses those same defaults when stage_id and
settings.difficulty are omitted. interview_get.current_stage exposes the earliest
ongoing or upcoming scheduled stage, falling back to the first non-archived
unfinished stage in ladder order. A completed practice never
advances the real ladder; no current stage produces an actionable error rather
than silently revisiting a finished stage. Explicit stage IDs still allow revisits.

Automatic difficulty starts at 2/5, advances after each two completed practices
for the same job/stage, and caps at 5. Paused, active and abandoned attempts do not
count; completed coached and fixed-level attempts do. Supplying difficulty chooses
a fixed level. The resolved level, history count and delivery guidance are pinned
in the snapshot (difficulty_progression) and shown in practice details. Retries and
resumes retain those choices even if the ladder or history changes. Existing fixed
practice snapshots remain unchanged; graph grouping still uses the numeric level.
Question selection prioritizes the session level, then easier questions, and
randomizes by exposure within each suitability group while preserving dependencies.
The skill supports one-request setup by job name and a warm-up-to-target delivery
style without requiring the user to configure preferences each time.

### Interview overview and voice handoff

The interview overview leads with the current stage, instructions for starting
voice practice in a connected harness, and a copyable request for the selected
job. Copying includes the job ID to avoid ambiguous employer/role matches; it
neither creates a practice nor launches or messages a harness. The overview also
shows the company intel, with the rest of the report behind More. Question-bank
editing, practice history/trends, and stage/application/research settings are in
separate views. Question filtering affects only the question bank.

This is presentation and clipboard organization over existing shared services.
Existing job_get, interview_get, interview_questions_get, interview_practices_list,
interview_statistics_get and the interview editing/practice tools provide the same
data and actions; no MCP schema or database change is needed. The skill's
one-request practice workflow remains the voice entry point. Widget tests cover
navigation, clipboard job identity without creating a session, customization,
research status, stage/question editing and saved progress.

### Spoken practice turn-taking

The practice handoff prompt, context/save tool descriptions and bundled skill keep
checkpointing out of the spoken interview. The agent saves a completed question
and its follow-ups before asking the next, then yields for the answer. Tool results,
incidental sounds and presence checks do not advance the pending question. Spoken
assessment is deferred unless coaching is enabled; relevant save failures remain
reportable. The skill calls for a brief neutral acknowledgment before saving and
a specific follow-up when more detail is needed, rather than waiting silently for
a richer answer. Requested thinking time is respected. This changes guidance only,
not checkpoint payloads, persisted
snapshots, scoring or permissions. Voice timing remains controlled by the harness.

The voice skill also uses available completion/pause cues for turn-taking. A
prolonged observable pause with unclear completion prompts a brief check about
whether the applicant wants more time, while keeping the same question pending.
It respects requested thinking time and does not assume that text-only harnesses
expose silence, timing or continuous audio. This is skill guidance, not a new
CareerShopper audio detector or timer.

### Employer AI-disclosure requests

The application workflow skill and both ACP writing prompts omit AI-assistance
notices requested only by employer listing/form text. A user can explicitly
request disclosure. The rule does not authorize invented no-AI authorship claims
or alteration of saved source text. UI document generation and MCP answer drafting
share this behavior through their existing writing services; no schema change or
new action is introduced.

### Stable job browsing and bulk document regeneration

Search remains mounted while a new page loads, preserving focus and text selection.
Inbox/All jobs share search and filter state; changing view invalidates only the
result page. Older asynchronous inbox reads cannot replace a newer query. Empty
filtered results point to the search/filter controls rather than suggesting that
all retained jobs disappeared.

Jobs > Select jobs allows individual selection or all eligible loaded rows, retained
across searches and pagination. Regenerate selected documents queues fresh resume
and cover-letter pairs using current Resume content, without opening each job.
Eligibility is shared through InboxJob.canRegenerateDocuments and the additive
can_regenerate_documents field in job_get/jobs_search: approved, active, unapplied,
saved documents, not closed or blocked, and no queued/running document writer.

The desktop rechecks each selection and persists ordinary application-materials
work orders before processing one at a time. Startup drains queued work. Each
writer reads current evidence when it starts. A job applied while waiting is
skipped; a bulk draft cannot replace active documents after the application
progresses. Existing documents survive failed generation. No schema migration is
needed: the queue uses existing work-order status and scope fields.

MCP exposes the same candidate reads and document updates through existing
application_materials_get/update and confirmed Resume content. As with single-job
regeneration, the connected harness drafts the new pair; it does not launch ACP
through MCP. The skill documents the bulk workflow. Regression tests cover search
focus/selection, filters across view switches, selection across searches, queue
eligibility/deduplication, sequential dispatch, changed profile evidence, changed
application status, persisted queue restart and retained prior drafts.

Job profiles show compensation and employment type prominently above application actions and tabs. `job_get` and `jobs_search` expose the same saved values as `compensation_text` and `employment_type` (null when unavailable). `job_import_submit` accepts these optional fields from the posting, including the stated currency and pay period; neither surface estimates missing terms. Existing retained source responses are used to recover employment types and Indeed pay periods locally during the database upgrade. Hourly display does not change annual salary search filtering.

### Optional document refresh after profile edits

Editing the profile does not regenerate or invalidate existing saved document
pairs. Unapplied jobs show a **Documents out of date** indicator in the job list,
job actions and document panel. `job_get`/`jobs_search` expose
`documents_outdated`; `application_materials_get` returns `materials.outdated`.
Both are computed by the same service query, comparing cited Resume revisions
and saved preference values against the current profile. Reads react to profile
edits. For older documents without a preference baseline, preference changes
newer than the saved pair are detected by update time. Applied and later stages
are not flagged. Saving a new valid pair establishes a new baseline.

Apply rechecks freshness before touching exported files or opening the browser.
The desktop confirmation offers **Cancel** or **Apply anyway**. The MCP equivalent
is `application_apply` with `allow_outdated=true`, only after the user chooses to
use that saved pair despite profile changes. Canceling leaves files, documents
and status alone. Export without applying remains available without this extra
confirmation. Neither path regenerates documents. Historical saved documents
are validated against their original confirmed fact revisions; new generation
and document edits still require current confirmed, disclosable evidence.

The active Jobs navigation item refreshes the current page while preserving its
Inbox/All jobs view, search, filters, loaded page size and selected job. This is
the same read exposed by `jobs_search`; it does not rerun a saved search or launch
AI. Refresh still defers while documents have unsaved edits or an export is in
progress. Filters sit beside the view selector, and Add listing remains in the
main navigation. The chat composer uses one circular action: Send (play icon)
when text or attachments are present, Stop when the agent is running with empty
input, and disabled Send when idle with empty input. Enter still sends content;
empty Enter does not interrupt. These are harness controls, with no new MCP
launch or messaging surface.

Search evaluation scope errors identify the submitted and current job IDs when
an agent accidentally reuses the previous assignment. The write remains rejected;
the agent can read and evaluate the correct job without restarting the search.

Interview scheduling uses the existing `interview_stages_save` ladder contract.
The Interviews overview shows a clickable stage flow with completed, scheduled,
planned, skipped and cancelled states. Each stage opens date/time pickers, duration
and status controls; times are saved in UTC and displayed in computer local time.
`interview_get` exposes the same ladder, `current_stage`, and `next_scheduled_stage`.
The current stage prioritizes the earliest upcoming/ongoing appointment, then the
first unfinished ladder stage. `jobs_search` and `job_get` expose `next_interview`;
Interviews list dates prominently and sort scheduled jobs chronologically before
unscheduled jobs and text relevance, in SQL before pagination.

Scheduled stages automatically become completed after start plus duration. The
shared service reconciles elapsed appointments on reads and on the desktop's
existing interview monitor, including at startup even with AI preparation off.
This records elapsed schedule time, not attendance, and does not change the
application outcome or delete practice history. Manual planned, completed, skipped,
cancelled and archived stages are preserved. Workspace revisions and audit events
record automatic transitions; stale stage edits must reload before saving.


### Saved application answers

Application documents → Application answers lets users save, review, copy, and
edit question/answer pairs for any saved job, without requiring approval or
material generation. `application_answers_list(job_id)` exposes the same text,
status, revision, and timestamps. `application_answer_save` takes `job_id`, a
stable `answer_id`, `expected_revision` (0 for creation), `question`, `answer`,
`status` (`draft` or `submitted`), and `confirmed:true`. Both surfaces use
ApplicationAnswerRepository; edits require the current revision and cannot move
an answer between jobs. Text is preserved verbatim, including paragraph breaks.

Saving requires a user request to keep answers. Submitted status requires the
user to confirm the exact text was submitted. Saving or changing this status
never applies to the job, changes application state, or confirms career facts.
These records can contain user-written text as well as selected generated prose;
they are not evidence for future resume claims. The read-only answer writer and
scoped work-order agents cannot save answers. Interview preparation reads submitted
answers through its existing scoped interview_get application context. New practice
sessions snapshot them with the rest of the application context; existing sessions
retain their original context. Drafts are excluded from that submitted context.

`application_answer_generate` still returns a grounded answer without saving it.
It uses the shared writing voice while keeping the response specific to the form
question. Simple motivation questions default to about 60–100 words in one short
paragraph (less when sufficient), not a cover letter or career overview. Behavioral
or multi-part questions may need more detail; explicit length limits remain ceilings.
No new ACP launch control, external form interaction, or automatic submission exists.

Schema 21 adds the application_answers table and its job/creation-time index.
Behavior tests cover exact text round trips, edit conflicts, scope and job
isolation, draft/submitted attribution, interview context, migration, and UI saving.


### Mandatory qualification eligibility

`job_evaluation_submit` requires `unmet_requirements`, an array of confirmed unmet
mandatory qualifications (explicitly empty when none). Each entry contains
`requirement`, `posting_evidence`, `applicant_evidence`, and `fact_revision_ids`.
The shared validation verifies structure, an exact saved title/description quote
(ignoring whitespace differences), and current confirmed matching-evidence IDs.
The evaluating agent determines whether a qualification is mandatory and actually
unmet: a preferred degree is not a blocker, an explicitly allowed experience
alternative must be assessed, and missing applicant information remains unknown.

Any confirmed blocker prevents automatic Inbox placement, independently of the
60/40 weighted score and search threshold. The job remains in All jobs with the
existing AI-rejected disposition. The job profile's Evaluation section shows the
requirement and both sides of its evidence; `job_get` and `jobs_search` expose the
same `unmet_requirements`. Existing dimensions JSON stores these assessments;
legacy evaluations expose an empty list until re-evaluated. No legacy description
is classified using a keyword filter or silently rescored. Explicit user approvals
and discards remain unchanged, as do availability and application state. A user
can still choose to approve a job despite a recorded qualification gap.
