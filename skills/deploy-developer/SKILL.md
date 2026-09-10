---
name: deploy-developer
description: Create a nested developer session configured with GPT-5.6 Luna, maximum reasoning effort, and the 1.1M long-context setting. Use when the user asks to create, start, launch, deploy, or spin up a nested session, developer sub agent, developer sub-agent, or other developer session with developer settings or a developer configuration.
---

# Deploy Developer

Create a nested session for development work by calling `create_session` with these exact kickoff settings:

- `model`: `gpt-5.6-luna`
- `reasoning_effort`: `max`
- `context_tier`: `long_context`

The `long_context` value selects the model's 1.1M context setting. Preserve any
explicitly requested session name, mode, execution location, workspace type,
base branch, notification behavior, or coordination setting. Otherwise:

- Create the session in the current project by omitting `project_id`.
- Use local execution by omitting `execution_location`.
- Use an isolated worktree by omitting `workspace_type`.
- Coordinate with the creator by leaving `coordinate_with_creator` enabled.
- Set `notify_on_idle` to `once`.
- Choose a short, descriptive sentence-case session name based on the task.
- Do not set `base_branch` unless the user explicitly requests one or the task clearly depends on an in-progress branch.

If the user asks only to create a developer session but does not provide the development task, ask for the task before creating the session.

## Build a precise kickoff

The nested session automatically receives applicable repository Copilot
instruction files. Do not repeat stable repository guidance already defined
there, such as general coding conventions, architecture, standard validation,
or formatting rules.

Make `kickoff.prompt` standalone but concise. Include only task-specific facts
that the nested session cannot reliably recover from the repository:

```text
Task:
Scope:
Required behavior:
Known findings/risks:
Validation:
Deliverable and permissions:
```

Apply these rules:

- Preserve exact user requirements and conversation-only decisions.
- Prefer exact findings, acceptance criteria, symbols, and file paths over
  background narrative.
- State branch or commit dependencies when the task relies on in-progress work.
- Mention validation limitations only when they affect execution.
- State side-effect permissions once: whether to commit, push, deploy, post, or
  report only.
- Consolidate overlapping context instead of repeating it under multiple
  headings.
- Do not repeat instructions supplied by another skill the developer is
  explicitly told to invoke.

Aim for roughly 150-350 words. Exceed that range only when multiple subsystems,
exact findings, or substantial conversation-only decisions require it. Long
context is capacity, not a prompt-length target.
