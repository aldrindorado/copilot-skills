---
name: reset-staging-folder
description: Deploy all web files introduced by PRs merged into development during a user-selected recent number of days to a selected staging directory. Use when asked to reset, refresh, or deploy a staging folder from recent development merges.
---

Use this skill only for an Ezytire repository. It selects files changed by merges
on `origin/development` and deploys only the files under `Tireweb Sites\Web`
through the installed `staging-deployment-custom` skill. Never queue, upload,
or attempt to map files from any other project folder.

## Required workflow

1. Ask the user **first** how many calendar days to look back from now. Require
   a positive whole number. Do not infer a date or reuse a prior deployment's
   lookback period.
2. Fetch the current development ref:

   ```powershell
   git fetch origin development --quiet
   ```

3. Create a temporary, detached worktree outside the repository from
   `origin/development`. Use a unique directory beneath the current session's
   artifacts directory, for example:

   ```powershell
   $sourceRoot = Join-Path $env:USERPROFILE ".copilot\session-state\$env:COPILOT_SESSION_ID\files\reset-staging-development"
   git worktree add --detach $sourceRoot origin/development
   ```

   If `COPILOT_SESSION_ID` is unavailable, use a uniquely named child directory
   beneath `$env:TEMP`. Do not switch, reset, or otherwise modify the caller's
   current branch. The temporary worktree is the authoritative source for both
   the file list and deployed content.

4. Load the custom deployment skill and follow its remote-directory rules:
   - Clear the saved custom remote root for a new direct deployment chat.
   - Ask for the remote staging directory unless the user supplied it.
   - Normalize and save it using
     `Set-StagingDeploymentRemoteRoot`.
   - Reuse it only for later deployments in this same chat unless the user
     supplies a replacement.

   ```powershell
   . "$HOME\.copilot\skills\staging-deployment-custom\StagingDeploymentSettings.ps1"
   Remove-StagingDeploymentRemoteRoot
   # Ask for $chosenRemoteRoot, then:
   $remoteRoot = Set-StagingDeploymentRemoteRoot -RemoteRoot $chosenRemoteRoot
   ```

5. Calculate the inclusive start timestamp as midnight in the local time zone,
   `N - 1` calendar days before today. For example, on August 12 with a
   three-day lookback, use `--since=2026-08-10T00:00:00+08:00`.

6. Preview the deployment from the temporary development worktree. Generate the
   list with the following argument order, which restricts the change list to
   merged first-parent changes and expands merge diffs against their first
   parent:

   ```powershell
   & "$HOME\.copilot\skills\staging-deployment-custom\Deploy-StagingCustom.ps1" `
       -RepositoryRoot $sourceRoot `
       -RemoteRoot $remoteRoot `
       -GenerateListFromGitLogArgs @(
           'origin/development',
           '--first-parent',
           '--diff-merges=first-parent',
           "--since=$sinceTimestamp"
       ) `
       -WhatIf
   ```

   The custom script deduplicates paths and accepts only files under
   `Tireweb Sites\Web`. Treat that as the complete deployment queue: report all
   changed paths outside this folder as skipped, including paths in
   `Customization`, `Tireweb Sites\Sites`, and every other project folder.
   Never add those paths through `-IncludePaths` or alternate copy logic. The
   script also blocks sensitive files, skips deleted/missing paths, and maps
   each selected local path to the selected remote root.

7. After a successful preview and **before any upload**, always display these
   two complete file-name lists:
   - **Queued for deployment:** every selected path below
     `Tireweb Sites\Web`, with its mapped remote path.
   - **Excluded from deployment:** every path excluded because it is outside
     `Tireweb Sites\Web`, protected/sensitive, deleted or missing locally.
     Group excluded paths by reason.

   Do not summarize either list as a count only. Show every path in each list,
   even in autopilot mode. In standard mode, require explicit user confirmation
   after showing the lists. Autopilot skips only that confirmation when the
   user explicitly requested it; it never skips the preview or the two lists.
8. After confirmation, use the exact same command without `-WhatIf`. Report
   the complete local-relative-to-remote file list returned by the script.
9. Remove the temporary worktree when finished, whether the operation succeeds,
   is declined, or fails:

   ```powershell
   git worktree remove --force $sourceRoot
   ```

   Never retry a failed upload without resolving and explaining its cause.

## Safety

- The deployment uploads only selected files and never deletes remote files.
- Do not include `shell` or `bash` in this skill's allowed tools.
- Do not expose, request, or place the SFTP password in chat, commands, or
  files. Follow the custom deployment skill's Credential Manager workflow.
- Queue and deploy only files beneath `Tireweb Sites\Web`; report every changed
  path from all other project folders as skipped.
