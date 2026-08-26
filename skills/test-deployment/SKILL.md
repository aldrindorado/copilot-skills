---
name: test-deployment
description: Verify that one or more approved, merged GitHub pull requests have reached their user-specified production websites. Use when asked to test, validate, or confirm production deployments from PRs.
---

Validate production deployments using merged GitHub pull requests as release
contracts and browser-visible evidence as deployment proof. Do not claim a
deployment succeeded when the available evidence cannot prove it.

## Required inputs

Gather these inputs one at a time with `ask_user`:

1. Ask for the GitHub pull-request number(s) or URL(s) if none were supplied.
   Accept a comma-separated or newline-separated list and normalize it into
   unique PR references.
2. Validate every PR before asking for production URLs. Each must be merged and
   approved. Retain a failed PR in the final report but exclude it from browser
   testing.
3. Ask for the production website URL(s) if none were supplied. Require full
   `https://` URLs and normalize them into unique URLs. Do not infer production
   hosts from branch names, staging hosts, or repository configuration.
4. When more than one PR or production URL is supplied, ask for the explicit
   PR-to-URL mapping unless the user already supplied it. Do not pair inputs by
   position or assume every PR belongs on every website. A PR can map to one or
   more URLs, and a URL can map to one or more PRs.
5. If a mapped PR change does not supply a clear browser-observable expected
   result, ask for one production user journey and its expected outcome. Ask
   only after inspecting that PR, so the request can name the relevant page or
   feature.

Use a normalized validation matrix for all subsequent work:

| PR | Production URL | Expected behavior | Release gate | Validation status |
| --- | --- | --- | --- | --- |

Each PR-to-URL pair is a separate validation target. Avoid duplicate browser
tests only when the same target and expected behavior are identical.

## Pull-request release gate

Use `gh` to retrieve the details and changed file list for every PR. For
example:

```powershell
gh pr view <number-or-url> --json number,url,state,mergedAt,reviewDecision,mergeCommit,baseRefName,headRefName,title,files
```

Each PR passes this gate only when:

- `state` is `MERGED`;
- `mergedAt` is populated;
- `reviewDecision` is `APPROVED`; and
- a merge commit is available.

If a PR fails any condition, report the unmet condition. Do not inspect any
website for that PR and do not describe it as production-ready. Continue with
other independent PRs that pass the gate.

When `reviewDecision` is unavailable or ambiguous, obtain the reviews with:

```powershell
gh api "repos/<owner>/<repo>/pulls/<number>/reviews?per_page=100"
```

Determine the latest submitted review state for each reviewer. Require at
least one current `APPROVED` review and no later `CHANGES_REQUESTED` review
from that reviewer. If the review state is still ambiguous, mark that PR as
not validated, explain that approval could not be established, and continue
with other independent PRs.

## Build a validation plan from the PR

For each PR that passes the release gate, inspect its changed files and diff
before browser testing:

```powershell
gh pr diff <number-or-url> --name-only
gh pr diff <number-or-url>
```

Classify each changed file:

| Change type | Required evidence |
| --- | --- |
| Public static asset (CSS, JavaScript, image, downloadable file) | Load the production asset or its consuming page and verify its expected new content or behavior. |
| WebForms page/module/template | Exercise the rendered production page and verify the changed user-visible behavior. |
| Server-side application code/configuration | Exercise a production user journey that executes the changed path and verify the expected result. A source file alone cannot be compared directly with production. |
| Build artifact, assembly, or infrastructure file | Verify the relevant runtime behavior or deployment health endpoint. If no observable check exists, report this limitation rather than claiming file-level deployment. |

Do not validate unrelated pages or files. For every changed file in each mapped
PR-to-URL target, record either:

- direct deployment evidence;
- runtime evidence that covers the file's behavior; or
- an explicit limitation explaining why the file cannot be verified externally.

If the diff alters production behavior but does not make the expected outcome
clear, ask the user for the expected production result before continuing.

## Production validation

Use Playwright for all browser testing. For each release-gated PR-to-URL target,
navigate to the mapped production URL, inspect the page, and execute the
minimal user journey that covers the changed behavior. Use browser
snapshots/evaluation rather than screenshots as the primary evidence.

For static files, where a stable changed string, selector, asset URL, or
response property exists, verify it directly. For application code, verify the
user-visible result rather than attempting to infer a server binary version.

Use production-safe test data only:

- Never submit orders, payments, bookings, destructive forms, or administrative
  mutations.
- Do not expose secrets, tokens, personal data, or session contents.
- Prefer read-only flows and reversible interactions.
- Stop immediately if the only available validation would cause a production
  mutation, then report the limitation.
- Use Tireweb-recognized test contact data when a form requires input. For
  email fields, default to `adorado@tireweb.com`. For other required fields,
  use obviously synthetic values (e.g., "Test User", "123 Test St") and pause
  before submission unless the user has explicitly approved it.

### Playwright execution guidance

Use Playwright (`playwright-browser_*`) for all browser-based validation:

- Navigate directly to the mapped production URL rather than traversing global
  navigation flows.
- Disable CSS animations and transitions immediately after navigation unless the
  scenario verifies motion or timing behavior.
- Inspect only the target element or container with
  `playwright-browser_evaluate` or a targeted snapshot; do not capture the
  full-page DOM or scan all elements by default.
- For multi-step journeys, batch route setup, navigation, interactions, and
  waits with `playwright-browser_run_code_unsafe`.
- For functional or form validation, block image, font, media, and analytics
  requests only when they are not part of the scenario. Do not block resources
  for visual or static-asset validation.
- Use `playwright-browser_wait_for` with explicit UI or network conditions
  instead of arbitrary delays, and do not retry after a timed-out condition.
- Prefer `playwright-browser_fill_form` for ordinary field entry. Use
  `playwright-browser_type` only when the scenario needs keyboard events, such
  as per-character autocomplete behavior.
- When validating analytics or `dataLayer` behavior that can precede navigation,
  attach the event listener before the triggering action and capture the result
  in the same script to avoid losing it as the page unloads. Record event
  counts, relevant field presence, and a representative payload as evidence.
- Inspect console output only at `warning` or `error` level. Inspect network
  activity only for `4xx` or `5xx` failures, and omit request or response
  payloads unless diagnosing an error.
- Do not take screenshots unless verifying an explicit layout requirement or
  documenting a visual failure.
- If a validation involves checking a freshly deployed static asset, hard-refresh
  with cache bypass (`Ctrl+F5` or `f` and `Shift` reload), or use a timestamp
  query parameter when loading the direct asset URL, before asserting its
  content.

On a Playwright initialization or tool failure, retry once. If it still fails,
report the exact blocked validation rather than switching tools silently.

## Result format

Report a concise deployment result with:

1. A validation matrix for every mapped PR-to-production-URL target: PR,
   production URL, changed file or behavior, validation performed, result, and
   evidence/limitation.
2. A final status for each PR-to-URL target:
   - **Validated deployed** — every changed behavior has direct or runtime
     production evidence.
   - **Partially validated** — one or more files cannot be externally proven;
     list the limitations.
   - **Not validated** — the PR failed the release gate, the production target
     was inaccessible, or the expected behavior was not observed.
3. An overall result:
   - **Validated deployed** only if every mapped target is validated deployed.
   - **Partially validated** if at least one mapped target is partial and none
     are not validated.
   - **Not validated** if any supplied PR fails its release gate or any mapped
     target is not validated.

Report each browser-tested target as a compact status block when appropriate:

`Status: Pass/Fail | Target URL: <URL> | Failing Selectors/Errors: <details or none>`

Never equate a successful HTTP response, a loaded home page, or a merged PR
with confirmation that the change was deployed. State the exact evidence that
supports the conclusion.

## JIRA ticket comment automation

After reporting the validation result, if **all** mapped PR-to-URL targets are
**Validated deployed**, attempt to post the validation matrix as a comment on
the linked JIRA ticket.

### Finding the JIRA ticket

1. If the user provided a JIRA ticket URL or key (e.g., `BP-183` or
   `https://ezytiretrial.atlassian.net/browse/BP-183`), use it directly.
2. Otherwise, inspect the merged PR for JIRA references in:
   - the PR title;
   - the PR body/description;
   - branch names (`headRefName` or `baseRefName`); and
   - commit messages in the merge commit.
3. Normalize any found reference into an issue key (e.g., `BP-183`).

### Posting the comment

Use the JIRA tool `JIRA-addCommentToJiraIssue` with `contentFormat: markdown`.
The comment must include:

- the release-gate result;
- the full validation matrix; and
- the overall **Validated deployed** conclusion.

Only post the comment when every supplied PR passed its release gate and every
mapped target is **Validated deployed**. If any target is **Partially
validated** or **Not validated**, do not auto-post; instead, ask the user
whether they still want a comment added to the ticket.

If no JIRA ticket can be identified, skip this step and report that no linked
ticket was found.
