---
name: test-staging
description: Deploy uncommitted Ezytire web changes from the main session's local branch checkout, then verify them on staging through Deployment and QA nested sessions.
---

Use this skill after the user finishes coding with the main session and wants
the current uncommitted web changes deployed and verified on staging. It is the
deployment-and-QA portion of `triad-workflow-orchestrator`, adapted for a main
session that is the user's co-developer.

## Goal

Coordinate delivery through two nested sessions:

1. **Deployment manager** - previews and uploads the uncommitted web changes
   from the main session's local branch checkout using `staging-deployment`.
2. **QA tester** - proves staging serves the uploaded files, then verifies the
   requested behavior.

The main session is the only development surface. It owns the local branch
checkout, changed files, working-tree manifest, runtime mapping, and
user-guided remediation. Never create a Dev nested session under this skill.

## Required startup inputs

Before deployment begins, obtain:

1. the main session's absolute local branch checkout path;
2. staging deployment directory, such as `EOSB-757` or `/EOSB-757`;
3. one or more staging URLs for QA.

Do not ask again for values already supplied in the current workflow. Preserve
every staging URL and require QA to cover every applicable target.

The main session must also record:

- the task objective and observable acceptance scenarios;
- the current branch name;
- the full list of intended uncommitted web files; and
- each changed front-end file's runtime URL/version mapping and distinctive
  fingerprint.

This workflow intentionally deploys from the main session's **uncommitted**
local branch checkout. Do not require a commit, release ref, push, fetch,
cherry-pick, stash, or a separate release worktree.

## Session bootstrap

### Naming and reuse

All nested sessions must include the current branch name:

- `Deployment - <branch-name>`
- `QA - <branch-name>`
- replacements: `<Role> Recovery - <branch-name>`

Before creating a session, search existing sessions for the corresponding name
case-insensitively. Reuse only an active or reachable matching session. Never
reuse a session whose name does not include the current branch name. If a
session worktree's kickoff failed, create the matching Recovery session.

### Nested-session model policy

Every new nested session created by this skill must use `auto` with no explicit
reasoning-effort override. Do not set `agent: "auto"`; omit `agent` to use the
default agent.

### Main-session development ownership

Every code change is made collaboratively by the user and main session in the
main session's existing local branch checkout. Deployment and QA must not:

- edit source files, refactor code, build substitute assets, or alter Git
  state;
- deploy from their own worktree, current directory, branch, or a detached
  checkout; or
- push, fetch, merge, rebase, cherry-pick, reset, stash, or commit.

The Deployment session may read the main session's supplied local checkout path
only to preview, hash, and upload the intended files. It must pass that path as
`-RepositoryRoot`; it is never allowed to substitute its own worktree. The
main source checkout must remain unchanged from manifest validation through
the actual upload.

## Working-tree deployment handoff

Before authorizing Deployment, main must inspect the supplied local checkout
and create exactly one valid `json` fenced **Working-Tree Deployment Manifest**.
The manifest is the authoritative file scope. Markdown lists, tables, or prose
must not add or override entries.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Test staging working-tree deployment manifest",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "source_root", "branch", "files"],
  "properties": {
    "schema_version": {
      "const": "1.0"
    },
    "source_root": {
      "type": "string",
      "minLength": 1
    },
    "branch": {
      "type": "string",
      "minLength": 1
    },
    "files": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "asset_type",
          "repository_source_path",
          "staging_relative_path",
          "sha256",
          "runtime_fingerprint",
          "runtime_mapping"
        ],
        "properties": {
          "asset_type": {
            "enum": ["frontend", "server-side", "compiled", "configuration"]
          },
          "repository_source_path": {
            "type": "string",
            "pattern": "^Tireweb Sites/Web/.+"
          },
          "staging_relative_path": {
            "type": "string",
            "pattern": "^[^/].*"
          },
          "sha256": {
            "type": "string",
            "pattern": "^[a-f0-9]{64}$"
          },
          "runtime_fingerprint": {
            "type": "string",
            "minLength": 1
          },
          "runtime_mapping": {
            "type": ["object", "null"],
            "additionalProperties": false,
            "required": [
              "expected_runtime_url_or_versioned_filename",
              "source_registration_or_resolution_evidence"
            ],
            "properties": {
              "expected_runtime_url_or_versioned_filename": {
                "type": "string",
                "minLength": 1
              },
              "source_registration_or_resolution_evidence": {
                "type": "string",
                "minLength": 1
              }
            }
          }
        },
        "allOf": [
          {
            "if": {
              "properties": {
                "asset_type": {
                  "const": "frontend"
                }
              }
            },
            "then": {
              "properties": {
                "runtime_mapping": {
                  "type": "object"
                }
              }
            }
          }
        ]
      }
    }
  }
}
```

Main must validate the manifest before handoff:

1. `source_root` exactly matches the main session's local checkout path.
2. `branch` matches that checkout's current branch.
3. Each source path appears as an added, modified, or untracked file in that
   checkout and exists beneath `Tireweb Sites\Web`.
4. Each `staging_relative_path` matches the source path relative to
   `Tireweb Sites\Web`.
5. Each SHA-256 is calculated from the current file in the supplied source
   root and each file contains its declared runtime fingerprint.
6. Front-end files have a non-null runtime mapping. Files must not duplicate a
   repository source path or staging-relative path.

Deleted, renamed, or non-web source changes cannot be deployed by this workflow
without an explicit user decision about the required build or deployment
artifact. Do not infer a replacement asset.

## Deployment phase

Main instructs Deployment to use `staging-deployment` in parent-authorized
autopilot mode. It provides the main local checkout path, staging directory,
and the exact manifest JSON.

Deployment must:

1. use exactly two PowerShell invocations for a normal successful deployment:
   one combined preflight-and-preview invocation and one combined
   revalidation-and-upload invocation. Do not run individual manifest checks,
   root-setting commands, or hash checks as separate exploratory commands.
   Never repeat a successful command merely to collect missing evidence.
2. run the combined preflight-and-preview invocation with
   `$ErrorActionPreference = 'Stop'`. In that invocation:
   - verify `source_root` exists and is not its own worktree;
   - validate the manifest, changed-file status snapshot, web-root path, and
    SHA-256/fingerprint of every manifest entry;
   - reject a source checkout whose complete changed web-file set differs from
    the manifest;
   - call `Set-StagingDeploymentRemoteRoot` once with the parent-selected
    staging directory; and
   - preview the supplied main-session checkout with `-IncludePaths` containing
    exactly every `repository_source_path` from the manifest.
    `Deploy-Staging.ps1` defaults to `-ChangeScope Uncommitted`, so do not add
    a branch scope:

   ```powershell
   $sourceRoot = '<main-session-local-branch-checkout>'
   $includePaths = @('<manifest-repository-source-paths>')
   & "$HOME\.copilot\skills\staging-deployment\Deploy-Staging.ps1" -RepositoryRoot $sourceRoot -RemoteRoot $remoteRoot -IncludePaths $includePaths -WhatIf
   ```

3. confirm from that one preview output that it selects exactly the manifest
   files and maps each to the declared staging-relative path.
4. run the combined revalidation-and-upload invocation immediately after the
   successful preview. It must recompute the complete changed web-file set and
   every manifest hash, blocking upload if either differs from the preflight,
   then upload the same source checkout with the same exact `-IncludePaths`:

   ```powershell
   & "$HOME\.copilot\skills\staging-deployment\Deploy-Staging.ps1" -RepositoryRoot $sourceRoot -RemoteRoot $remoteRoot -IncludePaths $includePaths
   ```

5. retry only after a failed invocation and an identified correction. Do not
   retry on a successful preflight, preview, hash check, or upload.

Deployment reports the uploaded files, remote target, source-root path, and
the hashes used for upload. If the source root, status, preview scope, path, or
hash differs, Deployment is blocked. It must not upload a substitute branch,
working tree, revision, or similarly named asset.

## Staging activation gate

An SFTP upload is not proof that staging serves the changed file. Functional QA
starts only after QA, or a dedicated verification session, proves each changed
runtime asset is active.

For every changed front-end asset:

1. load the affected staging page in a fresh browser context and inspect the
   actual `<script>` or `<link>` URL;
2. fetch that exact URL with a cache-bypassing unique query parameter and
   `cache: 'no-store'` when available;
3. compare the fetched content with the manifest SHA-256 or distinctive runtime
   fingerprint; and
4. record the URL, expected and observed hash/fingerprint, and cache-bypass
   method.

On HTTP staging, browser `crypto.subtle` may be unavailable. A cache-bypassed
fetch of the exact active asset URL plus a verified runtime fingerprint is
sufficient. Record the limitation; do not classify it alone as an activation
failure.

For server-side changes, exercise an observable response or behavior that only
the uploaded working-tree file can produce.

If activation fails, classify it as a **Deployment Activation Failure**. Do
not claim functional QA was performed. Return the evidence to main, which must
investigate runtime references, compiled artifact boundaries, selectors, module
variants, upload paths, and cache/CDN behavior. Main must update the current
working-tree manifest, rerun the preview, and upload only the corrected
working-tree file scope. Do not deploy a similarly named client asset as a
substitute.

## QA phase

After activation passes, main instructs QA to verify every supplied staging URL
against the acceptance scenarios from the completed coding work. QA uses
Playwright by default:

- use `playwright-browser_navigate` and `playwright-browser_evaluate` for page
  and `dataLayer` inspection;
- use `playwright-browser_click` for user interactions;
- use `playwright-browser_run_code_unsafe` for complex structured evidence;
- use Chrome DevTools only if Playwright is unavailable or a DevTools-only
  feature is required; and
- if DevTools reports `Transport closed` or an initialization failure, switch
  immediately to Playwright rather than retrying DevTools.

QA must report:

- PASS or FAIL for each scenario and staging URL;
- activation-gate evidence for every changed runtime asset;
- structured `dataLayer` evidence where relevant, including event counts,
  field-presence checks, and a sample payload;
- pertinent network and console evidence;
- the exact DOM text/node and runtime render path when visible behavior
  contradicts the uploaded source; and
- a final binary verdict: `Ready` or `Not Ready`.

When a submit action would change state, submit only if the staging flow is
demonstrably test-safe. Otherwise, report `Submit control reachable` rather
than an end-to-end submission.

## Outcome and remediation

- If QA is `Ready`, main reports the deployed working-tree scope, activation
  evidence, and QA verdict to the user.
- If QA is `Not Ready`, QA returns reproducible defect evidence to main. Main
  collaborates with the user to change the local branch checkout, regenerates
  the manifest, then starts another deployment attempt.
- If activation failed, main fixes the runtime/deployment issue and reruns the
  activation gate before functional QA; it does not count as a functional
  attempt.

Limit a single release objective to three functional QA attempts. Do not
continue automatically after the third `Not Ready` verdict; report the
unresolved evidence and wait for user direction.

## Message templates

### Main -> Deployment

Include:

- absolute main-session local checkout path and staging directory;
- parent authorization for `staging-deployment` autopilot mode;
- instruction to use the supplied path as `-RepositoryRoot`, not the
  Deployment session's own checkout;
- the exact mandatory working-tree manifest JSON below, populated from the
  main handoff and validated before previewing or uploading:

```json
{
  "schema_version": "1.0",
  "source_root": "<absolute-main-session-local-branch-checkout>",
  "branch": "<branch-name>",
  "files": [
    {
      "asset_type": "frontend",
      "repository_source_path": "Tireweb Sites/Web/<repository-path>",
      "staging_relative_path": "<path-relative-to-web-root>",
      "sha256": "<64-character-lowercase-sha256>",
      "runtime_fingerprint": "<distinctive-runtime-fingerprint>",
      "runtime_mapping": {
        "expected_runtime_url_or_versioned_filename": "<runtime-url-or-versioned-filename>",
        "source_registration_or_resolution_evidence": "<source-registration-or-runtime-resolution-evidence>"
      }
    }
  ]
}
```

- requirement to reject manifest, status, hash, source-root, or preview-scope
  mismatches;
- requirement to perform the parent-pinned two-command deployment contract:
  one combined preflight-and-preview invocation and one combined
  revalidation-and-upload invocation, both using exact manifest
  `-IncludePaths`; and
- required report: uploaded files, target path, source root, and local hashes.

### Main -> QA

Include:

- every staging URL in scope;
- the working-tree manifest JSON, runtime fingerprints, and affected page URLs;
- activation-gate requirement to inspect actual DOM asset URLs and compare
  cache-bypassed fetched content to the manifest before functional testing;
- exact acceptance scenarios;
- evidence format: per-scenario PASS/FAIL, structured `dataLayer` evidence,
  relevant network/console output, and `Ready`/`Not Ready`;
- Playwright-first tooling instruction; and
- requirement to stop at the submit control when submission is not test-safe.

## Safety checks

- Never create a Dev nested session in this workflow.
- Never require or perform a commit, push, fetch, merge, rebase, cherry-pick,
  reset, checkout, or stash for the main session's local branch.
- Never deploy from the Deployment session's worktree; always use the supplied
  main-session local checkout path.
- Never deploy deleted, renamed, non-web, inferred, or substitute files without
  an explicit user decision and an updated manifest.
- Never deploy without a successful preview, exact scope comparison, and
  immediately preceding hash recheck.
- Never split a normal deployment into separate exploratory validation commands
  or rerun a successful command.
- Never begin functional QA until the staging activation gate passes.
- Never allow Deployment or QA to modify source code.
- Never claim a failed or blocked deployment was functionally tested.
