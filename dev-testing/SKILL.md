---
name: dev-testing
description: Consolidated Ezytire developer testing, browser validation, staging verification, form-submission, and test-validation guidance. Invoke for requests involving development testing, validation, browser checks, staging verification, form testing, performance analysis, or Lighthouse.
---

Use this skill whenever the user asks to test, validate, verify, inspect browser
behavior, test a form, confirm staging behavior, perform performance analysis,
or run Lighthouse during development.

## Validation practices

- Use the smallest existing test, lint, or type-check that covers the change.
  Do not install new testing tools solely for validation.
- For data-changing SQL Server scripts, preserve and exercise the script's
  preflight validation, dry-run gate, transaction behavior, affected-row
  validation, and post-execution verification. Do not use `THROW`; scripts
  must remain compatible with legacy SQL Server.
- Report only validation that was actually performed and its concrete outcome.

## Browser testing and staging validation

Use Playwright (`playwright-browser_*`) by default for all browser-based
testing, staging verification, and automated QA.

- Navigate directly to the target URL instead of using global navigation flows.
- For functional or form validation, use `playwright-browser_run_code_unsafe` to batch
  route setup, navigation, interactions, and waits into one script. Block image,
  font, media, and analytics requests where they are not part of the scenario.
  Do not block resources for visual, performance, or asset-verification tests.
- Disable CSS animations and transitions immediately after navigation unless the
  scenario verifies motion or timing behavior.
- Wait for the observable state required by the scenario's expected result,
  such as a matching result card, success message, changed control state, or
  required network response. Do not use arbitrary delays; after a timed-out
  condition, report the blocked or failed validation instead of retrying it.
- Inspect only the target form or container with
  `playwright-browser_evaluate` or a targeted
  `playwright-browser_snapshot`. Assert the relevant controls or results within
  that target; do not use page-wide text, `document.body.innerText`, broad
  element scans, or `document.querySelectorAll('*')` as passing evidence.
  Broader inspection is permitted only to diagnose a failed or blocked test,
  and the reason must be reported.
- Prefer `playwright-browser_fill_form` for ordinary field entry. Use
  `playwright-browser_type` only when the scenario needs keyboard events, such
  as per-character autocomplete behavior.
- When analytics or `dataLayer` events can precede navigation, attach the event
  listener before the triggering action and capture the result in the same
  script to avoid losing it as the page unloads.
- Use `playwright-browser_run_code_unsafe` for multi-step browser flows or
  structured `dataLayer` capture, especially when batching avoids tool
  round-trips.
- When recording `dataLayer` evidence, provide structured results: event
  counts, relevant field presence, and a representative payload.
- Do not take screenshots unless verifying an explicit layout requirement or
  documenting a visual failure.
- Inspect console output only at `warning` or `error` level. Inspect network
  activity only for `4xx` or `5xx` failures, and omit request or response
  payloads unless diagnosing an error.
- If Playwright fails to initialize, report the failure and retry once. Do not
  silently switch tools.

Use Chrome DevTools only when Playwright is confirmed unavailable or when the
scenario specifically needs performance tracing, Lighthouse, LCP/Core Web
Vitals analysis, or JavaScript breakpoints.

When Chrome DevTools is used:

- Prefer DOM snapshots over screenshots for inspection.
- Use DOM-based locating before clicking.
- Batch related operations and form inputs where possible.
- Navigate directly to target URLs rather than through global navigation.
- Avoid unnecessary reloads; reuse the current page state.
- Use screenshots only for visual verification.
- Run Lighthouse only when the user explicitly requests it.
- Filter network requests to `4xx` and `5xx` failures, and console output to
  warnings and errors unless broader evidence is needed. Do not include request
  or response payloads unless diagnosing an error.
- Prefer a wait condition over arbitrary delays and do not poll after a timed
  out wait.
- Hard-refresh with cache bypass when verifying freshly deployed assets.
- If DevTools reports a transport or initialization failure, switch directly
  to Playwright without repeated retries.

## Form-submission safety

- Use `adorado@tireweb.com` in every email field when testing form submission.
- Never submit a production form without the user's explicit approval.

## Authenticated browser sessions

- Navigate to the login screen and pause when authentication is required.
- The user must enter credentials and complete multi-factor authentication
  directly in the same browser session. Never request, receive, store, or
  enter credentials or authentication codes.
- Continue only after the user confirms authentication is complete.
- If the session expires or another authentication challenge appears, pause
  again for the user rather than attempting to bypass it.
- Prefer a dedicated non-production test account for repeatable testing when
  one is available.

## Staging assets

For browser-served static assets deployed to staging, verify the public staging
URL with cache bypass, such as a timestamp query parameter, and compare the
response hash to the approved deployment asset when the deployment workflow
supports it. Do not treat an upload alone as browser verification.

## Validation reporting

Report browser test outcomes as a compact status block:

`Status: Pass/Fail | Target URL: <URL> | Failing Selectors/Errors: <details or none>`

Do not include step-by-step narration unless it is needed to explain a failure.
