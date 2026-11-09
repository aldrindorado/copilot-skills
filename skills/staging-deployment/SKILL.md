---
name: staging-deployment
description: Deploy Ezytire changes to staging through one manifest-bound SFTP workflow. Supports committed and uncommitted feature work, deployment from another session's checkout, explicit paths or filenames, Git log selections, and rebuilt project DLLs. Use when asked to deploy, upload, or preview staging changes.
argument-hint: '[remote directory] [uncommitted|branch|all] [base ref] [file paths or filenames] [autopilot]'
---

Use the sibling `Deploy-Staging.ps1` script. It uploads only files beneath
`Tireweb Sites\Web`, maps that folder to the chosen staging directory, and never
deletes remote files. This is the deployment workflow for web files and built
DLLs; do not invoke the retired `deploy-files-staging` skill.

Resolve `$deploymentSkillRoot` from this loaded skill's base directory. Installed
skills usually live at `$HOME\.copilot\skills\staging-deployment`; when working
in the shared repository, the base is its `skills\staging-deployment` directory.
Do not assume the installed path exists:

```powershell
$deploymentSkillRoot = '<base directory supplied by the loaded skill>'
```

## Resolve the source and target

Use the current checkout for a direct request. When a parent delegates deployment
from a developer session, use the supplied absolute `RepositoryRoot`, not the
deploying session's checkout. Do not switch, reset, commit, stash, or merge the
developer's worktree.

Ask for the staging directory unless the request or authorized parent already
supplies it. Accept `EOSB-757` or `/EOSB-757`. Reuse a target only within the same
chat, and replace it when the user names another target.

```powershell
. (Join-Path $deploymentSkillRoot 'StagingDeploymentSettings.ps1')
$sessionId = '<current app chat/session ID>'
$remoteRoot = Get-StagingDeploymentRemoteRoot -SessionId $sessionId
# If the request supplies a target, or after asking when none is saved:
$remoteRoot = Set-StagingDeploymentRemoteRoot -SessionId $sessionId -RemoteRoot $chosenRemoteRoot
$sourceRoot = '<authorized absolute source checkout>'
```

Use the actual session ID from app context when `COPILOT_SESSION_ID` is absent.
Never invent one or use a user-wide settings file. Helpers also accept an
explicit `SettingsPath` inside the current session's artifacts directory.
Do not clear settings on skill loading. For delegated work, pass the target
explicitly; another session does not need access to the parent's target settings.

Do not change the configured SFTP host, username, or pinned key unless the user
explicitly requests it.

## Choose one selection mode

| Request | Preview options | Uploaded content |
| --- | --- | --- |
| Deploy uncommitted changes (default) | `-ChangeScope Uncommitted` | Current staged, unstaged, and untracked files |
| Deploy all committed feature changes | `-ChangeScope Branch -BaseRef <intended base>` | Exported current HEAD snapshot; dirty edits are excluded |
| Deploy committed and uncommitted feature work | `-ChangeScope All -BaseRef <intended base>` | Union of branch and working-tree paths, using current working-tree bytes |
| Deploy specified files | `-IncludePaths $paths` | Existing working-tree files, even unchanged or ignored DLLs |
| Deploy paths selected by a Git log/date expression | `-GenerateListFromGitLogArgs $logArgs` | Selected paths from an exported current HEAD snapshot |

Resolve the intended base from the request or established branch context. Ask
when it is unclear; do not silently compare against the wrong base. Branch scope
uses the net diff `base...HEAD`, not the union of every commit's filenames.
Git log dates select paths, not historical versions. To deploy an older release,
provide a source checkout whose HEAD is that release.

Kickoff file lists may contain repository-relative paths, paths relative to
`Tireweb Sites\Web`, or bare filenames. Preserve entries with spaces as single
arguments. A bare filename resolves only when exactly one web file matches.
If ambiguous, show the candidate paths and ask which one the user intended.
Missing explicit files block deployment. Do not guess, use wildcards, or
silently omit requested files. Explicit source project paths are accepted and
converted to supported DLLs rather than uploaded directly.

Do not combine selection modes. Manifest replay is a separate mode and does
not scan Git, resolve filenames, export snapshots, or rebuild projects.

## Prepare and preview

For a new release, choose a unique manifest path outside the source repository:

```powershell
$manifestDirectory = '<current session artifacts directory>'
$manifestPath = Join-Path $manifestDirectory ("release-{0}.json" -f [guid]::NewGuid().ToString('N'))

& (Join-Path $deploymentSkillRoot 'Deploy-Staging.ps1') `
    -RepositoryRoot $sourceRoot `
    -RemoteRoot $remoteRoot `
    -ChangeScope All -BaseRef $baseRef `
    -CreateDeploymentManifestPath $manifestPath `
    -WhatIf
```

Replace the selection options with those from the table. An explicit-list
example is:

```powershell
-IncludePaths 'App_Modules\248-GMapLiteStore\EOv2.ascx','GoogleReviews.js','Tireweb Sites\Web\Bin\Customization.dll'
```

The preview rebuilds affected supported projects using `Build-StagingProjects.ps1`
and stages only their expected Release DLLs beneath the content root's `Web\Bin`.
It creates missing `Bin` directories and restores existing `packages.config`
dependencies only when package directories are missing. Build errors or missing
expected DLLs block the preview. Do not deploy stale outputs or build the full
solution when a mapped project covers the change.

| Source prefix | Project | Staged DLL |
| --- | --- | --- |
| `Charlie/` | `Charlie\Charlie.csproj` | `Charlie.dll` |
| `Tireweb Business/` | `Tireweb Business\Tireweb Business.csproj` | `Tireweb Business.dll` |
| `Poindexter/` | `Poindexter\Poindexter.csproj` | `Poindexter.dll` |
| `Wonky Wheel/Wonky/` | `Wonky Wheel\Wonky\Wonky.csproj` | `Wonky.dll` |
| `Tireweb Sites/Sites/` | `Tireweb Sites\Sites\Sites.csproj` | `Tireweb.Sites.dll` |
| `Customization/` | `Customization\Customization.csproj` | `Customization.dll` |

Each selected mapping is invoked once in this dependency order. MSBuild may
build its project references. Do not upload dependency DLLs, PDBs, documentation,
or configuration files merely because a build produced them.

Committed previews export HEAD with `git archive` to `<manifest path>.source`;
they do not modify branches or register Git worktrees. Builds run inside that
snapshot. Keep it until deployment finishes. Ignored local assemblies and
packages are not copied from a dirty developer checkout; missing build inputs
must be resolved explicitly before another preview.

Always show the source checkout, commit, content mode, staging directory,
complete sorted final upload queue with local-to-remote mappings, and every
excluded or removed path with its reason. Use the preview's final queue, including
rebuilt DLLs, not the raw source-change list. An empty queue means no approval
prompt and no upload.

```text
Remote root: /EOSB-757

Upload queue:
1. `Tireweb Sites/Web/App_Modules/example.ascx` -> /EOSB-757/App_Modules/example.ascx
2. `Tireweb Sites/Web/Bin/Customization.dll` -> /EOSB-757/Bin/Customization.dll
```

The version 2 manifest records the authorized checkout, content root/mode,
release commit, SFTP target/connection, verification mappings, approved paths,
and SHA-256 hashes. Existing manifests cannot be overwritten. Preserve the
`Manifest SHA256` emitted by preview; it binds the approved document to upload.
Older manifests require a fresh preview and approval.

Sensitive files are blocked in every mode, including manifest replay:
`WebsiteOptions.config`, `App_Files\*.config`, `.env` variants, secrets and
appsettings JSON variants, certificates, and private keys. Traversal and
symbolic-link/junction paths are rejected.

## Approve and deploy

Standard mode requires explicit user confirmation after preview and after the
complete queue is shown. Autopilot skips only that confirmation, and only when
the user or authorized parent explicitly requests it for this release.
Target selection, scope validation, preview, and verification remain required.

```powershell
& (Join-Path $deploymentSkillRoot 'Deploy-Staging.ps1') `
    -RepositoryRoot $sourceRoot `
    -RemoteRoot $remoteRoot `
    -DeploymentManifestPath $manifestPath `
    -DeploymentManifestSha256 $approvedManifestHash
```

Do not recalculate the queue or rebuild between preview and upload. The script
rejects changed manifests, checkout HEAD, target/connection, or source bytes.
It locks each source against writers while rehashing and transferring it, then
checks the remote byte size. Approval does not imply an atomic multi-file
release: an interrupted upload can leave earlier files deployed.

When static assets are included, obtain their public staging URLs before
preview and pass exact repository-path-to-URL mappings:

```powershell
-VerificationAssets 'Tireweb Sites/Web/Scripts/example.js|https://<staging-site>/Scripts/example.js'
```

Mappings are recorded in the manifest and reused during upload. Verification
uses a cache-bypass query and compares the downloaded response hash with the
approved bytes. Do not request browser URLs for server-side source files.

## Delegated deployment

A parent may prepare the manifest itself, or tell a deployment child to prepare
one from the developer's authorized checkout with the required selection mode.
For committed plus dirty feature work, explicitly select `All`, not the default.

When handing off an already previewed release, supply the absolute source
checkout, manifest path, manifest SHA-256, normalized staging root, and release
authorization. The deployment child runs exactly one manifest replay preview
and one manifest revalidation/upload command. Add `-WhatIf` to the upload
example for replay preview. Do not substitute the child's checkout, clear the
parent's settings, or probe/rebuild each asset separately. A different host must
not pretend it can read the original host's paths; stop and resolve access.

`backup-staging-files`, `deploy-staging-qa-feature`, and `reset-staging-folder`
may select paths or back up the approved release, but all uploads use this
engine. Backup takes the explicit remote root and final manifest asset paths.

## Finish or stop

Report every deployed repository-relative and remote path. On failure, report
the error and any possible partial upload; resolve the cause before retrying.
Never rerun a successful upload to gather evidence. After completion, decline,
or a failed release that will not be retried, remove only that release's exact
exported `.source` directory from the session artifacts. Never delete the
developer checkout. Keep the manifest as the deployment record.

## Authentication

Use the current user's Windows Credential Manager entry and bundled WinSCP.
Before the first deployment, ask the user to run the credential helper in an
interactive local PowerShell terminal:

```powershell
& (Join-Path $deploymentSkillRoot 'Set-StagingCredential.ps1')
```

The credential prompt is the only place to enter the password. Never put it in
chat, source control, command lines, configuration files, or FileZilla's
`sites.xml`. Do not add `shell` or `bash` to this skill's allowed tools.
