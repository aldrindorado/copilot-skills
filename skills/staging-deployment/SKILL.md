---
name: staging-deployment
description: Safely deploy Ezytire web files to staging through SFTP using the operator's assigned account. Use when asked to deploy, upload, or preview changes on staging.
---

Use the sibling `Deploy-Staging.ps1` script from the Ezytire repository root.
It deploys only files under `Tireweb Sites\Web`, maps them to a selected remote
staging directory, preserves paths with spaces and special characters, and
never deletes remote files.

Every upload requires an immutable deployment manifest. The manifest fixes the
approved file list, staging paths, release commit, and SHA-256 hashes. The
script validates it before upload and hashes each source file again immediately
before transfer.

## One-time workstation setup

Each operator needs an individual staging SFTP account assigned by the
staging-server administrator. Never share an account or enter a password in
chat, source control, command lines, or configuration files.

Download the official WinSCP .NET automation package from
<https://winscp.net/eng/docs/library_install>, then extract its contents into
this skill's `WinSCP` directory. Keep `WinSCP.exe` and `WinSCPnet.dll` in the
same directory and retain the package's license files. The package is not
stored in this repository.

Save the assigned account password in Windows Credential Manager:

```powershell
& "$HOME\.copilot\skills\staging-deployment\Set-StagingCredential.ps1" -UserName $userName
```

The staging connection is `52.44.202.235:22`. Its pinned server fingerprint is:

```text
ssh-rsa 1024 Yxo6FcvF30RCXrUQYJep89aRHkX8a6MAMY2XwFXPV6w
```

## 1. Resolve authority and target

For a direct deployment, clear the target saved by a previous chat, ask for
the remote directory unless it is already supplied, and save its normalized
form. Reuse it only for later deployments in the same chat.

```powershell
. "$HOME\.copilot\skills\staging-deployment\StagingDeploymentSettings.ps1"
Remove-StagingDeploymentRemoteRoot
$remoteRoot = Set-StagingDeploymentRemoteRoot -RemoteRoot $chosenRemoteRoot
$sourceRoot = (Get-Location).Path
```

For a parent-authorized deployment, its checkout, remote root, and manifest
are authoritative. Do not substitute the local checkout or select another
target.

## 2. Select scope and preview

Direct deployments discover added and modified uncommitted web files by
default. Use `-IncludePaths` for an explicit subset, or
`-ChangeScope Branch -BaseRef development` for committed branch changes.
Before branch preview, explain any changed files outside `Tireweb Sites\Web`
and ask whether to deploy web files only or build and deploy their artifacts.

Create a manifest outside the repository and preview once:

```powershell
$manifestDirectory = Join-Path $env:LOCALAPPDATA 'GitHub Copilot\staging-deployment'
$manifestPath = Join-Path $manifestDirectory ("release-{0}.json" -f [System.Guid]::NewGuid().ToString('N'))

& "$HOME\.copilot\skills\staging-deployment\Deploy-Staging.ps1" `
    -RepositoryRoot $sourceRoot `
    -RemoteRoot $remoteRoot `
    -UserName $userName `
    -CreateDeploymentManifestPath $manifestPath `
    -WhatIf
```

Parent-authorized releases preview their supplied manifest with
`-DeploymentManifestPath $manifestPath` instead. Do not combine a manifest
with `-IncludePaths`.

## 3. Approve and upload

Standard mode requires explicit user confirmation after the preview. Autopilot
is allowed only with explicit user or parent authorization; it skips only that
confirmation.

```powershell
& "$HOME\.copilot\skills\staging-deployment\Deploy-Staging.ps1" `
    -RepositoryRoot $sourceRoot `
    -RemoteRoot $remoteRoot `
    -UserName $userName `
    -DeploymentManifestPath $manifestPath
```

For browser-served static assets, require a public staging URL and add:

```powershell
-VerificationAssets 'Tireweb Sites/Web/path/to/asset.js|https://staging.example.com/path/to/asset.js'
```

The script cache-bypass fetches that URL and compares its SHA-256 hash with the
manifest. Do not use it for server-side source files that are not directly
served.

## 4. Report or stop

Report all deployed repository-relative and remote paths. On failure, report
the emitted error and resolve the cause before retrying. Do not rerun a
successful command only to collect extra evidence.
