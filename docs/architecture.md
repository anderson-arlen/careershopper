# Architecture

CareerShopper is one Flutter desktop application plus a small native Dart
console helper. Both use the same domain and SQLite code; users do not manage a
service or language runtime.

```text
saved searches -> source adapters -> observations -> normalize -> employer block
    -> residual filters -> conservative dedupe -> SQLite -> AI work queue -> inbox

Flutter app --ACP v1 / stdio--> registry-selected agent
agent --session-scoped MCP/stdio--> careershopper-agent --SQLite--> CareerShopper
```

## Components

- `lib/src/storage`: Drift schema and repositories. SQLite is the durable source
  of truth and uses WAL, foreign keys, and a busy timeout.
- `lib/src/ingestion`: provider-independent normalization and dedupe decisions.
- `lib/src/sources`: adapter contracts. Adapters return observations and never
  write application state directly.
- `lib/src/features`: Flutter presentation and user-authorized commands.
- `lib/src/protocol`: direct ACP client and MCP server implementations. The app
  reads the official ACP Registry, starts a compatible distribution over stdio,
  negotiates stable protocol v1, and supplies the native MCP helper in
  `session/new`.
- `bin/careershopper_agent.dart`: MCP and integration discovery executable.
- `agent-plugin`: portable plugin metadata and the CareerShopper Agent Skill.

The Profile screen is the human management surface for career facts,
provenance, verification, visibility, and preferences. Users may edit every
fact and preference. Fact edits create immutable confirmed revisions; retiring
a fact leaves its history intact. Search Strategy is a shared editing surface:
users can create and revise searches directly, and compatible AI harnesses can
automate the same operations through MCP after reading the profile, configured
sources, and existing searches.

The Documents screen owns versioned resume presentation templates. Template
records contain typography, page geometry, spacing, colors, section behavior,
and section order; generated Markdown remains a separate immutable content
artifact. The editor includes a representative live preview. The deterministic
DOCX/PDF renderer will consume the stored template contract rather than
accepting layout instructions from an AI harness.

## State axes

Availability (`unknown`, `open`, `closed`), review disposition
(`pending_evaluation`, `inbox`, `hidden_by_search`, `hidden_low_score`,
`approved`, `discarded`), and application status (`not_applied`,
`ready_to_apply`, `applied`, `interviewing`, `rejected`, `withdrawn`, `offer`,
`hired`) are stored and changed independently.

## IDs and revisions

Public domain identifiers are UUIDv7 strings. Source observations, job snapshots,
career-fact revisions, AI evaluations, application events, and materials are
immutable records. Mutable aggregate rows point at their current revision.

## AI work dispatch

The Flutter app stores the selected ACP agent and its pinned Registry version,
creates a work order/conversation, then starts the agent without a shell. It
performs `initialize`, creates an isolated session workspace, and calls
`session/new` with the CareerShopper MCP executable. Automated jobs include a
work-order environment so the MCP server restricts mutations to the assigned
job; a user-started chat receives the normal unscoped MCP surface. The app sends
turns through `session/prompt` and persists visible `session/update` messages,
plans, tool activity, errors, and usage updates in SQLite. Structured results
must be submitted through MCP; final chat text is never parsed as application
data.

The ACP session ID is durable. Follow-up turns start the same adapter and call
`session/load`, ignoring replayed events already in the local transcript, before
prompting again. The agent owns model context, history restoration, and context
compaction. CareerShopper owns the auditable user-facing transcript and offers a
new-chat boundary instead of attempting its own token-history summarization.

The Registry acquisition and process-launch layers are replaceable. Registry
entries using npm (`npx`) and Python (`uvx`) distributions are supported when
their launcher is installed. Binary archive installation remains separate so
it can verify platform, archive paths, and hashes before use.
