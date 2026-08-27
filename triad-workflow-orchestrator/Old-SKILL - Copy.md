---
name: triad-workflow-orchestrator
description: Orchestrates task delivery with nested Dev, Deployment, and QA sessions, with iterative fix/deploy/verify loop and final review gate.
---

Use this skill to run a repeatable multi-agent workflow for Ezytire tasks without relying on custom prompts.

## Goal

Coordinate development through three initial nested sessions:

1. **Developer agent** — implements code changes
2. **Deployment manager** — deploys to staging using `staging-deployment` skill
3. **QA tester** — verifies on staging URL

The main session remains the orchestrator and can create additional nested sessions as needed.

## Required startup questions (ask in main session)

Ask these before any implementation starts:

1. Staging deployment directory (examples: `EOSB-757` or `/EOSB-757`)
2. One or more staging URLs for QA verification (example: `http://eosb-757.tireco-op.com`)

Do not ask again for a value the user already supplied. Store every supplied
staging URL and require QA to cover each applicable target in deployment + QA
messages.

## Build validation policy

Never run MSBuild against the full Ezytire solution:

```powershell
msbuild "Tireweb Sites\Tireweb Sites.sln"
```

Dev must select the smallest existing build or test target that covers the
changed project:

- For `Customization\` changes, use `Customization\Customization.sln`.
- For `Tireweb Sites\Sites\` changes, use `Tireweb Sites\Sites\Sites.csproj`.
- For other changes, use the owning project file, subsystem solution, or a
  narrower existing test command.

Do not build unrelated projects merely because they are referenced by the
full solution. If the targeted build is blocked by a pre-existing dependency
or environment problem, report that exact blocker and continue with the
remaining appropriate validation; do not escalate to the full solution build.

### Dynamic Web Forms control validation

`Tireweb Sites\Web\App_Modules\**\*.ascx.cs` files that are referenced by an
ASCX `Src` directive are compiled by ASP.NET at runtime. They are not compiled
by `Tireweb Sites\Sites\Sites.csproj`; a successful Sites build therefore does
not validate those controls.

For every changed runtime-compiled control, Dev must:

1. Trace the ASCX directive to its code-behind and record both paths.
2. Run a targeted C# compile of that code-behind against the same .NET
   framework and `Web\Bin` assemblies used by staging. Prefer an existing
   Web Forms precompile when it covers the control; otherwise use the framework
   C# compiler to build only the code-behind as a temporary library. Resolve
   every compile error, including missing helpers and namespaces, before
   committing.
3. Report the exact command and result in the Dev callback. An unrelated
   project-build failure does not substitute for this check.
4. Classify the code-behind as a `server-side` asset in the manifest. Its
   runtime fingerprint must name the control type and the observable editor or
   response that proves ASP.NET loaded it. Include the matching ASCX or a
   compiled assembly only when the release actually changes that activation
   dependency.

## Session bootstrap

### Naming convention

All nested sessions created by the main session **must include the current working branch name** in their name, using the format:

- `Dev - <branch-name>` (code implementation)
- `Deployment - <branch-name>` (staging uploader)
- `QA - <branch-name>` (staging verification)
- Any additional nested sessions follow the same pattern: `<Role> - <branch-name>`

For example, on branch `EOSB-762`, the sessions should be named:
- `Dev - EOSB-762`
- `Deployment - EOSB-762`
- `QA - EOSB-762`

**Why this matters:** Multiple main sessions may exist across different branches. Including the branch name in each nested session's name ensures the correct main session can identify and communicate only with its own nested sessions, avoiding cross-task interference.

### Session reuse rule

Before creating new sessions, search existing sessions for names matching
`Dev - <branch-name>`, `Deployment - <branch-name>`, and `QA - <branch-name>`.
Match names case-insensitively because the session UI can normalize names to
lowercase. Reuse only an active or reachable matching session. **Never reuse a
session whose name does not include the current branch name.**

If a worktree was created but its kickoff failed, treat that session as
unusable rather than as a reusable triad member. Create a replacement named
`<Role> Recovery - <branch-name>` with a valid kickoff and track its ID in the
main session.

### Worker readiness and outage circuit breaker

A child session is usable only after it sends a separate **ACK callback** to
the parent that includes its role, session ID, assigned release SHA, and phase.
The ACK is not a completion callback. Main must schedule the first liveness
check when it hands off work and request an ACK if it has not arrived promptly.

If a `create_session` kickoff fails or returns a service error such as `503`:

1. Record the failed role, phase, release SHA, and error.
2. Create at most one correctly named `<Role> Recovery - <branch-name>` session
   for that role and phase. Never retry a failed kickoff by reusing its
   worktree or repeatedly creating indistinguishable sessions.
3. If the recovery kickoff also fails, mark that phase **infrastructure
   blocked**, stop autonomous launch retries, and report the outage to the
   user with the available options.

Infrastructure failure never authorizes the main session to edit source or
silently replace a role. Main may complete read-only investigation and
non-code verification directly. A main-session deployment is allowed only
when the user explicitly authorizes a named emergency deployment override and
the normal immutable-manifest, preview, confirmation, and activation gates
still run. Record that the triad ran in degraded mode.

### Completion callbacks and liveness

Child-session idle notifications and session metadata are not proof that a
phase completed. A child can go idle while waiting for work, and `get_session`
does not expose its final response. The main session must therefore use an
explicit callback protocol:

1. Create every new triad session with `notify_on_idle: "always"` so a
   standby idle state does not consume the only completion notification.
2. Every Dev, Deployment, and QA handoff must include the parent session ID
   and require the child to send its final structured result to that ID with
   `send_session_message`. A response visible only in the child session is
   not a handoff.
3. Main must record the awaited role, release SHA, phase, and callback
   requirements immediately after each handoff. Do not treat delivery of a
   `send_session_message` request, a stale `updated_at`, or an idle
   notification as a result.
4. Main must schedule a one-time liveness check (for example with
   `save_session_automation`) no later than five minutes after each active
   Dev, Deployment, or QA handoff. If the callback is absent, main must
   proactively request a checkpoint; it must not wait for the user to ask
   for status.
5. If a second liveness check receives no usable callback, main must state
   the child-session communication failure, then either complete the
   non-code verification directly or create a correctly named recovery
   verification session. Never infer PASS, FAIL, deployment success, or
   deployment failure from missing messages.

### Nested-session model policy

When creating a new nested session:

- **Dev** must use `gpt-5.6-terra` with `medium` reasoning effort.
- **Deployment** must use `gpt-5.6-terra` with `medium` reasoning effort.
- **QA** must use `kimi-k2.7-code` with no explicit reasoning-effort override.
- Every additional nested session must use `auto` with no explicit reasoning-effort override.

Pass these settings in the `create_session` kickoff configuration. This policy applies only to newly created sessions; existing sessions retain the model selected when they were created.

`agent` is an optional custom-agent name, not a model selector. Do **not** pass
`agent: "auto"`: omit `agent` to use the default agent. Set `model` to
`gpt-5.6-terra` for Dev and Deployment, `kimi-k2.7-code` for QA, or `auto`
for additional nested sessions. Dev and Deployment kickoffs must set
`reasoning_effort: "medium"`; QA and additional-session kickoffs must omit
`reasoning_effort`.

### Hard requirement — developer isolation

- The **main/orchestrator session must not implement code changes directly**.
- All source edits (`apply_patch`, editor changes, refactors, fixes) must be done in the **dev** nested session only.
- If the dev session does not exist yet, create it (with the correct branch-name convention) first, then send implementation instructions before any code-edit action.
- If a quick fix is discovered during deployment/QA, route it back to **dev**; do not patch from main.

### Release-lineage preflight

Before assigning Dev, main must record:

1. the intended release ref;
2. the orchestrator worktree `HEAD`;
3. `origin/<release-ref>`; and
4. their merge base when they differ.

If the local candidate and remote release ref differ, main must explicitly
declare the intended candidate SHA in the Dev assignment. Dev must begin from
that candidate or a reviewed descendant, not from the project default branch
or an inferred remote head. A remote ref resolving to a SHA is not proof that
the SHA contains the task implementation.

Do not merge divergent histories merely to make the remote ref advance. A
merge requires main approval and a post-merge tree check showing that every
required task behavior and asset is still present.

### Immutable release artifact handoff

Nested sessions normally use separate worktrees and may therefore be on different local branches. Session names do **not** prove that the same source is being deployed.

Before the first Dev handoff, main must define the release ref and use the
following **Asset Manifest JSON Schema**. After Dev commits, Dev must provide
exactly one valid `json` fenced block that validates against this schema. The
JSON block is the authoritative Dev-to-Deployment manifest; Markdown lists,
tables, or prose must not represent, add, or override manifest entries.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Triad asset manifest",
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "release_ref", "release_commit", "assets"],
  "properties": {
    "schema_version": {
      "const": "1.0"
    },
    "release_ref": {
      "type": "string",
      "minLength": 1
    },
    "release_commit": {
      "type": "string",
      "pattern": "^[a-f0-9]{40}$"
    },
    "assets": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "asset_type",
          "repository_source_path",
          "staging_upload_path",
          "sha256",
          "runtime_fingerprint",
          "runtime_mapping",
          "activation_dependencies"
        ],
        "properties": {
          "asset_type": {
            "enum": ["frontend", "server-side", "compiled", "configuration"]
          },
          "repository_source_path": {
            "type": "string",
            "minLength": 1
          },
          "staging_upload_path": {
            "type": "string",
            "minLength": 1
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
          },
          "activation_dependencies": {
            "type": "object",
            "additionalProperties": false,
            "required": ["required", "artifacts"],
            "properties": {
              "required": {
                "type": "boolean"
              },
              "artifacts": {
                "type": "array",
                "items": {
                  "type": "object",
                  "additionalProperties": false,
                  "required": [
                    "artifact_type",
                    "repository_source_path",
                    "staging_upload_path",
                    "reason"
                  ],
                  "properties": {
                    "artifact_type": {
                      "enum": [
                        "server-side-selector",
                        "compiled-artifact",
                        "module-variant",
                        "configuration"
                      ]
                    },
                    "repository_source_path": {
                      "type": "string",
                      "minLength": 1
                    },
                    "staging_upload_path": {
                      "type": "string",
                      "minLength": 1
                    },
                    "reason": {
                      "type": "string",
                      "minLength": 1
                    }
                  }
                }
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
          },
          {
            "if": {
              "properties": {
                "activation_dependencies": {
                  "properties": {
                    "required": {
                      "const": true
                    }
                  }
                }
              }
            },
            "then": {
              "properties": {
                "activation_dependencies": {
                  "properties": {
                    "artifacts": {
                      "minItems": 1
                    }
                  }
                }
              }
            },
            "else": {
              "properties": {
                "activation_dependencies": {
                  "properties": {
                    "artifacts": {
                      "maxItems": 0
                    }
                  }
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

`release_ref` is the branch/ref intended for staging and `release_commit` is
the exact immutable SHA to deploy. Each intended deployed file must appear
exactly once in `assets`; its hash must be the lowercase SHA-256 computed from
the raw Git blob at `release_commit`, not a line-ending-normalized working-tree
copy. On Windows, Dev must calculate each hash from a binary
`git cat-file blob <release_commit>:<path>` stream; do not use text
redirection, `git show` written through text APIs, or `Get-FileHash` on an
`autocrlf` checkout. Every front-end asset must have a non-null
`runtime_mapping` that identifies its actual runtime URL or versioned filename
and the source registration or runtime-resolution evidence. A non-null
activation-dependency artifact must also appear as a complete `assets` entry
with its own hash.

The Dev handoff must include the release ref. Dev must report:

1. the exact commit SHA containing the completed change;
2. whether it was published to the release ref;
3. the single schema-valid asset-manifest JSON block for every file that will
   be deployed; and
4. a content fingerprint that proves the changed runtime path is present (for example, a new helper name or exact normalized output); and
5. a diff summary from the declared candidate/baseline to the final release
   commit, including any merge rationale.
6. for every runtime-compiled ASCX code-behind, the directive-to-code-behind
   mapping and the targeted compile command and result.

When a shared release branch is required, Dev must publish its exact commit to that ref and verify the remote ref resolves to the reported SHA. A Dev worktree may keep its own branch, but it must not leave Deployment to infer, cherry-pick, or recreate the intended change.

Before Deployment begins, main must persist the exact Dev manifest JSON
unchanged at a durable session-artifact path. The same file must be available
for both Deployment preview and actual upload; do not use a one-command
temporary file that can disappear after preview.

Deployment must deploy from the reported immutable SHA, not from its own branch, a working-tree diff, or a cherry-pick. It must:

1. fetch the release ref;
2. verify `origin/<release-ref>` resolves to the Dev-reported SHA;
3. create a clean, detached temporary worktree at that SHA (use
   `core.autocrlf=false` when needed) without modifying a dirty deployment
   worktree;
4. verify that worktree's `HEAD` is the reported SHA and its raw file bytes
   match every manifest hash;
5. use `staging-deployment`'s `-DeploymentManifestPath` mode with the durable
   manifest for both preview and upload. This explicit mode selects only
   manifest assets and avoids the default uncommitted-change discovery; and
6. remove only the clean temporary release worktree after a successful upload.

If a byte-preserving release file must be materialized, copy
`git cat-file blob` output directly from its binary standard-output stream to
a `FileStream`. Do not decode/re-encode it, strip a BOM, or normalize line
endings.

If the release SHA or any file hash differs, deployment is blocked. Report the mismatch to main; do not upload a substitute build.

### Committed remediation deployment

Every follow-up commit, including a one-file server-side control repair, is a
new immutable release. Rebuild the durable manifest from the exact follow-up
SHA and use `-DeploymentManifestPath` for both preview and upload.

Do not use `-IncludePaths`, default uncommitted-file discovery, or
`-ChangeScope Branch` as a fallback for an authoritative committed release.
Those modes can reject committed files, accidentally include prior changes, or
lose the release-to-manifest lineage. If the manifest cannot be materialized
from the detached release worktree, block deployment and return the problem to
Dev.

### Main release-acceptance gate

Before authorizing Deployment, main must independently:

1. fetch the release ref and confirm it resolves to the reported SHA;
2. inspect the final release tree, not the orchestrator worktree's possibly
   stale `HEAD`;
3. confirm the manifest paths exist at that SHA and are the files that contain
   the requested behavior;
4. trace each front-end asset to its source registration and expected runtime
   URL; and
5. reject the handoff if the reported manifest names an inactive, obsolete, or
   unrelated asset.
6. for each runtime-compiled ASCX code-behind, verify the `Src` mapping and
   Dev's targeted compile result before authorizing deployment.

This is a handoff failure, not a QA failure. Return it to Dev before any
deployment starts.

## Orchestration flow

### Phase 1 — Plan in main session

1. Main session first determines whether the `grill-me` skill is available to
   the user. When it is available, invoke `grill-me` and use its questioning
   workflow to sharpen the task plan before proceeding. When it is unavailable,
   analyze the task in the default **plan mode** instead. Do not block the
   workflow solely because `grill-me` is unavailable.
2. Produce a concrete plan with:
   - target files and modules
   - expected behavior change
   - validation strategy
   - rollout/deploy scope
3. For front-end changes, perform a runtime-asset preflight before the Dev
   handoff:
   - trace the source registration for each asset;
   - inspect the current staging DOM asset URL when a staging site is
     available; and
   - document any source-to-staging version mismatch and whether it requires a
     server-side selector or compiled deployment.
4. Send the implementation plan and declared release candidate to **dev**.

### Phase 2 — Development

1. Dev session implements changes on its branch/session and publishes the exact release commit as required by the immutable release artifact handoff.
2. Dev sends the following report to main using `send_session_message`:
   - changed files
   - key logic updates
   - local validation results
   - any risk notes
   - release ref and immutable commit SHA
   - one schema-valid asset-manifest JSON block
3. Main session runs the release-acceptance gate and resolves blockers.

Development handoff is mandatory for every code-change iteration (initial work and all QA follow-up fixes).

### Phase 3 — Deployment

1. Main session instructs **deployment** session to deploy using `staging-deployment` skill.
2. Deployment session must:
   - parse and validate the immutable release commit and asset-manifest JSON
     before beginning;
   - create the clean detached release worktree and use the durable manifest
     path as described in the immutable release artifact handoff;
   - verify every front-end upload path against the manifest's expected runtime
     URL/version mapping;
   - run `-DeploymentManifestPath <manifest>` with `-WhatIf`, then run the
     identical command without `-WhatIf` after successful preview;
   - report uploaded files, remote target, deployed commit SHA, local raw-byte
     hashes, remote size verification, and temporary-worktree cleanup to main
     with `send_session_message`.

### Phase 3.5 — Staging activation gate

An SFTP upload result is not sufficient proof that a staging page serves the changed asset. Before functional QA begins, QA (or a dedicated verification session) must prove the staging URL resolves the deployed runtime assets.

For every changed front-end asset:

1. Load the affected staging page in a fresh browser context and inspect its actual `<script>`/`<link>` URL.
2. Fetch that exact URL with a cache-bypassing request (unique query parameter and `cache: 'no-store'` where available).
3. Compare the fetched content to the asset manifest using a SHA-256 hash or the distinctive runtime fingerprint.
4. Record the URL, expected and observed hash/fingerprint, and cache-bypass method.

On HTTP staging sites, browser `crypto.subtle` may be unavailable because the
page is not a secure context. In that case, a successful cache-bypassed fetch
of the exact active asset URL plus a verified distinctive runtime fingerprint
is sufficient for the activation gate. Record that browser SHA-256 was
unavailable; do not classify that limitation alone as a Deployment Activation
Failure.

For server-side changes, exercise an observable response or page behavior that can only be produced by the deployed commit.

#### Runtime-compiled control triage

For an ASCX control with a `Src` code-behind, a successful upload or a changed
compiled settings DLL does not prove that the control loaded. If the activation
gate shows a blank container, missing form, or an unchanged response:

1. Load both the changed route and an ordinary pre-existing route in fresh
   browser pages. If both fail, treat the issue as control resolution or
   runtime compilation, not as a query-string or feature-flag defect.
2. Capture the suppressed `LoadControl`/ASP.NET compiler error from
   ScratchPad, IIS/application logs, or the staging error surface. If server
   logs are unavailable, reproduce the targeted code-behind compile against
   the release `Web\Bin` references before proposing another deployment.
3. Do not upload an unchanged ASCX merely to force recompilation. Upload a
   markup file only when its directive or emitted markup changed in the
   immutable release and the manifest declares that dependency.
4. Route a compile failure back through Dev as a new commit and manifest; do
   not patch the control or invent a remediation asset from the orchestrator.

If the activation gate fails:

- classify it as **Deployment Activation Failure**, not a functional QA failure;
- do not claim the product behavior has been retested;
- stop the Dev → Deploy → QA loop and investigate versioned references, CDN/browser caches, module selection, or an incorrect asset path;
- rerun the activation gate after the deployment issue is fixed.

Only start functional QA after the activation gate passes.

#### Versioned-asset activation remediation

If the page serves a different versioned asset than the declared manifest:

1. Compare the declared source registration, the live DOM URL, the release
   tree, and the deployment mechanism. Determine whether the mismatch is a
   stale server-side selector, a compiled artifact boundary, a module variant,
   or a cache/CDN issue.
2. Do not silently treat a matching helper name in a different file as proof
   of activation.
3. A replacement **Runtime Asset Remediation Manifest** is allowed only when
   the immutable release commit contains the actual live-path file and main
   proves it has the requested behavior. It must be a replacement
   schema-valid asset-manifest JSON block, with the revised runtime mapping
   and an activation-dependency `reason` that records why the original path
   was inactive.
4. Deployment must run a new preview and upload only that remediation manifest.
   QA must then rerun the activation gate.
5. If the selector requires a source, compiled, or configuration artifact that
   is not part of the release, block the workflow and route the missing
   deployment work to Dev. Do not deploy a similarly named client asset as a
   substitute.

This remediation does not consume a functional QA loop. Functional QA remains
blocked until the revised activation gate passes.

### Phase 4 — QA verification

1. Main session instructs **qa** session to test the deployed build using every
   applicable startup staging URL.
2. QA must send the following report to main with `send_session_message`:
   - PASS/FAIL per scenario
   - URLs tested
   - staging activation-gate evidence for every changed runtime asset
   - network/console evidence where relevant
   - final verdict (`Ready` or `Not Ready`)

When the scenario includes a state-changing submit action, QA must submit only
when the staging flow is demonstrably test-safe. Otherwise, report
`Submit control reachable` rather than claiming an end-to-end confirmation was
submitted.

#### QA tooling — Playwright primary, Chrome DevTools fallback

- **Default: use Playwright** (`playwright-browser_*` tools) for all staging QA.
  - Use `playwright-browser_navigate` → `playwright-browser_evaluate` for `dataLayer` inspection.
  - Use `playwright-browser_click` to trigger user interactions (e.g. "Schedule Install" CTA).
  - Use `playwright-browser_run_code_unsafe` for complex multi-step scripts (loop over events, structured JSON capture).
  - Capture structured evidence from `window.dataLayer` directly — do not rely on visual screenshots as proof.
- **Fallback: Chrome DevTools MCP** only when Playwright is unavailable or when the scenario specifically requires DevTools-only features (Performance trace, Lighthouse audit, breakpoints, LCP analysis).
  - If Chrome DevTools MCP fails with `Transport closed` or init errors, switch immediately to Playwright — do not retry DevTools repeatedly.
- **Evidence format** for `dataLayer` events: capture as structured output (counts, sample payloads, field presence checks) — not just "event seen". Example:
  ```
  view_item_list events: 1 | items: 12 | carousel: 3 | grid: 9
  sample: { item_id: '123', item_name: 'X', item_list_name: 'grid' }
  ```

#### QA source-to-DOM trace requirement

When a visible label or behavior contradicts the expected deployed code:

1. First check the staging activation gate; do not assume a successful upload made the new file live.
2. If activation passes, identify the exact DOM node, its displayed value, and the runtime code path that created it.
3. Report all rendering paths that were exercised (for example: picker, next-available banner, review, confirmation, and client-specific module variant).
4. Treat helper-only assertions as insufficient. A fix must be validated through the actual rendered DOM path on staging.

This prevents repeated patches to helpers that are not used by the customer-facing surface.

### Phase 5 — Decision gate

- If **QA = PASS/Ready**:
  1. Main accepts the explicit QA callback, then runs final self-review/code-review against the immutable
     release SHA. Do not review the orchestrator worktree's `HEAD` when it
     differs from the published release.
  2. Main session reports completion

- If **QA = FAIL/Not Ready**:
  1. QA sends defect details and activation-gate evidence to main session.
  2. Main determines whether this is a **Deployment Activation Failure** or a verified **Functional Failure**.
  3. For a Deployment Activation Failure, repair the deployment/reference/cache problem and rerun the activation gate before any functional QA retry.
  4. For a verified Functional Failure, main investigates the actual rendered code path, defines a focused fix task, and sends it to Dev.
  5. Repeat **Develop → Deploy → Activation Gate → QA** for functional failures, subject to the loop cap.

## Loop rule (max 3 loops)

Do not stop after the first verified functional QA failure. Repeat the **Develop → Deploy → Activation Gate → QA** cycle up to **3 functional loops maximum**.

- If QA passes within 3 loops: proceed to final code review and completion.
- If QA still fails on loop 3: stop the loop, report unresolved blockers to the user, and await direction.
- An activation-gate failure does **not** consume a functional QA loop because functional QA has not yet tested the intended build. It must still be reported immediately and resolved before proceeding.

This cap prevents accidental infinite retry loops.

## Scaling rule

You are not limited to these 3 sessions. Spawn additional nested sessions when needed (e.g., security review, data migration, performance validation), but keep the triad sessions as the default backbone.

## Message templates

### Template: Main -> Dev

Use this structure when assigning implementation:

- task objective
- plan summary
- exact files/surfaces to change
- constraints (language/version/style/safety)
- required validation commands, limited to the smallest affected project or
  existing targeted test; never the full `Tireweb Sites\Tireweb Sites.sln`
- release ref that must receive the completed change
- declared release candidate SHA and remote/local lineage, when they differ
- expected return format (changed files, results, release commit SHA, one
  schema-valid asset-manifest JSON block, diff from candidate, blockers)
- **mandatory callback:** include the parent session ID in the assignment and
  require `send_session_message` to that ID with the completed structured
  handoff; do not leave the report only in the child session

### Template: Main -> Deployment

Include:

- remote staging directory
- the following **mandatory JSON block**, populated with Dev's exact manifest
  and validated against the Asset Manifest JSON Schema before any preview or
  upload; do not translate it to a Markdown list or infer missing values:

```json
{
  "schema_version": "1.0",
  "release_ref": "<release-ref>",
  "release_commit": "<40-character-lowercase-commit-sha>",
  "assets": [
    {
      "asset_type": "frontend",
      "repository_source_path": "<repository-path>",
      "staging_upload_path": "<staging-path>",
      "sha256": "<64-character-lowercase-sha256>",
      "runtime_fingerprint": "<distinctive-runtime-fingerprint>",
      "runtime_mapping": {
        "expected_runtime_url_or_versioned_filename": "<runtime-url-or-versioned-filename>",
        "source_registration_or_resolution_evidence": "<source-registration-or-runtime-resolution-evidence>"
      },
      "activation_dependencies": {
        "required": false,
        "artifacts": []
      }
    }
  ]
}
```

- reject the handoff if its JSON is invalid, a required field is missing, an
  asset is duplicated, or a hash/path does not match the detached release
  checkout
- requirement to use a clean, detached temporary checkout of that exact SHA;
  never cherry-pick or deploy an inferred working tree
- durable manifest-path requirement: use `-DeploymentManifestPath` for both
  the preview and upload, rather than default uncommitted-file discovery
- requirement to run preview before upload and preserve raw Git-blob bytes
- **mandatory callback:** include the parent session ID in the assignment and
  require `send_session_message` to that ID with uploaded files, target path,
  deployed commit, local hashes, remote size verification, and cleanup

### Template: Main -> QA

Include:

- every staging URL in scope
- activation-gate instructions: inspect the actual asset URLs from the page and compare cache-bypassed content to the asset manifest before testing behavior; use a runtime fingerprint when browser SHA-256 is unavailable on HTTP
- exact test scenarios and URLs
- required evidence format (PASS/FAIL, structured `dataLayer` capture, network/console where relevant)
- final binary verdict (`Ready` or `Not Ready`)
- tooling instruction: **use Playwright by default** (`playwright-browser_*`); fall back to Chrome DevTools MCP only if Playwright is unavailable or a DevTools-specific feature is required (Performance trace, Lighthouse, breakpoints)
- for `dataLayer` scenarios: capture evidence via `playwright-browser_evaluate` / `playwright-browser_run_code_unsafe` with `window.dataLayer` inspection — structured counts + sample payloads, not just "event observed"
- when behavior fails despite a passing activation gate: include the exact DOM text/node and the known runtime render path; do not rely on helper-level claims
- when a submit would create a non-test-safe booking, stop at the submit control
  and label the result accordingly
- **mandatory callback:** include the parent session ID in the assignment and
  require `send_session_message` to that ID with the complete activation and
  QA verdict; a report that remains only in the QA session does not complete
  the phase

## Safety checks

- Never perform code edits from the main/orchestrator session.
- Never deploy without preview + confirmation.
- Keep deployment limited to intended files/scope.
- Never deploy from a different worktree branch, cherry-pick, or unverified working tree when an immutable release commit has been declared.
- Never rely on a child idle notification, `get_session` metadata, or a
  delivered request as evidence of phase completion; require the structured
  child callback and perform proactive liveness checks.
- Never calculate or validate a manifest hash from a text-converted,
  BOM-stripped, or line-ending-normalized release file.
- Never use default uncommitted-file discovery for an authoritative immutable
  manifest deployment; use `-DeploymentManifestPath` with a stable manifest
  file and a detached release worktree.
- Never bypass the runtime-compiled control check because a related
  `Tireweb.Sites.dll` build succeeded.
- Never remediate a blank server-side control by re-uploading unchanged markup
  before obtaining a compiler/resolution diagnosis.
- Never authorize Deployment solely because a remote ref resolves to a reported
  SHA; first verify the release tree and runtime-asset mapping.
- Never assume the repository's latest asset version is the version selected by
  staging. Resolve the actual DOM asset URL before functional QA.
- Never replace an inactive manifest file with a different versioned file
  without a Runtime Asset Remediation Manifest and a new preview/upload.
- Never start functional QA until the staging activation gate proves the page serves the declared deployed assets.
- On QA failure, do not claim completion.
- On QA tool failure (Chrome DevTools `Transport closed`), switch to Playwright immediately — do not retry the failing tool more than once.
- On completion, summarize what was changed, deployed, and verified.


## Post-review adjustment loop (after QA pass)

If main-session code review finds required adjustments after QA has already passed:

1. Main session classifies findings:
   - **Blocking** (correctness, security, data loss, regression risk)
   - **Non-blocking** (style, optional refactor, low-risk cleanup)

2. For **blocking findings**:
   - Send a focused fix task to **dev**
   - Re-run **deployment** for changed files/scope
   - Re-run the **staging activation gate**
   - Re-run **qa** for impacted scenarios (plus smoke check)
   - Return to main-session code review
   - Count this as a new loop and still enforce the global max-loop cap

3. For **non-blocking findings**:
   - Either defer (document in final notes) or fix only if user approves extra iteration

4. Exit conditions:
   - No blocking findings remain, and QA is still `Ready`
   - Or loop cap reached -> stop and report unresolved blockers + recommendation
