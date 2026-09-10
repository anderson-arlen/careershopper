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
LinkedIn requests only the first results page and does not bulk-fetch detail pages.
Minimum intervals are two hours for Indeed and six hours for LinkedIn. TLS checks
remain enabled; there are no login cookies, proxy rotation, or automatic block retries.
An HTTP 429, CAPTCHA, or access block updates source health and stops requests.
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
