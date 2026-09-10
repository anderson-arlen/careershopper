# Profile onboarding

Use this workflow when creating or substantially revising a CareerShopper profile.

1. Read the current profile and saved searches first. Do not duplicate facts.
2. Ask in coherent groups: identity/contact visibility, employment and dates,
   accomplishments, skills and technologies, projects, education or publications,
   then career preferences and dislikes.
3. Preserve date precision. Do not turn a year into an invented month or day.
4. Separate factual experience from preferences. A desired technology is not an
   experienced skill unless the user says so.
5. Batch facts by provenance. Direct answers may be confirmed; extracted facts
   remain pending even when they look plausible. Store search guidance separately
   with `profile_preferences_upsert`.
6. Keep sensitive application answers `application_only` or `private`, not
   resume-visible.
7. After profile work, read sources and existing searches. Create or revise a
   concise search strategy with `saved_search_upsert`; do not ask the user to
   translate their goals into query fields.
8. Summarize additions, uncertainties, preferences, and search-strategy changes
   before considering setup complete.

An existing Application Pipeline repository is ordinary source material, not a
special import format. Read its user-selected files with normal harness file tools,
translate supported content into CareerShopper facts, and preserve the original
file labels as provenance. Never modify that repository.
