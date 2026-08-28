---
name: qa-smoke-testing
description: Author, execute, and maintain reusable QA smoke-test scenarios for website functionality affected by code changes. Use when QA needs to confirm that existing functionality still works as expected after a deployment or change.
model: kimi-k2.7-code
---

Use this skill for regression-style, black-box smoke testing of website
functionality that was affected by a deployment or code change. The goal is to
confirm that existing behavior still works as expected, not to validate a
specific Jira ticket, pull request, or source-file diff.

QA does not need access to the application codebase or its GitHub repository.
Store reusable scenarios in client directories under `.qa\smoke-tests\`.

## Initial setup

On first use, ask the QA user for a local base directory. It may be anywhere on
the user's machine; do not assume or select it. Under that base, use this
required client directory for all scenario creation, updates, and output files:

```text
{qa-base-directory}\.qa\smoke-tests\{client-name}\
```

Create the `.qa\smoke-tests\{client-name}\` directory when it does not exist.

## Required inputs

Gather missing inputs one at a time with `ask_user`:

1. On initial setup, ask for the local base directory before asking for the
   client.
2. Ask which client is being tested (for example, `Expressoil` or `Brakes Plus`).
   Use the client name exactly as it appears in the directory structure under
   `.qa\smoke-tests\`.
3. Ask for a feature or module key. Normalize it to a kebab-case identifier,
   such as `checkout-flow`.
4. Ask for the full target URL and environment. Do not infer a production,
   staging, or test host.
5. Ask for the acceptance criteria and the expected observable result for the
   affected functionality. Keep the scope to existing behavior; do not create a
   broader targeted-test plan.
6. Ask whether to run an existing scenario or author/update it.

## Scenario storage

Store scenarios at:

```text
{qa-base-directory}\.qa\smoke-tests\{client-name}\{feature-key}.md
```

Example clients: `Expressoil`, `Brakes Plus`.

1. Check whether the scenario file exists under the selected client folder.
2. For **Run Existing**, load the scenario and confirm that its acceptance
   criteria and expected result still match the requested scope. Update the
   scenario first when they differ.
3. For **Author / Update**, create or revise the scenario from the supplied
   acceptance criteria. Every step must have a user action and an observable
   expected result.
4. Save the scenario locally in the client folder. Do not commit or push it
   unless the QA user explicitly asks.
5. Do not store credentials, MFA codes, personal data, session contents, or
   secrets in the scenario or its execution record.
6. Treat its acceptance criteria, expected result, and explicitly stated
   interaction methods as the test contract.
7. Execute each named journey independently; do not use one journey's result
   as evidence for another.

Use this schema:

```markdown
# QA Smoke Test: {feature-key}

Owner: {QA owner or team}
Applicability: {affected feature, site, and supported environments}
Last reviewed: {YYYY-MM-DD}

## Acceptance Criteria
- {acceptance criterion for existing functionality}

## Expected Result
{single observable pass condition confirming existing behavior still works}

## Preconditions
- {required non-sensitive test state}
- {approved test account or session, if applicable}

## Scenario
1. Action: {natural-language user action}
   Expected: {observable UI result}
2. Action: {natural-language user action}
   Expected: {observable UI result}
```

Do not record per-run execution details in the scenario file. Execution records
and supporting evidence are written to the client `output` folder only.

## Test-output storage

Write each execution record and supporting evidence as a `.docx` document in
the client-specific output folder, not in the scenario markdown file:

```text
{qa-base-directory}\.qa\smoke-tests\{client-name}\output\
```

1. After each run, write the validation record and any supporting evidence to
   the client `output` folder.
2. Name output files with a timestamp and feature key so runs are easy to trace,
   for example `{feature-key}-{YYYY-MM-DDTHH-mm-ss}.docx`.
3. Do not store credentials, MFA codes, personal data, session contents, or
   secrets in output files.
4. Format DOCX records vertically with headings and paragraphs; do not use wide
   summary tables.

Keep the reusable scenario and its execution history current:

- Set `Owner`, `Applicability`, and `Last reviewed` when authoring or changing
  the scenario.
- Use the scenario file only for the reusable test definition. Move per-run
  results, evidence, and matrices to the client `output` folder.
- Update the scenario when the acceptance criteria, expected result, or affected
  user journey changes. Do not overwrite prior execution evidence in output
  files.

## Safe browser execution

Use Playwright (`playwright-browser_*`) for browser smoke testing:

- Navigate directly to the supplied target URL.
- Use the smallest journey that proves the acceptance criteria and expected
  result. Do not validate unrelated pages or features.
- Follow the scenario's stated journey and expected result. Where no interaction
  method is specified, use an equivalent safe interaction to complete the step.
- Preserve an explicitly stated method or control. For example, a required
  click must be a click on that control, not keyboard navigation. Mark the
  scenario **Blocked** if an explicit method cannot be performed.
- For multi-step journeys, batch route setup, navigation, interactions, and
  waits with `playwright-browser_run_code_unsafe`.
- Disable CSS animations and transitions unless motion or timing is being
  tested.
- Before triggering an action, inspect the target component and capture the
  relevant baseline. Do not assume its result selectors or markup.
- Wait for the expected post-action state within that component. For dynamic
  results, assert a changed result or required content, not merely that a
  container exists or that pre-existing content is present. Do not use
  arbitrary delays.
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
- Before reporting **Fail**, inspect the target component after the failed
  assertion; a missing assumed selector alone is not failure evidence.
- Retry each failed journey once from its preconditions. Report both attempts
  and use **Pass after retry** only if retry passes.

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

## Results and reporting

Report the outcome as a vertical validation record:

```text
# QA Smoke Test Validation Record

Execution timestamp: {ISO 8601 timestamp}
Client: {client-name}
Feature: {feature-key}
Target URL / environment: {target}

## Acceptance Criteria
- {criterion}

## Expected Result
{expected result}

## Journey: {journey name}
Validation performed: {actions taken}
Outcome: Pass / Fail / Blocked
Evidence or limitation: {concise evidence}

## Overall Outcome
Pass / Pass after retry / Fail / Blocked

## Status
Status: Pass/Fail/Blocked | Client: {client-name} | Target URL: {target} | Failing Selectors/Errors: {details or none}
```

- **Pass**: Every supplied acceptance criterion and expected result was
  observed.
- **Fail**: An observable result differs from the expected result. Create or
  link a defect with reproduction steps, expected and actual results, target
  environment, and concise evidence.
- **Blocked**: Authentication, access, safe test data, or an execution error
  prevented validation. State the exact blocker.
- Use one **Journey** section for each named journey. Include any equivalent
  interaction and both retry outcomes in that journey's section.

Persist the report and any evidence to the client output folder:

```text
{qa-base-directory}\.qa\smoke-tests\{client-name}\output\{feature-key}-{timestamp}.docx
```

When issue-tracking access is available, add the validation record and final outcome as a
comment on the relevant ticket. Include linked defects and the execution
timestamp. Do not claim that a GitHub PR or individual source file was deployed
based on this smoke test.

For each browser-tested target, also report:

`Status: Pass/Fail/Blocked | Client: {client-name} | Target URL: <URL> | Failing Selectors/Errors: <details or none>`
