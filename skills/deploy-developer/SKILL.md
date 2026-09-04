---
name: deploy-developer
description: Create a nested developer session configured with GPT-5.6 Luna, maximum reasoning effort, and the 1.1M long-context setting. Use when the user asks to create, start, launch, deploy, or spin up a nested session with developer settings or a developer configuration.
---

# Deploy Developer

Create a nested session for development work by calling `create_session` with these exact kickoff settings:

- `model`: `gpt-5.6-luna`
- `reasoning_effort`: `max`
- `context_tier`: `long_context`

The `long_context` value selects the model's 1.1M context setting. Use the user's requested development task as `kickoff.prompt`. Preserve any explicitly requested session name, mode, execution location, workspace type, base branch, notification behavior, or coordination setting. Otherwise:

- Create the session in the current project by omitting `project_id`.
- Use local execution by omitting `execution_location`.
- Use an isolated worktree by omitting `workspace_type`.
- Coordinate with the creator by leaving `coordinate_with_creator` enabled.
- Set `notify_on_idle` to `once`.
- Choose a short, descriptive sentence-case session name based on the task.
- Do not set `base_branch` unless the user explicitly requests one or the task clearly depends on an in-progress branch.

If the user asks only to create a developer session but does not provide the development task, ask for the task before creating the session.
