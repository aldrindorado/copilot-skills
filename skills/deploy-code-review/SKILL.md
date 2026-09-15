---
name: deploy-code-review
description: Launch a coordinated, read-only nested code-review session using GPT-5.6 Sol, medium reasoning, and long context. Use when the user asks to delegate, run, or perform a code review in a nested session or reviewer sub-session while carrying forward review context and instructions from the main session.
---

# Deploy code review

Create a nested project session that performs the review. The main session is
the coordinator and must not perform the delegated review itself.

## Fixed reviewer settings

- model: `gpt-5.6-sol`
- reasoning effort: `medium`
- context tier: `long_context` (1.1M context)
- mode: `autopilot`
- execution location: `local`
- workspace type: `branch`
- coordination with the main session: enabled
- idle notification: `once`
- default agent: omit `agent`

Normally omit `base_branch` so the nested session uses the current local
checkout and current `HEAD`. Do not create a worktree unless the user explicitly
requests one.

## Build the review handoff

Before creating the nested session, collect the review instructions already
available in the main conversation. The nested session automatically receives
applicable repository Copilot instruction files. Determine whether the AI IDE
where this skill is installed exposes a `code-review` skill. If it does, the
nested reviewer must invoke that skill. If it does not, the nested reviewer
must run the IDE's `/review` command instead. Do not repeat stable repository
guidance or generic review rules already supplied by those sources.

The kickoff must remain standalone and use this compact structure:

```text
Scope:
Intended behavior:
Known risks and exclusions:
Output and permissions:
```

Include:

- repository name and absolute path only when the nested workspace cannot
  identify them reliably;
- current branch plus the exact comparison base, pull request, commit range, or
  working-tree scope;
- task-specific intended behavior and conversation-only decisions needed to
  distinguish defects from deliberate behavior;
- known risks, exclusions, and validation limits that materially affect the
  review;
- whether findings go to the main session, staged inline comments, GitHub, or a
  combination; and
- any user-authorized exception to the default read-only behavior.

Do not separately repeat the same requirement as context, priority, risk, and
definition of done. When available, the invoked `code-review` skill governs
high-confidence findings, severity ordering, exact changed-line references,
and implementation-ready guidance. Otherwise, rely on the IDE's `/review`
command for its standard review behavior.

Aim for roughly 250-500 words. Exceed that range only for genuinely broad
multi-subsystem reviews or substantial conversation-only requirements. Long
context is capacity, not a prompt-length target.

Preserve the user's additional context and instructions accurately. Do not
replace specific requirements with a generic summary. If the comparison target
or review scope is genuinely absent and cannot be inferred from the current
session, ask one focused question before creating the reviewer.

## Create the reviewer

Use `create_session` with:

```text
name: Code review - <branch-or-pr>
execution_location: local
workspace_type: branch
coordinate_with_creator: true
notify_on_idle: once
kickoff.model: gpt-5.6-sol
kickoff.reasoning_effort: medium
kickoff.context_tier: long_context
kickoff.mode: autopilot
```

When the `code-review` skill is available, the first sentence of the kickoff
must be:

> Invoke the `code-review` skill immediately as your first action and follow it
> as the source of truth for the entire review.

When no `code-review` skill is available, the first sentence of the kickoff
must instead be:

> Run the `/review` command immediately as your first action and use its review
> workflow as the source of truth for the entire review.

Do not invoke `code-review` or run `/review` in the main session as a substitute
for requiring the nested reviewer to use the available review workflow.

## Completion

Wait for the nested session's completion message. An idle notification alone is
not proof that the review completed. If the reviewer reports a blocker caused
by missing context, send the missing information to the same nested session
rather than creating a replacement.

Return the review result to the user without weakening severity, dropping file
or line references, or omitting suggested changes. State the nested session
name or ID only when useful for traceability.
