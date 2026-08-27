---
name: triad-workflow-orchestrator
description: Orchestrates Ezytire delivery through Dev, Deployment, and QA with immutable releases and activation gates.
---

# Triad workflow

Use this workflow for Ezytire changes that require staging deployment and QA.
The main session orchestrates; Dev implements; Deployment uploads; QA verifies.

Read `asset-manifest.schema.json` before accepting a Dev manifest or starting
Deployment. `Old-SKILL - Copy.md` is an archive, not an active runbook.

## Non-negotiables

- **Main never edits source.** Route every fix to Dev.
- Use at most **three functional loops**: Dev -> Deploy -> Activation -> QA.
  An activation failure does not consume a loop.
- Name sessions `Dev - <branch>`, `Deployment - <branch>`, and `QA - <branch>`.
  Use `<Role> Recovery - <branch>` only for a failed kickoff.
- New-session models: Dev and Deployment use `gpt-5.6-terra` at `medium`;
  QA uses `kimi-k2.7-code` with no reasoning-effort override; other roles use
  `auto` with no reasoning-effort override. Never set `agent: "auto"`.
- Create triad sessions with `notify_on_idle: "always"`. Idle status is never
  completion evidence.
- QA must invoke `dev-testing` before browser or staging validation and apply
  its applicable guidance throughout the QA session.

## 1. Prepare in Main

1. Ask once for the staging directory and every QA URL. Reuse supplied values.
   QA must cover every applicable supplied URL.
2. Use `grill-me` when available; otherwise make a normal plan. Record target
   files, expected behavior, validation, release scope, and the staging
   observable that proves activation.
3. Record the release ref, local `HEAD`, `origin/<release-ref>`, and merge
   base when they differ. State the intended candidate SHA in the Dev handoff.
4. For browser-served assets, trace source registration and the current staging
   DOM URL before Dev starts.
5. Find branch-matching existing triad sessions. Reuse only reachable sessions
   with valid callbacks; never reuse a failed kickoff or another branch's role.
6. Before the Dev handoff, decide how every compiled or generated runtime
   artifact will be produced: a policy-allowed build or an existing immutable
   artifact from the release tree. Deployment must never discover build-tool,
   configuration-access, or artifact-source constraints for the first time.

## 2. Hand off to Dev

Dev must ACK the parent with role, session ID, phase, and assigned release SHA
before starting work. The assignment must include the parent ID, candidate SHA,
target files, C# 5 constraints where applicable, smallest validation command,
and required callback format.

Dev must:

1. Make all source changes, validate the smallest affected project, commit, and
   publish the exact release commit.
2. For a changed `Web\App_Modules\*.ascx.cs` referenced by `Src=`, trace the
   directive and compile the code-behind against the runtime .NET framework and
   `Web\Bin` references. `Sites.csproj` does not validate these controls.
3. For a source change outside the staging upload root, include its required
   compiled artifact or configuration asset in the manifest. Never deploy
   unmapped source in place of the runtime artifact.
4. Assemble the complete runtime dependency closure before the first manifest:
   static assets, compiled selectors, dynamically compiled control source, and
   every configuration or assembly required to activate the release. Do not
   defer an activation repair merely because a dependency is unchanged in the
   source diff.
5. Validate each manifest asset against the deployment tool's upload `LocalRoot`
   before handoff. A generated web-runtime artifact must be materialized at its
   real deployable path (for example, `Web\Bin\...`), not at its build-output
   path outside the upload root.
6. Send a completion callback containing changed files, validation, risk,
   release ref/SHA, diff from candidate, runtime fingerprint, artifact-production
   strategy, and exactly one manifest that validates against
   `asset-manifest.schema.json`.

Main must persist that unchanged manifest at a durable session-artifact path
and independently verify the release ref, release tree, manifest paths,
raw Git-blob hashes, runtime mappings, and dynamic-control compile result.
Reject an incomplete handoff before Deployment starts.
On Windows, calculate release hashes from binary `git cat-file blob` output,
never from a text-normalized checkout. Every activation dependency must also
appear as a complete manifest asset.
This release-assembly gate must prove that the manifest contains the complete
runtime closure before its first preview; later activation repairs are new
Dev-owned releases, not ad hoc Deployment additions.

## 3. Deploy the immutable release

Deployment must ACK before work and deploy only from the Dev-reported SHA:

1. Fetch the release ref and confirm it resolves to the manifest SHA.
2. Create a clean detached worktree at that SHA without modifying a dirty
   workspace. On Windows, use a shared worktree command that sets
   `core.autocrlf=false` for the operation, then verify raw Git-blob bytes
   against every manifest asset before preview.
3. Use `staging-deployment` with the durable manifest and
   `-DeploymentManifestPath` for both preview and approved upload.
4. Present one structured preview gate containing the release SHA, manifest
   identity, upload paths, runtime mappings, local hashes, and activation URL;
   obtain explicit upload confirmation for that exact unchanged manifest.
5. Report preview start/end, upload start/end, uploaded paths, remote target,
   SHA, local hashes, remote verification, and cleanup to Main. Distinguish
   transfer duration from preflight, approval, activation, and coordination
   delays.

Every follow-up commit is a new release. Rebuild its manifest from that exact
SHA. Never use uncommitted discovery, `-IncludePaths`, or `-ChangeScope Branch`
as an authoritative committed-release fallback.

## 4. Prove activation before QA

SFTP success is not activation.

- For front-end assets, inspect the live DOM URL in a fresh browser context,
  cache-bypass fetch it, and compare its hash or distinctive fingerprint to the
  manifest. If browser hashing is unavailable on HTTP, record that limitation
  and verify the cache-bypassed distinctive fingerprint.
- For server-side assets, exercise behavior that only the release can produce.
- For `ASCX Src` controls, test both the changed route and an ordinary route.
  If both render blank or omit the expected form, diagnose `LoadControl` or
  ASP.NET compilation first. Obtain ScratchPad/IIS error evidence or reproduce
  the targeted code-behind compile against release `Web\Bin` references.
- Never re-upload unchanged markup just to force recompilation. A new
  code-behind repair must return through Dev as a new commit and manifest.
- If the live DOM serves a different versioned asset, compare the source
  registration, live URL, release tree, and deployment mapping. Upload only a
  replacement manifest whose revised live-path asset exists in that release;
  otherwise block and return the missing selector, compiled artifact, or
  configuration to Dev.

Classify an activation failure as **Deployment Activation Failure**, stop
functional QA, repair the release/reference/cache problem, and rerun this gate.

## 5. QA and decision

QA uses Playwright by default and must callback with every tested staging URL,
activation evidence, PASS/FAIL per scenario, console/network evidence when
relevant, and one final verdict: `Ready` or `Not Ready`. Use Chrome DevTools
only when Playwright is unavailable or a DevTools-only capability is required.

For analytics scenarios, capture structured `window.dataLayer` evidence
(event counts, required fields, and a sample payload). When activation passes
but visible behavior differs, report the exact DOM node/text and the rendered
runtime path; helper-level evidence alone is insufficient.

For state-changing flows, submit only when staging is demonstrably safe;
otherwise report `Submit control reachable`.

- **Ready:** Main accepts the explicit QA callback, then runs final code review
  against the immutable release SHA. A blocking review finding returns through
  Dev -> Deploy -> Activation -> QA and consumes a functional loop; defer
  non-blocking findings unless the user approves another iteration.
- **Not Ready, activation failure:** fix deployment/activation, then rerun the
  activation gate.
- **Not Ready, functional failure:** send a focused defect to Dev and repeat
  the loop until QA passes or loop three fails.

## Liveness and service outages

After every active handoff, Main records role, session ID, phase, SHA, expected
callback, and schedules a liveness check within five minutes.

If the callback is absent, request a checkpoint. After a second missed check,
state the communication failure and either perform read-only verification or
create one correctly named recovery session.

For a kickoff failure or `503`:

1. Record the role, phase, SHA, and error.
2. Create at most one recovery session for that role and phase.
3. If it also fails, mark the phase infrastructure-blocked and stop automatic
   retries. Report the outage and await user direction.

Infrastructure failure never permits Main to edit source. Main may deploy only
after the user explicitly authorizes a named emergency override; preserve every
manifest, preview, confirmation, and activation requirement and report degraded
mode.

## Callback minimums

- **Dev:** ACK; final SHA/ref; manifest; validation; runtime fingerprint; diff;
  blockers.
- **Deployment:** ACK; preview; approval; uploaded paths; target; SHA; hashes;
  remote verification; cleanup.
- **QA:** ACK; activation evidence; scenarios; URLs; PASS/FAIL; final verdict.

Callbacks must be sent with `send_session_message` to the parent. A child-only
response, delivered message, stale timestamp, or idle notification is not a
handoff result.
