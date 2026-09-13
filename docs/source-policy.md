# Job-source policy

Source acquisition is a replaceable edge of CareerShopper. An adapter may be
removed from an official build without changing jobs, searches, evaluations, or
application history.

## Implemented adapters

- Greenhouse public Job Board API
- Lever public Postings API
- Ashby public Job Board API
- Indeed public search page (fragile)
- LinkedIn guest job-search page (fragile)

The ATS adapters identify a board and its employer. Indeed and LinkedIn are
broad search adapters driven by saved-search criteria. Constraints that a
provider cannot express are enforced locally before AI evaluation.

## Safety contract

All adapters must:

- use normal TLS verification and an honest CareerShopper user agent;
- respect the configured minimum polling interval;
- treat HTTP 429 as a backoff instruction, including `Retry-After` when present;
- mark a source unavailable on CAPTCHA, access-denied, or authentication blocks;
- avoid proxy/IP rotation, CAPTCHA solving, credential bypass, and provider-limit
  circumvention;
- cap response size and preserve enough failure detail for the user to diagnose
  a disabled source.

Indeed uses the JobSpy-style undocumented GraphQL endpoint and published client
protocol headers; LinkedIn uses a public guest HTML endpoint. Both remain fragile.
Indeed requests only the first 100 results, ordered by relevance, without following
cursors. Diagnostics indicate whether further results were available.
LinkedIn fetches up to the source's `max_pages` setting (1–100, default 1),
filtered to jobs posted in the past 24 hours (`f_TPR=r86400`). It advances by the
actual card count, deduplicates job IDs across pages, waits three seconds between
pages, and stops on empty/repeated results or a provider error. Page size is not
assumed to be fixed. It does not bulk-fetch detail pages.
Minimum intervals are two hours for Indeed and six hours for LinkedIn. TLS checks
remain enabled; there are no login cookies, proxy rotation, or automatic block retries.
An HTTP 429, CAPTCHA, or access block updates source health and stops requests.
Each saved search uses one source and its own local-time cron or interval
schedule. Automatic searches run while the desktop app is open; an overdue
schedule runs once when the app reopens. Scheduling never overrides provider
minimum intervals or saved blocks.
Blocked sources and affected searches display a Blocked notice with Clear block.
The user can explicitly clear the saved block through the UI or `source_block_clear`.
This resets health to not checked and records the action locally. It sends no
request, enables no polling, and preserves run history, backoff, and minimum
request intervals. A later search is a separate action; automatic block retries
remain disabled.
The repository persists per-run HTTP request and response objects, bodies, and
parsing/filtering counters locally. Credential and cookie headers are redacted.
Response capture is capped at 20 MiB with explicit truncation/incomplete markers.
Provider content is untrusted data. JobSpy attribution is in assets/JobSpy-LICENSE.

For requested posting imports and refreshes, `job_posting_fetch` uses the existing
Dart HTTP client with a Chrome-style User-Agent. This header applies to posting
retrieval; search adapters retain their existing headers. The request does not
execute JavaScript or load browser cookies. Returned page text is untrusted and
must be extracted into `job_import_submit` before evaluation. Script references
to CAPTCHA libraries do not alone establish a challenge; explicit denial or
challenge text still stops retrieval. Posting fetches share saved host blocks
with availability checks, and record new blocks locally without retrying.
