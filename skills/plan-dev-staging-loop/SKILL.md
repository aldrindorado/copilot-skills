---
name: plan-dev-staging-loop
description: Plan an Ezytire change in the main session, hand implementation to a GPT-6 Luna local-branch development session, then use Kimi K2.7 Code to run test-staging and return QA defects to development for at most two total delivery iterations.
---

# Plan, develop, and test staging

Use this skill for an Ezytire task that should be planned by the main session,
implemented in a nested local development session, deployed to staging, and
verified by QA.

The main session is the coordinator. It owns planning and handoffs but does not
edit source code, deploy files, test staging directly, or access a database.

## Non-negotiable rules

- Run no more than **two total delivery iterations**. One iteration is:
  Development -> `test-staging` -> result.
- Iteration 1 is the initial implementation and staging test. If it fails,
  iteration 2 is the only automatic remediation attempt.
- Reuse the original Development session for fixes so it retains context.
- Reuse the staging coordinator session for the second `test-staging` run when
  it is reachable and healthy.
- Development uses the user's current local checkout and current branch.
- Do not create a worktree for Development. Create it with
  `execution_location: "local"` and `workspace_type: "branch"`, and normally
  omit `base_branch` so it uses the local checkout's current `HEAD`.
- Never commit, push, reset, rebase, stash, or switch branches unless the user
  explicitly requests that Git operation.
- Never connect to, query, inspect, alter, or update a database.
- When schema or data changes are required, Development may create a
  reviewable manual SQL script, but no session may execute it. Tell the user
  what script to run and treat database-dependent QA as blocked until the user
  confirms it was run.
- Preserve unrelated local changes.

## Fixed session settings

### Development session

- name: `Development - <branch-name>`
- model: `gpt-6-luna`
- reasoning effort: `max`
- context tier: `long_context`
- mode: `autopilot`
- execution location: `local`
- workspace type: `branch`
- coordination with the main session: enabled
- idle notification: `always`
- default agent: omit `agent`

### Staging coordinator session

- name: `Staging QA - <branch-name>`
- model: `kimi-k2.7-code`
- mode: `autopilot`
- context tier: `default`
- coordination with the main session: enabled
- idle notification: `always`
- default agent: omit `agent`
- reasoning effort: omit it because Kimi K2.7 Code does not support an
  explicit reasoning-effort setting

The staging coordinator must invoke `test-staging` as its first action and
follow that skill exactly. Its Deployment and QA child sessions therefore use
the model and settings required by `test-staging`.

## 1. Plan in the main session

1. Inspect the current branch, relevant source, existing implementation
   patterns, deployment requirements, and runtime dependencies.
2. Reuse staging inputs already supplied in the conversation. Ask only for
   missing required values:
   - staging directory;
   - staging URL or URLs;
   - acceptance scenarios; and
   - upload authorization after preview.
3. Identify whether the task needs database schema or data changes. Record
   that scripts are manual-only and database access is prohibited.
4. Produce a concrete implementation plan containing:
   - behavior and scope;
   - target files and layers;
   - database script requirements;
   - runtime and compiled artifact requirements;
   - smallest relevant builds or checks;
   - staging deployment scope;
   - QA acceptance scenarios; and
   - failure and rollback considerations.
5. Get plan approval in the main session before creating Development.
6. Check existing sessions before creating a new role session. Reuse an exact
   branch-and-role match only when it is healthy and appropriate.

## 2. Hand the approved plan to Development

Create Development with the fixed settings above. Its standalone kickoff must
include:

- repository path, repository name, and current branch;
- the complete approved plan, not a summary that depends on chat history;
- every acceptance scenario;
- repository language and instruction constraints;
- required source and runtime artifact handling;
- validation commands or expected validation coverage;
- explicit prohibitions on database access and SQL execution;
- explicit prohibition on staging deployment;
- instruction to create manual SQL scripts when required;
- instruction to report changed files, generated/runtime artifacts, validation
  results, SQL script paths, and blockers; and
- instruction to send its completion report to the main coordinator.

Wait for a positive completion report. An idle notification alone is not proof
of completion. If Development reports a blocker, surface it and stop unless it
can be corrected within the same session without consuming a QA iteration.

## 3. Run staging deployment and QA

After Development completes, create the staging coordinator with the fixed
settings above. Its standalone kickoff must:

- explicitly say: "Invoke the `test-staging` skill immediately as your first
  action and follow it exactly";
- identify the local repository path and current branch;
- include the Development report and complete changed-file list;
- include generated assemblies or other required runtime artifacts;
- include the staging directory, all test URLs, and upload authorization;
- include every acceptance scenario;
- prohibit source edits and Git-state changes;
- prohibit all database access and SQL execution;
- exclude manual SQL scripts from deployment;
- require database-dependent scenarios to be marked `BLOCKED`, not bypassed;
  and
- request deployment evidence plus PASS, FAIL, or BLOCKED for every scenario.

The staging coordinator owns `test-staging`, including its sequential
Deployment and QA children. Do not create a separate QA session from Main.

## 4. Handle QA defects

Classify the staging result:

- **Ready:** deployment succeeded and all required non-database scenarios pass.
  Report success. Clearly list any database-dependent scenario still blocked
  for the user's manual action.
- **Deployment or activation defect:** missing file, assembly, generated
  artifact, stale asset, compilation failure, or runtime dependency problem.
  Return it to Development.
- **Functional QA defect:** implemented behavior differs from an acceptance
  scenario. Return it to Development.
- **Infrastructure or credential blocker:** report it and stop. Do not consume
  the second iteration when no code or release change can correct it.

For a correctable defect after iteration 1, send a new message to the same
Development session. The remediation message must include:

- iteration number (`2 of 2`);
- exact failing URL and scenario;
- expected versus actual behavior;
- HTTP status, compiler/runtime error, selector, console output, network
  evidence, or screenshot evidence;
- missing deployment/runtime artifact when applicable;
- precise implementation guidance without prescribing an unsafe shortcut;
- required regression checks;
- database restrictions; and
- a request for a fresh changed-file/runtime-artifact and validation report.

Do not fix the defect in Main.

After Development reports the fix, send a new turn to the same healthy staging
coordinator instructing it to invoke `test-staging` again with the revised
Development report, complete deployment scope, and all original acceptance
scenarios. This is iteration 2.

## 5. Stop condition

After iteration 2:

- If QA is Ready, report the successful target and evidence.
- If QA still fails, stop automatic work. Report the remaining reproducible
  defects, deployment state, database blockers, and both iteration outcomes.
- Do not start a third Development, Deployment, or QA cycle.

## Final report

Report:

- current branch;
- iterations used out of two;
- Development result and changed files;
- manual SQL script path and confirmation that it was not executed;
- staging target and deployed files/runtime artifacts;
- PASS, FAIL, or BLOCKED for every acceptance scenario;
- remaining blockers; and
- final verdict: `Ready`, `Ready except for manual database activation`, or
  `Not Ready`.
