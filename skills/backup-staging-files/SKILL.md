---
name: backup-staging-files
description: Back up an explicit list of Ezytire staging files to a persisted local directory before deployment, reusing deploy-files-staging SFTP settings and credentials.
---

# Backup staging files before deployment

Use this skill with `/deploy-files-staging` when the user provides the exact
repository-relative files that will be overwritten on staging and wants a
local backup first.

This skill downloads files only. It never uploads, deletes, or modifies remote
staging files, and it never changes repository files.

## Required setup

The first use must configure the local backup directory. Do not ask for it
again after it has been saved:

```powershell
. "$HOME\.copilot\skills\backup-staging-files\StagingBackupSettings.ps1"
$backupRoot = Get-StagingBackupRoot
```

If `$backupRoot` is empty, ask the user where backups should be saved, then
persist the answer outside the repository:

```powershell
& "$HOME\.copilot\skills\backup-staging-files\Set-StagingBackupRoot.ps1" `
    -BackupRoot '<user-selected absolute directory>'
```

The setting is stored at:

```text
%LOCALAPPDATA%\GitHub Copilot\backup-staging-files\settings.json
```

The backup directory must be outside the repository. If the user explicitly
requests a different backup location later, save the new location before
continuing.

The staging remote root is shared with `/deploy-files-staging`. It must already
be saved by that skill. Do not create a second remote-root setting or ask for a
second remote-root value unless the deploy skill has not been configured.

## Backup workflow

1. Take the file list from the user's additional context or from the exact
   deployment preview. Do not infer a different list from `git diff`.
2. Pass the actual deployable paths, not source paths that will only produce a
   DLL. Paths must be under `Tireweb Sites\Web`; use the staged DLL paths when
   the deployment includes rebuilt projects.
3. Run a dry run before downloading:

   ```powershell
   $backupRunName = 'staging-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')

   & "$HOME\.copilot\skills\backup-staging-files\Backup-StagingFiles.ps1" `
       -RepositoryRoot (Get-Location).Path `
       -IncludePaths $deploymentPaths `
       -BackupRunName $backupRunName `
       -WhatIf
   ```

4. The dry run opens the read-only SFTP connection, preflights every remote
   file, and then shows the complete remote-to-local mapping, the persisted
   backup root, and the proposed timestamped run directory. It creates no run
   directory, manifest, or downloaded file. The proposed directory is not
   reserved: if it becomes occupied before execution, the real run allocates
   the next available `-1`, `-2`, and so on suffix. Treat the directory and
   manifest reported after the real run as authoritative.
5. In standard mode, ask for explicit confirmation after a successful dry run.
   If the user explicitly requested `autopilot`, proceed after the successful
   dry run without a second confirmation. Run the same command without
   `-WhatIf`, without changing the file list or run name, and with
   `-Confirm:$false` so the skill's confirmation is not duplicated:

   ```powershell
   & "$HOME\.copilot\skills\backup-staging-files\Backup-StagingFiles.ps1" `
       -RepositoryRoot (Get-Location).Path `
       -IncludePaths $deploymentPaths `
       -BackupRunName $backupRunName `
       -Confirm:$false
   ```

   Direct script callers retain PowerShell's normal high-impact confirmation
   behavior when `-Confirm:$false` is not supplied.
6. Report the created backup directory, manifest path, every backed-up file,
   remote path, local path, and verified byte size. Do not display file
   contents.
7. Only after the backup succeeds should `/deploy-files-staging` be allowed to
   upload the same exact file list.

## Script behavior

`Backup-StagingFiles.ps1`:

- Reuses the deploy skill's saved remote root, Windows Credential Manager
  credential, pinned SFTP host key, and bundled WinSCP library.
- Rejects traversal, absolute repository paths, missing local paths, paths
  outside `Tireweb Sites\Web`, and sensitive/secret files.
- Performs a remote preflight for every requested file before downloading.
- Creates a new timestamped run directory under the configured backup root.
- Preserves the remote `Tireweb Sites\Web`-relative path beneath that run
  directory.
- Writes `manifest.json` with the remote/local mappings, status, timestamps, and
  verified sizes.
- Verifies every downloaded file against the remote size.
- Leaves a failed run manifest marked `failed` if a transfer stops partway
  through; it does not delete partial backups.

The skill depends on the installed `deploy-files-staging` skill for SFTP
authentication and WinSCP. It intentionally contains no credentials,
certificates, or third-party binaries so it can be published safely to GitHub.

## Safety requirements

- Never request, print, store, or pass the SFTP password in chat or source
  control.
- Never read or modify FileZilla's `sites.xml`.
- Never delete remote files.
- Never silently continue after a missing remote file or size mismatch.
- Never deploy automatically; backup and deployment remain separate steps.
