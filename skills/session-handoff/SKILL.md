---
name: session-handoff
description: Create or refresh a concise continuation handoff and cumulative decision log for the current coding session, including the goal, major decisions and plan deviations, branch and files changed, tests, blockers, evidence-based process improvements, and one exact next step. Save both Markdown files under C:\ESP\copilot-handoffs\<origin-feature-key>, reusing the stable feature directory when it exists. Use when the user wants to clear context, preserve session state, prepare a continuation note, or write a handoff file.
---

# Create a continuation handoff

Use this skill when the user wants the current work preserved in a concise
Markdown handoff so another session can continue without relying on chat
history.

Never record credentials, tokens, passwords, connection strings, or other
secrets in either handoff file. Record only the non-sensitive name or location
of a required secret, such as a configuration key, user-secret name, or vault
entry.

## Output location

Save the handoff to:

```text
C:\ESP\copilot-handoffs\<origin-feature-key>\handoff.md
```

Maintain the cumulative decision log beside it:

```text
C:\ESP\copilot-handoffs\<origin-feature-key>\decisionLog.md
```

## Resolve the stable feature directory

Prefer the feature branch tracked by the current session's `origin` upstream,
not the generated local Copilot worktree branch:

```powershell
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
```

When the result is `origin/<feature-branch>`, use `<feature-branch>` as the
feature key. For example:

```text
origin/EOSB-810 -> C:\ESP\copilot-handoffs\eosb-810
```

Normalize the feature key for a stable Windows directory:

- Remove the `origin/` prefix.
- Convert the key to lowercase.
- Replace `/`, `\`, and other Windows-invalid filename characters with `-`.
- Preserve hyphens and other valid characters.

If the current branch has no upstream, use the session's explicit origin
feature branch when one is supplied in the workspace context. If neither is
available, use the current Git branch only as a last resort and apply the same
lowercase normalization. If the working directory is not a Git repository,
ask the user for the feature name instead of inventing one.

Always check the deterministic directory
`C:\ESP\copilot-handoffs\<origin-feature-key>` first. Reuse its existing
`handoff.md` and `decisionLog.md` in place; do not create a second directory
from a generated local branch name, and do not search similarly named
directories.

Create `C:\ESP\copilot-handoffs` and the stable feature folder when they do not exist.
If `handoff.md` already exists, update it to reflect the current state rather
than creating numbered or timestamped copies. Preserve any clearly
user-authored sections that remain relevant.

If `decisionLog.md` already exists, preserve its historical entries. Add only
new major decisions or material changes to earlier decisions; do not recreate
the file from the current chat summary.

## Gather authoritative state

Build the handoff from both the conversation and current workspace evidence.
Do not claim a result that was not observed.

1. Identify the current repository, branch, upstream, last commit, push state,
   and working-tree state. Use explicit Git evidence where available:

   ```powershell
   git rev-parse --abbrev-ref HEAD
   git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
   git log -1 --oneline
   git rev-list --left-right --count '@{upstream}...HEAD'
   git status --porcelain
   ```

   If there is no upstream, record that fact rather than inventing ahead or
   behind counts.
2. Inspect staged, unstaged, and untracked files so the file list is complete.
3. Summarize the user's goal and the important implementation decisions.
   Identify decisions that caused major code changes or materially diverted
   the implementation from the initial plan.
4. Record relevant files or deployment scope. Group files by subsystem when
   that is clearer than one long list.
5. Record tests, builds, browser checks, reviews, deployments, and their actual
   outcomes.
6. Record unresolved defects, environment limitations, authentication needs,
   manual database work, and other blockers.
7. Produce a concise, phase-based mini-retrospective for `For Improvements`.
   Evaluate development, deployment, validation, and cross-phase handoffs when
   those phases occurred. Include every high-confidence optimization supported
   by observed evidence; do not collapse distinct findings into one generic
   bullet merely to shorten the handoff. For each recommendation, state the
   observed failure, friction, delay, conflict, missing coverage, or successful
   practice that motivates it, then give the concrete optimization. Omit
   speculative ideas and content already covered by blockers, the exact next
   step, or decision-log history.
8. Derive one concrete next action. It must be executable and specific, not
   "continue testing" or "finish the work."

Do not access a database merely to enrich a handoff. Do not rerun expensive
tests, rebuild artifacts, deploy, or modify source code solely to collect
handoff evidence.

## Classify information as ephemeral or durable

Before writing, classify each finding by asking: **Will this still be true and
useful after the current feature is completed?**

| Classification | Examples | Where to record it |
|---|---|---|
| Ephemeral session state | Current blocker, uncommitted files, branch-specific test result, deployment status, exact next step | `handoff.md` |
| Durable consequential decision | Architecture, interface, data-flow, persistence, security, compatibility, or deployment choice that constrains future work | `decisionLog.md`, referenced briefly from `handoff.md` |
| Durable repository knowledge | General entry points, subsystem documentation, standard commands, or behavior unrelated to continuing this feature | Omit unless it directly constrains the continuation; do not turn the handoff into general repository documentation |

Record a finding in one primary location and reference it elsewhere only when
needed for continuation. This keeps the handoff focused while preserving
consequential decisions in the cumulative decision log.

## Cumulative decision log

Use `decisionLog.md` as the durable history of consequential choices so later
sessions can understand why the implementation changed and revisit earlier
reasoning. Do not log routine edits, obvious implementation details, temporary
debugging steps, or decisions that had no meaningful effect on scope, design,
behavior, safety, or delivery.

Record a decision when at least one of these is true:

- It establishes or changes architecture, interfaces, data flow, persistence,
  security boundaries, deployment behavior, or compatibility guarantees.
- It causes substantial code changes or constrains future implementation.
- It materially changes scope, sequencing, or the original plan.
- It accepts a significant trade-off, limitation, operational risk, or
  migration strategy.
- It explicitly rejects a plausible alternative that future work might
  otherwise reconsider.

Before writing, read the existing decision log and avoid duplicate entries.
Use stable sequential IDs (`DEC-001`, `DEC-002`, and so on) and chronological
order. Preserve the original wording of historical entries except to correct a
factual error or change their status. If a decision changes, add a new entry,
mark the earlier entry `Superseded`, and link both entries with `Supersedes`
and `Superseded by` fields. Never silently rewrite history.

Use this smallest complete structure:

```markdown
# <Feature> Decision Log

## DEC-001: <Decision title>

- **Recorded:** <ISO 8601 date and time with offset when known>
- **Status:** Active
- **Context:** <Problem, constraint, or initial plan>
- **Decision:** <What was chosen>
- **Rationale:** <Why it was chosen>
- **Impact:** <Major code, scope, behavior, or delivery consequences>
- **Rejected alternatives:** <Alternatives and why they were rejected, or None>
- **Evidence:** <Relevant files, commits, PRs, tests, or session IDs when known>
```

Add `- **Supersedes:** DEC-###` or `- **Superseded by:** DEC-###` only when
applicable. Use `Unknown` rather than inventing rationale, alternatives, dates,
or evidence. If no new qualifying decision was made, leave `decisionLog.md`
unchanged. If the file does not exist and there are no qualifying decisions,
create it with the title and `No major decisions recorded yet.`

## Required Markdown contract

Write the smallest complete handoff using these headings:

```markdown
# <Feature> Handoff

## Goal

## Branch and working state

## Decisions

## Files changed

## Tests and validation

## Blockers

## For Improvements

## Session log

## Exact next step
```

Apply these requirements:

- **Goal:** one or two sentences describing the requested outcome.
- **Branch and working state:** repository path, branch, commit/push state, and
  whether changes are staged or uncommitted.
- **Decisions:** summarize only active decisions that constrain future
  implementation. Reference their `DEC-###` IDs from `decisionLog.md` when
  available; keep full history and rejected alternatives in the decision log.
- **Files changed:** exact repository-relative paths when known. Mark new,
  generated, deployment-only, or manual SQL files clearly.
- **Tests and validation:** name each actual check and its result. Distinguish
  PASS, FAIL, PARTIAL, and BLOCKED.
- **Blockers:** include the exact error, route, missing prerequisite, or manual
  action. Write `None` when there are no blockers.
- **For Improvements:** keep the handoff concise overall, but make this section
  a structured, phase-based mini-retrospective. Use labeled bullets or compact
  subheadings for each applicable phase, normally **Development**,
  **Deployment**, **Validation**, and **Cross-phase**. Include every distinct,
  high-confidence optimization supported by observed evidence rather than only
  a broad summary. Each item must contain both:
  1. the concrete evidence or observed failure that motivated it; and
  2. the specific process, tooling, ownership, test, or sequencing change that
     would improve future work.
  Preserve successful practices when retaining them is itself an actionable
  optimization. Exclude speculative ideas and anything already represented as
  a current blocker, exact next step, or decision-log entry. Write
  `None identified.` only when no evidence-supported improvement exists.
- **Session log:** append one concise line for each handoff creation or refresh,
  newest last, using
  `- <ISO 8601 date and time with offset>: <what changed in this refresh>`.
  Keep at most 15 lines. When the limit would be exceeded, replace the oldest
  lines with one summary line rather than discarding meaningful history.
- **Exact next step:** provide one imperative action with the target command,
  URL, file, session ID, or deployment scope when known.

Include database restrictions and whether SQL was executed whenever database
work was discussed. Include staging targets and deployed artifacts whenever a
deployment occurred.

## Write and verify

1. Inspect both destination files before writing so an existing handoff or
   decision history is not accidentally discarded.
2. Create the destination folder if absent.
3. Use `apply_patch` to create or update `handoff.md` and `decisionLog.md`.
4. Read both saved files back. Confirm every required handoff heading is
   present, including `## For Improvements`, and confirm that section contains
   a phase-based mini-retrospective covering every applicable phase, with each
   recommendation tied to concrete observed evidence, or exactly
   `None identified.`. Check that distinct high-confidence findings were not
   over-compressed into generic bullets. Confirm speculative ideas are absent,
   blockers and the exact next step remain in their dedicated sections, and
   decision-log history is not duplicated. Confirm `## Session log` is present,
   chronological, and bounded to 15 lines. Confirm decision IDs are unique and
   sequential. Confirm neither file contains credentials, tokens, passwords,
   connection strings, or other secrets.
5. Reply with only both saved paths and whether each file was created, updated,
   or unchanged.

Do not create planning or handoff files inside the source repository.
