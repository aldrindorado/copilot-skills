---
name: qa-smoke-testing
description: Author, execute, and maintain reusable QA smoke-test scenarios for website functionality affected by a deployment. Use when QA needs to validate a Jira ticket's acceptance criteria or rerun a saved affected-feature smoke test.
---

Use this skill for Jira-driven, black-box smoke testing of an affected website
functionality after deployment. It establishes whether the supplied acceptance
criteria and expected result pass or fail; it does not prove that a specific
GitHub pull request or source-file change is deployed.

QA does not need access to the application codebase or its GitHub repository.
Store reusable scenarios in a QA-owned local Git repository, using its
`.qa/smoke-tests/` directory. Jira remains the source for the ticket,
acceptance criteria, execution evidence, and defect links.

## Required inputs

Gather missing inputs one at a time with `ask_user`:

1. Ask for the Jira ticket key and use it as the scenario reference.
2. Ask for a feature or module key. Normalize it to a kebab-case identifier,
   such as `checkout-flow`.
3. Ask for the full target URL and environment. Do not infer a production,
   staging, or test host.
4. Ask for the ticket acceptance criteria and the expected observable result.
   Keep the scope to the affected functionality; do not create a broader
   targeted-test plan.
5. Ask whether to run an existing scenario or author/update it.
6. If the QA-owned scenario repository is not already available in the current
   workspace, ask for its local path. Do not use the application codebase
   repository for scenario storage.

## Scenario storage

Store scenarios at:

```text
{qa-scenario-repository}\.qa\smoke-tests\{feature-key}.md
```

1. Check whether the scenario file exists.
2. For **Run Existing**, load the scenario and confirm that its acceptance
   criteria and expected result still match the Jira ticket. Update the
   scenario first when they differ.
3. For **Author / Update**, create or revise the scenario from the Jira
   acceptance criteria. Every step must have a user action and an observable
   expected result.
4. Save the scenario locally. Do not commit or push it unless the QA user
   explicitly asks.
5. Do not store credentials, MFA codes, personal data, session contents, or
   secrets in the scenario or its execution record.

Use this schema:

```markdown
# QA Smoke Test: {feature-key}

Jira ticket: {ticket-key}
Owner: {QA owner or team}
Applicability: {affected feature, site, and supported environments}
Last reviewed: {YYYY-MM-DD}

## Acceptance Criteria
- {ticket acceptance criterion}

## Expected Result
{single observable pass condition for the affected functionality}

## Preconditions
- {required non-sensitive test state}
- {approved test account or session, if applicable}

## Scenario
1. Action: {natural-language user action}
   Expected: {observable UI result}
2. Action: {natural-language user action}
   Expected: {observable UI result}

## Execution Record
| Executed at | Environment / URL | Tester | Outcome | Jira evidence | Defects |
| --- | --- | --- | --- | --- | --- |
| {ISO 8601 timestamp} | {target} | {tester} | Pass / Fail / Blocked | {comment or attachment link} | {linked Jira bugs or none} |
```

Keep the reusable scenario and its execution history current:

- Set `Owner`, `Applicability`, and `Last reviewed` when authoring or changing
  the scenario.
- Add an execution-record row for every run with the exact URL/environment,
  outcome, and Jira evidence.
- Update the scenario when the Jira acceptance criteria, expected result, or
  affected user journey changes. Do not overwrite prior execution evidence.

## Safe browser execution

Use Playwright (`playwright-browser_*`) for browser smoke testing:

- Navigate directly to the supplied target URL.
- Use the smallest journey that proves the acceptance criteria and expected
  result. Do not validate unrelated pages or features.
- For multi-step journeys, batch route setup, navigation, interactions, and
  waits with `playwright-browser_run_code_unsafe`.
- Disable CSS animations and transitions unless motion or timing is being
  tested.
- Wait for the observable state required by the scenario's expected result,
  such as a matching result card, success message, changed control state, or
  required network response. Do not use arbitrary delays; after a timed-out
  condition, record the blocked or failed validation instead of retrying it.
- Inspect only the target component or container with
  `playwright-browser_evaluate` or a targeted snapshot. Assert the relevant
  controls or results within that target; do not use page-wide text,
  `document.body.innerText`, broad element scans, or
  `document.querySelectorAll('*')` as passing evidence. Broader inspection is
  permitted only to diagnose a failed or blocked test, and the reason must be
  recorded.
- For functional or form testing, block image, font, media, and analytics
  requests only when they are not part of the scenario. Do not block resources
  for visual or static-asset checks.
- Prefer `playwright-browser_fill_form` for ordinary data entry. Use
  `playwright-browser_type` only when testing keyboard events, such as
  per-character autocomplete behavior.
- When analytics or `dataLayer` behavior is part of the acceptance criteria,
  attach the event listener before the triggering action and capture the
  result in the same script. Record event counts, relevant field presence, and
  a representative payload.
- Inspect console output only at `warning` or `error` level. Inspect network
  activity only for `4xx` or `5xx` failures, and omit payloads unless
  diagnosing an error.
- Take screenshots only for an explicit layout requirement or to document a
  visual failure.
- When verifying a recently deployed static asset, use cache bypass or a
  timestamp query parameter before asserting its content.
- If Playwright initialization or a required tool fails, retry once. If it
  fails again, record the blocked validation and do not silently switch tools.

## Production safety and authentication

- Prefer read-only and reversible journeys.
- Never submit orders, payments, bookings, administrative changes, or
  destructive forms.
- Use approved test accounts and `adorado@tireweb.com` for email fields.
- Pause before any production mutation unless the user explicitly approves it.
- Navigate to the login screen and pause when authentication is required.
- The QA user must enter credentials and complete MFA directly in the browser
  session. Never request, receive, store, or enter credentials or MFA codes.
- Resume only after the user confirms authentication is complete. Pause again
  if the session expires or another challenge appears.

## Results and Jira reporting

Report the outcome as a Jira-focused validation record:

| Jira ticket | Target URL / environment | Acceptance criteria | Validation performed | Outcome | Evidence or limitation |
| --- | --- | --- | --- | --- | --- |

- **Pass**: Every supplied acceptance criterion and expected result was
  observed.
- **Fail**: An observable result differs from the expected result. Create or
  link a Jira defect with reproduction steps, expected and actual results,
  target environment, and concise evidence.
- **Blocked**: Authentication, access, safe test data, or an execution error
  prevented validation. State the exact blocker.

When Jira access is available, add the matrix and final outcome as a comment on
the source ticket. Include linked defects and the execution timestamp. Do not
claim that a GitHub PR or individual source file was deployed based on this
smoke test.

For each browser-tested target, also report:

`Status: Pass/Fail/Blocked | Target URL: <URL> | Failing Selectors/Errors: <details or none>`
