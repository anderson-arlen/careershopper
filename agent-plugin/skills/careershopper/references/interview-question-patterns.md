# Interview question patterns and pressure practice

Research checked 2026-09-13. Use this catalog when preparing a bank or running a
mock interview. These are families to adapt to the actual role, not a script to
repeat or a claim that every employer uses every tactic. Sources establish broad
formats; the prompts below are original practice examples. Variations explicitly
marked as simulations are training designs, not reports of employer behavior.

## Evidence behind the catalog

- [OPM structured interviews](https://www.opm.gov/policy-data-oversight/assessment-and-selection/other-assessment-methods/structured-interviews/): past-behavior and hypothetical-situation questions, with planned follow-up probes tied to job competencies.
- [Amazon interviewer guidance](https://www.aboutamazon.com/news/workplace/amazon-jobs-interview-mistakes): expect evidence, distinguish personal contribution from team results, prepare varied examples, and clarify assumptions.
- [Microsoft technical interviews](https://careers.microsoft.com/v2/global/en/hiring-tips/technical-interviewing): problem decomposition, implementation, design, testing, boundaries and error conditions.
- [Microsoft interview tips](https://careers.microsoft.com/v2/global/en/hiring-tips/interview-tips.html): when unfamiliar or stuck, clarify and show resourcefulness rather than pretending to know.
- [Harvard interviewing guidance](https://careerservices.fas.harvard.edu/resources/interviewing/): resume discussion, negative framing, professional fit, and silence that may simply mean note-taking.
- [Indeed employer guide to stress interviews](https://www.indeed.com/employers/c/info/what-is-stress-interview): forceful questions, interruptions/disinterest, brainteasers, cases and rapid-fire rounds. It cautions against inconsiderate conduct; inclusion here prepares the applicant, not endorses that conduct.
- [McKinsey interview formats](https://www.mckinsey.com/careers/interviewing): detailed experience probes, analytical cases and role-specific expertise assessments.
- [Harvard offer/compensation guidance](https://careerservices.fas.harvard.edu/resources/harvard-college-evaluating-and-negotiating-job-and-internship-offers/): salary expectations and time-sensitive decisions can arise during the process.

## Coverage families

For each relevant family, generate several distinct scenarios and follow-up paths.
Do not copy this table verbatim as the bank or substitute it for technical coverage.

| Family | Original practice example / variation | What to evaluate | Basis |
| --- | --- | --- | --- |
| Broad opening / undefined scope | Give me the background that matters for this role. Start one variant more vaguely, then clarify when asked. | Relevant structure, scoping and concision. | Harvard, Microsoft |
| Repeated ownership and evidence probes | Your resume describes a migration. Which decisions were yours? What measurements support the outcome? What would a teammate add? | Specific contribution, evidence, honest limits. | Amazon, OPM |
| Exhausted prepared story | Use a different example of that skill. Now describe one that went badly. | Breadth, responsiveness, no invented story. | Amazon |
| Negative framing / self-awareness | Which technical judgment would you reverse? What criticism was fair? What changed afterward? | Accountability and concrete improvement, not disguised strengths. | Harvard |
| Uncomfortable career narrative | What explains that transition? Why this scope now? What might a former manager question? Use only actual saved history. | Clear factual explanation without defensiveness or attacking others. | Harvard, Indeed |
| Conflict / competing obligations | Two stakeholders want incompatible outcomes. How do you proceed? What if your manager rejects that plan? | Listening, prioritization, escalation and tradeoffs. | OPM situational format; original scenario |
| Skepticism / defend and revise | I am not convinced that design is safe. What evidence would change your mind? | Evidence-based defense and willingness to update. | Original pressure simulation based on Indeed and Microsoft |
| False premise / authority pressure | An interviewer asserts a deliberately incorrect technical rule and asks you to agree. | Respectful correction and verification instead of automatic agreement. | Original simulation; use verified technical criteria, not an employer claim |
| Forced choice / conflicting constraints | Pick one of two flawed options. Is there a third? Then require a decision under a real deadline. | Detect false dilemmas, state costs, make a justified decision. | Original situational/case variation based on OPM and McKinsey |
| Missing data / changing evidence | Diagnose a failure with limited telemetry; reveal a new observation that contradicts the initial theory. | Information gathering, hypothesis revision, avoiding sunk-cost reasoning. | Original technical/case variation based on Microsoft and McKinsey |
| Knowledge boundary / bluff pressure | Explain an unfamiliar mechanism. After an honest limit, ask how you would investigate it. | Separate facts from hypotheses; propose a useful verification plan. | Microsoft interview tips |
| Rapid-fire / multipart / compression | Ask short fundamentals from different posting requirements, or request a 30-second explanation after a detailed one. | Accuracy, organization and recovery. Allow asking to take multipart questions in order. | Indeed lightning rounds; compression/multipart are simulations |
| Interruption / low feedback / silence | Cut to the unresolved point, acknowledge neutrally, or pause briefly after a complete answer when the harness supports it. | Stay composed, resume the point, avoid unnecessary rambling. | Indeed; Harvard on silence |
| Estimation / unfamiliar puzzle | Estimate a role-relevant capacity or investigate a small logic puzzle with stated assumptions. | Decomposition, sanity checks and reasoning; not a memorized trick. | McKinsey cases; Indeed brainteasers |
| Critique / role reversal | Identify a risk in this product decision; then explain it to a nontechnical stakeholder. Or invite feedback on the interview itself. | Tact, useful critique and audience adaptation. | Indeed forceful questioning; stakeholder variation is a simulation |
| Commitment / compensation pressure | What would make you leave? What range would you consider? A simulated recruiter presses for an immediate commitment. | Consistency with saved preferences, questions and professional boundaries. | Harvard compensation guidance; pressure is a simulation |

Treat confidential-information requests and personal boundary challenges as
optional professional-boundary simulations. Credit a tactful refusal or redirection;
do not require disclosure of private information, former-employer secrets or an
invented competing offer. Do not make jurisdiction-specific legal claims.

## Write the question, not an instruction to create one

Every saved `prompt` is an actual interviewer utterance. Independently compose
its substance; do not use a topic-by-template loop to fill the bank. Scripts can
serialize already authored questions, but rotating technology names through
"fundamentals / reading / debugging / design / tradeoff" sentence patterns does
not produce meaningful coverage. A prompt must test a particular concept or
judgment. Leadership, for example, cannot be substituted for a software component
in a production-debugging scenario.

The examples below illustrate completeness and scope, not a fixed list to copy:

| Unfinished template | Ready-to-ask example |
| --- | --- |
| Design a REST and distributed systems solution for an internal workflow with clear contracts. | A client submits a report-generation job over HTTP, times out, and retries. How would you prevent the retry from creating a second job, and what would you return while the first job is still running? |
| Choose between two plausible CI/CD approaches under a tight deadline. | You must deploy a stateless API today. Would you choose a rolling deployment or blue-green deployment if there is not enough capacity to run two full copies? How would you roll back? |
| Explain the core concept of PostgreSQL. | In PostgreSQL, would you use `manager_id = NULL` or `manager_id IS NULL` to find employees without a manager? Why? |
| Read a small React example and predict its behavior. | In a React function component, `count` is initially 0. A click handler runs `setCount(count + 1); setCount(count + 1);`. What count do you expect after the update, and how would you make two increments reliable? |
| A production feature using leadership regresses for one workload. | A release is causing errors, your manager wants to keep it live, and the on-call engineer wants to roll back. What evidence would you gather, and how would you handle the disagreement? |

Include referenced code, inputs, symptoms, and competing options **in the prompt**.
Do not refer to a nonexistent example or put all the facts only in hidden grading
notes. For voice practice, keep snippets short enough to read aloud; longer code
exercises can be shown in chat when that fits the stage and user request. Ask
bounded design questions; a multi-hour implementation brief belongs in the intel
exercise section as a reported assignment or labeled preparation exercise.

Deliberately vague questions remain useful. Give the interviewer concrete facts
to reveal when the applicant clarifies: for example, a broad diagnostic opening
can withhold traffic and error details, but `follow_ups` must state the actual
observations to provide. Distinguish an intentional clarification test from an
unfinished scenario. The practice agent should not have to invent the missing
problem, options, or answer key.

Before submission, read each question as the interviewer and work through a
plausible answer. Put the specific expected result/concepts, acceptable tradeoffs,
and common incorrect reasoning in `criteria`; generic "correctness and depth"
is insufficient. Check technical criteria against the relevant primary sources
and runtime assumptions. On refresh, replace incomplete templates in the saved
bank instead of preserving them because their topic labels appear to cover the
posting. Count independently usable questions, not rows. If quality or coverage
falls short, report the actual shortfall rather than manufacturing completeness.

## Building banks for repeated practice

Read `questions.stage_targets` from `interview_get`; for newly proposed stages
that are not saved yet, apply the same target formula below. Each active stage targets at
least **40 distinct primary questions**, or **five times its estimated session
capacity**, whichever is larger. Capacity uses one primary question per five
minutes as a planning estimate, not a rule for the actual interview. A 60-minute
stage therefore targets 60 questions; three such stages target 180. Add multiple
follow-ups per question. Follow-ups and superficial rewordings do not count as
new primary questions. Cover quick fundamentals and long scenarios separately.

Provide a spread of difficulty 1–5 within each stage, including independently
usable easy fundamentals and harder variants; do not mark the whole bank level 3.
Include all applicable families across the ladder, with several variants per
family and a reason for omitted families in coverage_gaps. Keep technical stages
predominantly grounded in the posting's technical requirements. General interview
patterns supplement company/role research; research accessible employer reports
for additional patterns, with dates and role context. A partial packet can be
saved with explicit shortfalls, but do not present it as comprehensive. The
schema supports 1,000 primary questions; report capacity constraints honestly.

## Running varied sessions

Set optional `depends_on` to stable IDs of genuine prerequisite questions in the
same stage. Keep simple follow-ups in `follow_ups`. Do not chain unrelated questions
just to force a script. Prerequisites must be active, and cycles are invalid.

The snapshot uses randomized topological ordering: prerequisites first, with
random choices among the least-practiced currently eligible questions at the
session difficulty, then easier questions before harder ones. It does
not simply shuffle the original list or always start at the first question. `selection_history` reports
recorded exposure. Use this order as the starting priority, draw a time-appropriate
subset across relevant topics and patterns, and reserve time for follow-ups. Do
not work down the same original list every session. Vary scenarios and probe paths;
retain the source question ID when changing delivery, and use an empty question ID
only for truly spontaneous questions. Explicit user requests to revisit a question
or weakness override novelty. After the bank is exhausted, revisiting is expected.

Respect the pinned stage, difficulty_progression and personality. Start each
session with an easy warm-up, then build toward its saved level. Automatic levels
start at 2 and rise after every two completed practices for that job/stage; the
repository pins the level, so do not recompute it during a resumed session. Introductory levels use gentler
probes; harder sessions increase ambiguity, speed and pushback. Cover pressure
families across sessions, not by turning every question into a confrontation.
Answer clarification requests naturally. Do not reveal the hidden test or criteria
before the response in non-coaching mode; explain the pattern and handling in
feedback afterward. Never treat silence, an interruption or a skeptical tone as
proof the applicant is wrong. Do not claim to measure timing or voice behaviors
that the harness cannot observe. Stop when asked.
