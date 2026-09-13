# CareerShopper

## Preparing an application

**Shared writing style** on Documents edits the reusable voice and prose rules
for resumes, cover letters, and application essay answers. Save commits to
`writing-style.md` in CareerShopper's data directory; without a custom file,
the bundled `assets/writing-style.md` is used. Reset to default stays in the
editor until saved. Document generation prompt now controls document structure
separately. Existing custom prompts and saved drafts are not overwritten.

When asked to answer an application essay question, a connected chat agent can
call `application_answer_generate` with the question, posting text/URL, optional
word/character limits, and `confirmed: true`. CareerShopper invokes its existing
default ACP model and settings; the writer chooses relevant confirmed profile
facts and follows the shared style. No job ID, per-task model, or general ACP
control is needed. The result is a copy-ready answer or a structured error
(including missing information), returned to the caller without saving answer
history in CareerShopper. Revisions pass the previous answer and feedback.
The ACP provider may retain its own session history. Nothing fills or submits
the form. Only this narrow MCP operation may invoke ACP; its writer cannot
recursively call it. Generation is serialized and uses the existing ACP timeout.

Documents includes **Pipeline Classic**, ported from the old pipeline renderer: centered navy masthead, compact Arial typography, ruled sections, and an applicant-name/page-count footer. New installs and untouched old defaults adopt it; customized templates remain intact. **Use pipeline template** replaces a customized layout while retaining your writing prompt. CareerShopper never reads the old project at runtime.

The default writing structure uses an opening summary, **Direct Match** evidence,
grouped **Core Skills**, substantive **Professional Experience**, and descriptive
**Open-source & Independent Products** entries. Relevant patents remain included;
projects are ordered by most recent start date. Bold labels, italic date lines,
hard line breaks, subtitle/footer frontmatter, and explicit page breaks are
supported by the editable preview and both exporters. Use Markdown source to
change formatting markers or page metadata. Old plain-text drafts still work.

Expand **Document generation prompt** in Documents to edit instructions for both drafts, then **Save template**. **Reset prompt to default** restores only the writing prompt in the editor; use Save template to commit it. It does not reset your layout. Changes affect the next generation or regeneration, not saved Markdown. Untouched older default prompts are upgraded, while custom prompts are preserved. The default emphasizes truthful, explicit job-terminology matching for ATS/AI screening and omits irrelevant sections or coursework. The fixed factual-support and output-format contract still applies.

The default uses **Relevant Work History** for selective employment history,
keeps unrelated accomplishments in separate bullets, preserves products' actual
end-user audiences, and itemizes patents with confirmed titles and spelled-out
categories in compact number/classification/title/month-year bullets, without
co-inventor names or attribution boilerplate. It does not invent dates to hide gaps or add routine page breaks
before projects. DOCX/PDF keep headings and role/project metadata with following
content when page space runs out; explicitly requested page breaks remain supported.

Cover letters use the pipeline's letter treatment rather than the compact resume
layout: 10-point body, 1.12 line spacing, 8-point paragraph spacing, 0.7-inch
top/bottom and 0.78-inch side margins, and no page numbering by default. Individually
customized template values are retained; explicit Markdown `page_numbers` takes
precedence. Documents shows the derived letter settings, also exposed by MCP.
The default writing prompt targets a focused 350–450-word letter: a role subtitle,
available drafting date, recipient, a few relevant evidence paragraphs connecting
the applicant to the employer's needs, and a separate closing/signature. It avoids
turning the letter into a second resume or an exhaustive technical inventory.
Both drafts also receive a recruiter/employer-perspective editorial review:
emphasize relevant capability, collaboration, decisions, and outcomes; omit
unnecessary staffing/crisis context (including being the only developer) that
may create avoidable negative signals. This changes selection and wording, never
the underlying facts or truthful answers to required application questions.
The resume headline describes the target role's actual function, not the current
job title. It removes employer-specific levels (Software Engineer IV → Software
Engineer) while retaining meaningful specialization. Work-history titles remain
unchanged; no seniority is inferred from an internal grade.

Inbox is a to-do queue ordered by overall fit score. Jobs appear when they need
approval or decline, when approved documents are ready to apply, or when failed
AI work needs a retry. Failures show an error badge, explanation, and Retry AI
action. Retrying keeps you in Inbox and advances to the next job. Approved jobs
awaiting documents, active document generation, and closed applications stay in
All jobs. MCP exposes the same queue through `jobs_search` with `view: "inbox"`.
Approval keeps you in Inbox and selects the next job while documents are prepared.
Use **Refresh** to load the latest saved inbox. While you use the window, background
changes wait. After three idle minutes, the inbox refreshes every three minutes;
unsaved document edits pause refresh. Your own actions still update the affected
job immediately. Refresh retains the selected job when it remains in the queue.
Expired AI runs are marked failed at startup and when their deadlines pass,
preserving conversation history and existing documents.

Application stage and outcome are separate. For example, **Interviewing** can
remain the stage after the outcome becomes **Rejected by employer** or
**Withdrawn by me**. Declining a listing yourself uses **Discard**. Existing
rejected/withdrawn records recover their last recorded stage from history when
available. MCP provides `application_status_set` and `application_outcome_set`.

1. **Approve** shortlists the job and invokes your default ACP agent to draft a tailored Markdown resume and cover letter. The stage shows Approved during preparation, then Ready to apply when documents are saved, followed by Applied, Interviewing, etc. as you update your progress. Outcome changes preserve that stage.
2. Optionally open the job’s **Application documents** tab to review or edit the drafts. The **Resume** and **Cover letter** tabs show an editable rendered preview: click a heading, paragraph, or bullet to edit its text. **Markdown source** exposes the underlying structure and evidence comments when needed. Review is not required to apply, but save or revert any edits before exporting. **Regenerate** requests fresh drafts; previous versions remain in local storage.
3. Choose **DOCX** or **PDF** in the job header, above the Job details/Application documents tabs. **Export documents** renders the saved resume and cover letter without opening the listing or changing status, so you can read the actual output in your preferred viewer. **Apply** performs the same export and also opens the listing in your default browser. Both clear the dedicated `~/Documents/CareerShopper` directory and export exactly `resume.<format>` and `cover letter.<format>`. The readiness indicator distinguishes missing documents, generation in progress, and documents ready to apply; click it to open the documents tab. Review is optional. Complete the application yourself, then change the application-status chip to Applied.

The output folder is shared by all jobs at `~/Documents/CareerShopper` (under the user profile on Windows). **Everything in that folder is removed on each export.** Other files in Documents and exports in the former data-directory output folder are left untouched. Do not use the new output folder to store files you want to keep. Saved Markdown drafts are separate and are not deleted. Opening an approved, not-yet-applied job with no drafts or previous generation attempt queues its first generation automatically. Failed attempts require an explicit retry.

Every Markdown block carries a `<!-- facts: revision-id -->` source comment linking it to the current saved Resume content revision. Only enabled content may support application claims. Keep these comments when editing; they never appear in exported documents. Update your profile and regenerate if facts change. DOCX uses the resume template’s font; PDF embeds DejaVu Sans for portable rendering. Exporting does not submit an application or automatically mark one Applied.

CareerShopper is a local-first desktop application that continuously finds,
deduplicates, evaluates, and manages job opportunities. It is intentionally
separate from the prior `application-pipeline` research project.

The current implementation establishes the Flutter desktop shell, SQLite/Drift
information model, conservative normalization and deduplication primitives,
public Greenhouse, Lever, and Ashby adapters, JobSpy-style Indeed GraphQL and LinkedIn
search adapters, an editable versioned resume template with live preview, and
the portable MCP/Agent Skill integration. It also acts as an ACP v1 client: the
user selects a compatible agent from the official ACP Registry, and
CareerShopper supplies its scoped MCP server when creating each ACP session.
Application drafts can be reviewed and exported locally to DOCX or PDF.
Manual searches analyze eligible new or changed matches through the configured
ACP harness and surface matches meeting the score threshold in Inbox. Unchanged
evaluated listings are skipped. Run now works with searches paused and leaves
polling disabled. Analysis progress and failures appear in Activity.

Scheduled searches continue while the Linux window is hidden in the system tray.
Close the window to hide it; use **Open CareerShopper** in the tray or launch the
app again to reopen the same instance. **Quit CareerShopper** exits and stops
scheduling. Agent approval requests reopen a hidden window. A desktop tray host
is required; without one, closing the window exits normally.

Linux builds require the Ayatana AppIndicator development library
(`libayatana-appindicator` on Arch, `libayatana-appindicator3-dev` on Debian/Ubuntu).
`make test-native` checks tray lifecycle behavior with a GTK display; the tests
can also use GTK's headless Broadway backend on a private D-Bus session.

## Current desktop workflow

1. Open **Sources** and add Indeed, LinkedIn, or one or more Greenhouse, Lever,
   or Ashby employer boards.
2. Ask an MCP-connected AI agent to build your factual career profile,
   preferences, and saved-search strategy—or create searches manually under
   **Searches**.
   Each search selects one source and its own schedule: daily at a local time,
   a repeating interval, or a custom cron expression. Scheduled searches run
   while CareerShopper is open; missed runs are combined into one on reopening.
3. Edit and save your history under **Profile → Resume content**. Disabled entries
   remain available for matching but stay out of applications. Review uncertain
   imported work before enabling it. Manage preferences in the adjacent tab.
   Inspect and edit every search under **Searches**.
4. Open **Documents** to review or edit the reusable resume layout, typography,
   colors, spacing, and section order.
5. Adjust searches directly or tell the AI when you want to see more or less of
   something so it can revise them through MCP.
6. Open **AI → Agents**, browse the official ACP Registry, and select an agent
   such as Codex. **AI → Activity** is a persistent chat/activity view: adding
   a URL streams that job-scoped work there, and **New chat** starts a normal
   conversation with CareerShopper MCP available.
7. Inspect retained results under **All jobs**. Jobs that pass deterministic
   filtering remain pending until the AI evaluation workflow runs. An evaluated
   URL can be refreshed and reanalyzed from its detail pane; the complete
   posting is retained in a new snapshot and displayed in the scrollable job
   view.

Source cards can be configured in the app. Provider health and backoff status
appear on each source.

## Install CareerShopper

```sh
make install
```

On Linux this builds and installs the desktop application for the current user,
including a launcher and `.desktop` entry, then installs the native MCP helper,
portable Agent Plugin, and CareerShopper Skill. The default locations are:

- Application bundle: `$HOME/.local/lib/careershopper`
- Command-line launcher: `$HOME/.local/bin/careershopper`
- Desktop entry: `$HOME/.local/share/applications/com.example.careershopper.desktop`
- Agent Plugin: `$HOME/.local/share/careershopper/agent-plugin`
- Shared Skill: `$HOME/.agents/skills/careershopper`

The command refreshes the desktop application cache when the platform utility
is available. It also prints ready-to-run MCP registration commands for using
CareerShopper from a standalone harness, the portable Agent Plugin path, and a
generic MCP configuration containing the installed executable's absolute path.
Restart or reload an already-running harness after installing the Skill.
Repeated installs replace the same active Skill. Recoverable older copies are
kept in `$HOME/.agents/careershopper-skill-backups`, outside the `skills`
discovery directory. Installation also moves managed backups left by older
versions there so they no longer appear as duplicate Skills.

In the desktop app, open **AI → Agents** and choose **Browse ACP Registry**. Registry
metadata is cached locally. CareerShopper launches the selected distribution
without a shell, negotiates ACP v1, creates a session with the native
CareerShopper MCP helper, and sends the scoped work prompt with
`session/prompt`. An existing pending URL can be retried with **Run with AI**
from its detail view. The Codex adapter reuses the existing Codex CLI login and
cached ChatGPT subscription credentials; CareerShopper does not maintain a
second login. Custom ACP/stdio executables are also supported.

Use the **Agent defaults** (sliders) button beside an agent, or in the new-chat
dialog, to choose its advertised model, reasoning effort, fast mode, and other
ACP session options. Defaults are saved locally and copied into new chats and
job imports. The sliders button beside an existing conversation's message box
changes settings for its next turn; finish the current turn first. Settings are
discovered without sending a model prompt. Changing a model refreshes dependent
choices, and unavailable saved choices must be reviewed in settings before a
run can proceed. Agents without session configuration options keep their defaults.

CareerShopper stores the visible ACP transcript and session ID locally. A
follow-up launches the selected adapter and uses ACP `session/load` before the
next `session/prompt`, so the agent restores its own conversation history and
context. Model context-window management and compaction belong to the agent;
users can start a fresh chat when they want a clean task boundary.

Override destinations when packaging or testing:

```sh
make install PREFIX=/desired/user-prefix AGENTS_DIR=/desired/.agents
make mcp-info INSTALL_ROOT=/desired/plugin/root
```

## Development

```sh
flutter pub get
dart run build_runner build
dart analyze
flutter test
flutter run -d linux
dart run tool/build_agent_plugin.dart
# Or use: make check, make build-agent, make build-linux
```

The database defaults to the platform user-data directory. Set
`CAREERSHOPPER_DATA_DIR` to an explicit directory for development or MCP
integration tests.

## Trust boundaries

- Job listings and web content are untrusted data.
- Employer blocks are deterministic and happen before AI evaluation.
- AI-generated career claims must cite confirmed career-fact revisions.
- Closing a listing never changes the user's application status.
- CareerShopper does not automate browser applications or evade source blocks.

See [docs/source-policy.md](docs/source-policy.md) for adapter safety and scope.

Search runs show a per-source result report and retain **Run history & diagnostics**
with errors, skip reasons, HTTP status, page counts, new/existing listings, filtering
and AI eligibility. Indeed uses JobSpy's GraphQL approach and relevance ordering,
reading only the first 100 results per run. Empty
results, provider failures, incomplete responses and search filtering are distinct.
Polling is not enabled by a manual run. See [UI/MCP parity](docs/mcp-ui-parity.md)
for the matching `saved_search_runs_list` tool and counting details.
