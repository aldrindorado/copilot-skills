---
name: staging-deployment
description: Safely deploy Ezytire web files to staging through SFTP, including uncommitted changes, committed branch changes, or parent-authorized manifest assets. Use when asked to deploy, upload, or preview changes on staging.
---

Use the sibling `Deploy-Staging.ps1` script from the Ezytire repository root.
It deploys only files under `Tireweb Sites\Web`, maps them to a selected remote
staging directory, preserves paths with spaces and special characters, and
never deletes remote files.

Every upload requires an immutable deployment manifest. The manifest fixes the
approved file list, staging paths, release commit, and SHA-256 hashes. The
script validates it before upload and hashes each source file again immediately
before transfer.

## 1. Resolve the deployment authority and target

For a direct deployment, reset any target saved by a previous chat, then ask
for the remote directory unless the request already names one. Accept
`EOSB-757` or `/EOSB-757`; save its normalized form and reuse it for later
deployments in this chat unless the user changes it.

```powershell
. "$HOME\.copilot\skills\staging-deployment\StagingDeploymentSettings.ps1"
Remove-StagingDeploymentRemoteRoot
$remoteRoot = Set-StagingDeploymentRemoteRoot -RemoteRoot $chosenRemoteRoot
$sourceRoot = (Get-Location).Path
```

For a parent-authorized deployment, the parent-supplied checkout, remote root,
and manifest are authoritative. Do not clear the saved root, ask for another
directory, or use the deployment session's checkout. Save the supplied root
once with `Set-StagingDeploymentRemoteRoot`.

Do not change the configured SFTP host or username without an explicit user
request.

## 2. Select the release scope

Direct deployments discover added and modified uncommitted web files by
default. Use these preview options when applicable:

```powershell
# Explicit files
-IncludePaths 'Tireweb Sites/Web/App_Modules/248-GMapLiteStore/EOv2.ascx'

# Committed changes only
-ChangeScope Branch -BaseRef development
```

Before previewing branch changes, identify source changes outside
`Tireweb Sites\Web`. Explain that they have no FileZilla-style mapping, then
ask whether to deploy the web files only or build and deploy the required
artifacts. Stop for clarification when the intended web scope is ambiguous.

Parent-authorized releases use the supplied manifest and do not scan Git
changes. Do not combine `-DeploymentManifestPath` with `-IncludePaths`.

## 3. Preview and create the immutable manifest

For a direct deployment, create the manifest outside the repository and run
one preview command. Include the selected scope options from step 2 when
needed.

```powershell
$manifestDirectory = Join-Path $env:LOCALAPPDATA 'GitHub Copilot\staging-deployment'
$manifestPath = Join-Path $manifestDirectory ("release-{0}.json" -f [System.Guid]::NewGuid().ToString('N'))

& "$HOME\.copilot\skills\staging-deployment\Deploy-Staging.ps1" `
    -RepositoryRoot $sourceRoot `
    -RemoteRoot $remoteRoot `
    -CreateDeploymentManifestPath $manifestPath `
    -WhatIf
```

For a parent-authorized release, use its existing manifest:

```powershell
& "$HOME\.copilot\skills\staging-deployment\Deploy-Staging.ps1" `
    -RepositoryRoot $sourceRoot `
    -RemoteRoot $remoteRoot `
    -DeploymentManifestPath $manifestPath `
    -WhatIf
```

Report the selected files, local-to-remote mappings, and manifest path. A
preview never authorizes an upload by itself.

## 4. Approve and upload

In standard mode, obtain explicit user confirmation after a successful preview.
In autopilot mode, proceed only when the user or parent explicitly authorizes
autopilot; it skips only the confirmation, never target selection, scope
validation, or preview.

Upload immediately after the approved preview:

```powershell
& "$HOME\.copilot\skills\staging-deployment\Deploy-Staging.ps1" `
    -RepositoryRoot $sourceRoot `
    -RemoteRoot $remoteRoot `
    -DeploymentManifestPath $manifestPath
```

When the release includes a browser-served static asset, require its public
staging URL and add a verification mapping. The tool adds a cache-bypass query
string, downloads the response, and compares its SHA-256 hash to the manifest.
Do not use this option for server-side source files that are not directly
served.

```powershell
-VerificationAssets 'Tireweb Sites/Web/App_Modules/248-GMapLiteStore/Scripts/GoogleReviews.js|https://eo-qa1.tireco-op.com/App_Modules/248-GMapLiteStore/Scripts/GoogleReviews.js?v=6'
```

Parent-authorized deployments use exactly one combined preview command and one
combined revalidation-and-upload command. Do not issue standalone probes for
their manifest, hashes, target root, or scope.

## 5. Report or stop

On success, report every deployed repository-relative and remote path. On
failure, report the emitted error and resolve its cause before trying again.
Never rerun a successful command only to gather extra evidence.

## Authentication

The connection is `aldrin.d@52.44.202.235:22`, using the current user's
Windows Credential Manager entry and the bundled WinSCP library. The pinned
server fingerprint is:

```text
ssh-rsa 1024 Yxo6FcvF30RCXrUQYJep89aRHkX8a6MAMY2XwFXPV6w
```

Before the first deployment, open an interactive local PowerShell terminal:

```powershell
& "$HOME\.copilot\skills\staging-deployment\Set-StagingCredential.ps1"
```

The credential prompt is the only place to enter the password. Never place it
in chat, source control, command lines, configuration files, or FileZilla's
`sites.xml`.
