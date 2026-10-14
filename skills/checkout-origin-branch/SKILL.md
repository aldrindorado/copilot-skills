---
name: checkout-origin-branch
description: Safely connect the current Copilot-managed worktree to a user-specified origin branch. Use when the user asks to check out, open, switch this worktree to, or link a feature branch such as EOSB-801.
---

# Check out an origin branch in a Copilot worktree

Connect the current Copilot-managed worktree to `origin/<branch>` while keeping
the app-managed local branch name.

## Resolve the branch

Resolve the branch name in this order:

1. Use the branch supplied in skill arguments or additional context.
2. Use a branch explicitly named in the user's request.
3. Otherwise, ask the user which branch to use with the `ask_user` tool.

Accept either `<branch>` or `origin/<branch>` and normalize it to `<branch>`.
Reject blank values, commit hashes, and refs outside `origin/`.

## Safety requirements

- Operate only in the current Copilot worktree.
- Do not create another Git worktree.
- Do not rename the branch with raw Git commands. The app owns the local
  worktree branch name.
- Do not use `git reset --hard`, `git checkout --`, `git clean`, or force-push.
- Before changing commits, run `git status --porcelain`.
- If the worktree is dirty, stop and ask the user whether to preserve, commit,
  or discard the changes. Never discard them automatically.
- Fetch and verify the requested remote branch before changing the worktree.

## Procedure

Run these steps:

1. Fetch the requested branch:

   ```powershell
   git fetch origin <branch>
   ```

2. Confirm `refs/remotes/origin/<branch>` exists:

   ```powershell
   git show-ref --verify refs/remotes/origin/<branch>
   ```

   If it does not exist, stop and report that the remote branch was not found.

3. Confirm the worktree is clean:

   ```powershell
   git status --porcelain
   ```

4. Align the current app-managed branch without replacing its local name:

   ```powershell
   git reset --keep origin/<branch>
   git branch --set-upstream-to=origin/<branch>
   ```

5. Verify the result:

   ```powershell
   git status --short --branch
   git rev-parse HEAD
   git rev-parse origin/<branch>
   ```

The two commit hashes must match. The status output must show the current local
branch tracking `origin/<branch>`. If either check fails, report the mismatch
instead of claiming success.

## Response

State:

- the app-managed local branch name;
- the configured `origin/<branch>` upstream;
- the matching commit hash.

Do not say the local branch has the same name as the feature branch unless it
actually does.
