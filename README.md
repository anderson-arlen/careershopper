# CareerShopper

**Early development · Experimental · Build from source; no prebuilt binaries yet.**

CareerShopper is an AI-first job search workspace with automated searches,
personalized matching, tailored resumes and cover letters, and application
tracking. Put your searches on autopilot and spend your time on the strongest
matches.

Use the AI harness of your choice: an **agent skill** teaches it CareerShopper's
workflows, **MCP** lets it read and manage your career profile and jobs, and
**ACP** lets the desktop app delegate work to a compatible agent. Work in the
UI, control CareerShopper directly through your harness, or use both.

## How it works

1. **Build the resume you would never send.** Work with your AI agent to create
   a detailed record of your career: roles, projects, accomplishments, skills,
   and the context behind them. Go well beyond what fits on an application
   resume. This becomes the source material for matching and tailored documents.
   Add what you enjoy, what you want next, and preferences such as location,
   remote work, compensation, and the kinds of companies you want to join.

2. **Turn your profile into searches.** Ask your agent to construct searches
   around your experience and goals, then review or adjust them in CareerShopper.
   Search Indeed and LinkedIn, or follow employer boards on Greenhouse, Lever,
   and Ashby. You can also import a listing directly by URL.

3. **Let AI sort the results.** Each eligible listing is evaluated against your
   career profile. Low-scoring results stay out of your inbox; matches that meet
   your chosen threshold arrive with an assessment of fit. Your inbox puts the
   strongest matches first, so you can focus on better opportunities before
   spending time on marginal ones. Hidden results remain available in All jobs.

4. **Keep opportunities coming.** Schedule searches daily, at an interval, or
   with a custom cron schedule. New matching jobs replenish your inbox as they
   are found. Apply to as many or as few as you want. Each search run uses one
   AI conversation, evaluating jobs individually while reusing your career
   context. Interrupted evaluation queues resume when you reopen the app.

5. **Approve the jobs you want to pursue.** Approval starts a tailored resume
   and cover letter for that job, saved as Markdown. Keep reviewing other jobs
   while the agent prepares them. You can then inspect, edit, or regenerate the
   drafts in the job's Application documents tab.

6. **Apply and track your progress.** Choose DOCX or PDF and click **Apply**.
   CareerShopper exports your documents and opens the job in your browser for
   you to complete the application. Confirm when you've applied, then track
   interviews, offers, and outcomes. The Statistics page shows how many jobs
   you've found, where they came from, and how they progress through your
   application funnel.

Scheduled searches run while CareerShopper is open. On Linux, closing the window
keeps it running in the system tray when a tray host is available; **Quit** stops
it. Missed scheduled runs are combined into one run when you reopen the app.

## A detailed career history becomes a focused application

Your saved resume is the source of truth. The AI selects relevant experience
from it and builds a resume around the specific job, including an opening
summary, a **Direct Match** section connecting your experience to the role,
grouped **Core Skills**, relevant work history, and supporting projects or
patents. The cover letter explains the match in your voice.

Applicant-specific claims must be supported by confirmed resume content.
Entries you disable can still inform matching but are excluded from application
materials. You control the shared writing style, document instructions, section
order, and layout in **Documents**.

Drafts are editable Markdown with a rendered preview. CareerShopper handles
DOCX and PDF formatting, and keeps previous drafts locally. Your agent can also
help answer application essay questions using the same saved career history
and writing style.

Exports go to `~/Documents/CareerShopper` as `resume.docx` and `cover letter.docx`
(or their PDF equivalents). The folder is cleared first so it contains only the
documents for your current application. File pickers typically reopen the last
folder you used, so when you're filling out several applications, the right
files are waiting in the same place every time. There's no searching through
previous exports or guessing which resume belongs to which job.

**Each export replaces everything in that dedicated folder.** Keep files you
want to retain elsewhere; saved Markdown drafts are stored separately.

## Bring your own agent

CareerShopper relies on a configured AI harness for matching and document
preparation. In **AI → Agents**, browse the ACP Registry and choose a compatible
agent, such as Codex, or configure a custom ACP executable. Model choices and
other available settings come from your selected agent.

To work from your own harness instead of the desktop UI, connect the installed
CareerShopper MCP helper and load its agent skill. You can ask it to build your
profile, manage searches, evaluate jobs, and prepare application documents.
The installer prints MCP registration commands and the plugin location.

Your profile, job history, documents, and visible AI activity are stored locally.
AI tasks share the context they need with your configured harness and its model
provider. Authentication, billing, and model usage are handled through that
harness; CareerShopper does not require its own model API account.

## Build and get started

Linux is the current installation target. This is experimental software, and
prebuilt binaries are not planned until it is closer to a release.

You'll need a Flutter SDK with Dart 3.12.2 or newer in the 3.x series, Flutter's
Linux desktop build dependencies, and the Ayatana AppIndicator development
library (`libayatana-appindicator` on Arch or
`libayatana-appindicator3-dev` on Debian/Ubuntu). Your chosen ACP agent may also
need its own launcher, such as `npx` or `uvx`.

```sh
git clone https://github.com/anderson-arlen/careershopper.git
cd careershopper
make install
```

This builds and installs the desktop app, native MCP helper, agent plugin, and
skill for the current user. Launch CareerShopper from your application menu,
then:

1. Choose and configure your agent under **AI → Agents**.
2. Add your job sources under **Sources**.
3. Start a conversation in **AI → Activity**, or connect your own harness, and
   ask it to help build your career profile and searches.
4. Review your profile and searches, then run or schedule them.

After installing the skill, restart or reload an already-running harness.
When updating CareerShopper, quit the app, run `make install` again, and relaunch.

<details>
<summary>Install locations and overrides</summary>

- Application: `$HOME/.local/lib/careershopper`
- Launcher: `$HOME/.local/bin/careershopper`
- Agent plugin: `$HOME/.local/share/careershopper/agent-plugin`
- Agent skill: `$HOME/.agents/skills/careershopper`

```sh
make install PREFIX=/desired/user-prefix AGENTS_DIR=/desired/.agents
make mcp-info INSTALL_ROOT=/desired/plugin/root
```

The database lives in the platform's user-data directory. Set
`CAREERSHOPPER_DATA_DIR` to use a separate directory for development or testing.

</details>

## Development

```sh
make run          # Run the desktop app from source
make check        # Check formatting, analyze, and run Flutter tests
make test-native  # Test Linux tray behavior; requires a GTK display
make build-linux  # Build the Linux desktop bundle
make build-agent  # Build the native MCP helper and agent plugin
```

After changing the database model, regenerate the Drift code with
`dart run build_runner build`.

For implementation details, see the [architecture](docs/architecture.md),
[UI and MCP capabilities](docs/mcp-ui-parity.md), and
[source behavior and access policy](docs/source-policy.md).

## License and acknowledgments

Created by **Arlen Anderson** and available under the [MIT license](LICENSE).

The Indeed adapter was informed by [JobSpy](https://github.com/speedyapply/JobSpy),
including its GraphQL request and client protocol headers. Its
[MIT notice](assets/JobSpy-LICENSE) is retained with the adapter.
Bundled fonts and source icons have their own notices in
[assets/fonts/DejaVu-LICENSE.txt](assets/fonts/DejaVu-LICENSE.txt) and
[assets/sources/README.md](assets/sources/README.md).
