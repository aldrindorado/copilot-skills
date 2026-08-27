---
name: staging-deployment-custom
description: Deploy a user-supplied list of Ezytire web files to staging through SFTP, with optional generation of the list from a git log expression. Use when asked to deploy a custom set of files, a generated file list, or a date-range-based set of changes to staging.
---

Use the sibling `Deploy-StagingCustom.ps1` script from the Ezytire repository root
to deploy a specific list of files under `Tireweb Sites\Web` to staging. The script
maps that local folder directly to a user-selected remote staging directory, skips
files outside the web root, and verifies each uploaded file's remote size.

## Deployment workflow

1. For a direct deployment chat, clear the previously saved remote directory at
   the beginning of skill loading, then load the settings helper:

   ```powershell
   . "$HOME\.copilot\skills\staging-deployment-custom\StagingDeploymentSettings.ps1"
   Remove-StagingDeploymentRemoteRoot
   ```

2. For a direct deployment, ask the user for the remote staging directory that
   should be used for this chat session before previewing files, unless the
   user already provided one in the deployment request. Accept either
   `EOSB-757` or `/EOSB-757`; normalize it before use.
3. For a direct deployment, save the chosen directory locally, outside the
   repository:

   ```powershell
   $remoteRoot = Set-StagingDeploymentRemoteRoot -RemoteRoot $chosenRemoteRoot
   ```

4. For succeeding direct deployments in the same chat session, reuse that saved
   directory without asking again.
5. If the user asks to change directories, or provides a new directory in a
   later invocation, use the new value and immediately resave it with
   `Set-StagingDeploymentRemoteRoot` before previewing.
6. Resolve the files to deploy. The script accepts either:

   - An explicit list via `-IncludePaths`, or
   - Git log arguments via `-GenerateListFromGitLogArgs` that the script passes
     to `git log --name-only --pretty=format:`.

   Examples:

   ```powershell
   # Explicit list
   & "$HOME\.copilot\skills\staging-deployment-custom\Deploy-StagingCustom.ps1" `
       -RepositoryRoot (Get-Location).Path `
       -RemoteRoot $remoteRoot `
       -IncludePaths 'Tireweb Sites/Web/App_Modules/248-GMapLiteStore/BrakesPlus.ascx','Tireweb Sites/Web/App_Modules/248-GMapLiteStore/Default.ascx.cs' `
       -WhatIf
   ```

   ```powershell
   # Generated from git log date range on development
   & "$HOME\.copilot\skills\staging-deployment-custom\Deploy-StagingCustom.ps1" `
       -RepositoryRoot (Get-Location).Path `
       -RemoteRoot $remoteRoot `
       -GenerateListFromGitLogArgs 'development','--since=2026-08-01','--until=2026-08-08' `
       -WhatIf
   ```

7. Run the preview with the chosen directory and `-WhatIf`.
8. Summarize the files selected by the preview. Do not upload files based only
   on a request to preview or inspect the deployment.
9. Select the confirmation behavior:
   - **Standard mode (default):** ask the user for explicit confirmation after
     previewing the selected files.
   - **Autopilot mode:** when the user explicitly requests `autopilot`, proceed
     directly from a successful preview to the real upload. State the selected
     files and remote root before uploading, but do not ask a second confirmation
     question.
10. Autopilot mode only skips the post-preview confirmation. It never skips:
    - remote directory selection or normalization;
    - the preview; or
    - scope validation.
11. After confirmation in standard mode, or immediately after preview in
    autopilot mode, run the same command without `-WhatIf`:

    ```powershell
    & "$HOME\.copilot\skills\staging-deployment-custom\Deploy-StagingCustom.ps1" `
        -RepositoryRoot (Get-Location).Path `
        -RemoteRoot $remoteRoot `
        -IncludePaths '...'
    ```

12. Report success or the error emitted by the script. Always display the full
    list of files uploaded in that deployment, with local repository-relative
    and remote paths. Do not retry a failed upload without first resolving and
    explaining the failure.

## How file lists are resolved

- `-IncludePaths` accepts an array of repository-relative paths. Paths are
  normalized, deduplicated, checked for directory traversal, verified to exist
  on disk, and limited to files under `Tireweb Sites\Web`.
- `-GenerateListFromGitLogArgs` accepts an array of arguments passed after
  `git log --name-only --pretty=format:`. It runs:

  ```powershell
  git log --name-only --pretty=format: <args>
  ```

  The output is deduplicated and then validated the same way as `-IncludePaths`.
- The two parameters cannot be combined.
- Files outside `Tireweb Sites\Web` are reported as warnings and skipped; the
  script does not build or deploy source-layer artifacts.
- Sensitive and secret files are blocked from deployment. The exact blocklist
  includes but is not limited to:
  - `WebsiteOptions.config`
  - `App_Files\*.config`
  - `.env` and `.env.*`
  - `secrets.json` and `secrets.*.json`
  - `appsettings.json` and `appsettings.*.json`
  - Certificate and key files (`.pfx`, `.key`, `.pem`, `.cer`, `.crt`)

  If a blocked file is included, the deployment stops with an error before any
  upload occurs.

## SFTP authentication

The staging connection uses `aldrin.d@52.44.202.235:22` with the password
from the current user's Windows Credential Manager. It uses the bundled
portable WinSCP .NET library and pins this server fingerprint:

```text
ssh-rsa 1024 Yxo6FcvF30RCXrUQYJep89aRHkX8a6MAMY2XwFXPV6w
```

If the credential has not been saved, direct the user to run the existing
staging credential helper:

```powershell
& "$HOME\.copilot\skills\staging-deployment\Set-StagingCredential.ps1"
```

The password must never be entered in chat, source control, a command line, or
a configuration file. Do not read or modify FileZilla's `sites.xml`.

## Safety

- Do not add `shell` or `bash` to this skill's `allowed-tools`.
- The script uploads the requested files only; it deliberately does not delete
  files from the staging server.
- Autopilot mode requires explicit user authorization for that deployment. Never
  infer it from a previous unrelated deployment.
- Do not change the configured host or username unless the user explicitly
  requests an override.
- The directory selected by the user is remembered for the current chat session
  and is reused automatically unless the user explicitly changes it.
