---
name: deploy-files-staging
description: Deploy a user-supplied list of Ezytire web files and rebuilt project DLLs to staging through SFTP, with optional generation of the list from a git log expression. Use when asked to deploy a custom set of files, a generated file list, or a date-range-based set of changes to staging.
---

Use the sibling scripts from the Ezytire repository root:

- `Build-StagingCustomProjects.ps1` rebuilds only supported projects affected by
  the selected source paths and stages their Release DLLs in
  `Tireweb Sites\Web\Bin`.
- `Deploy-StagingCustom.ps1` deploys a specific list of files under
  `Tireweb Sites\Web` to staging. It maps that local folder directly to a
  user-selected remote staging directory and verifies each uploaded file's
  remote size.

## Deployment workflow

1. For a direct deployment chat, clear the previously saved remote directory at
   the beginning of skill loading, then load the settings helper:

   ```powershell
   . "$HOME\.copilot\skills\deploy-files-staging\StagingDeploymentSettings.ps1"
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
6. Resolve the complete changed-path list. The deployment script accepts either:

   - An explicit list via `-IncludePaths`, or
   - Git log arguments via `-GenerateListFromGitLogArgs` that the script passes
     to `git log --name-only --pretty=format:`.

   Examples:

   ```powershell
   # Explicit list
   & "$HOME\.copilot\skills\deploy-files-staging\Deploy-StagingCustom.ps1" `
       -RepositoryRoot (Get-Location).Path `
       -RemoteRoot $remoteRoot `
       -IncludePaths 'Tireweb Sites/Web/App_Modules/248-GMapLiteStore/BrakesPlus.ascx','Tireweb Sites/Web/App_Modules/248-GMapLiteStore/Default.ascx.cs' `
       -WhatIf
   ```

   ```powershell
   # Generated from git log date range on development
   & "$HOME\.copilot\skills\deploy-files-staging\Deploy-StagingCustom.ps1" `
       -RepositoryRoot (Get-Location).Path `
       -RemoteRoot $remoteRoot `
       -GenerateListFromGitLogArgs 'development','--since=2026-08-01','--until=2026-08-08' `
       -WhatIf
   ```

7. Classify paths outside `Tireweb Sites\Web`. If any belong to a supported
   project, run `Build-StagingCustomProjects.ps1` once with the complete
   changed-path list. The helper rebuilds each affected project at most once in
   Release configuration and copies its expected DLL into
   `Tireweb Sites\Web\Bin`.

   ```powershell
   $preparedDlls = @(
       & "$HOME\.copilot\skills\deploy-files-staging\Build-StagingCustomProjects.ps1" `
           -RepositoryRoot (Get-Location).Path `
           -ChangedPaths $changedPaths
   )

   $webPaths = @(
       $changedPaths |
           Where-Object { $_ -like 'Tireweb Sites/Web/*' }
   )
   $deploymentPaths = @($webPaths) + @($preparedDlls.WebRelativePath)
   ```

   Treat every build error or missing expected DLL as blocking. Do not deploy a
   stale or partial build. Report warnings, but proceed only when MSBuild exits
   successfully and all expected DLLs were staged. Do not build the full
   solution when a mapped smaller project covers the source changes.
8. Run the deployment preview with the chosen directory, the explicit
   `$deploymentPaths` queue, and `-WhatIf`. Do not rebuild between preview and
   upload; the confirmed upload must use the exact staged DLL that was previewed.
9. After a successful preview, and before asking for confirmation or uploading
   anything, always present the complete final upload queue in this exact
   review format:

   ```text
   Remote root: /EOSB-757

   Upload queue:
   1. `Tireweb Sites/Web/path/file.ext`
   2. `Tireweb Sites/Web/path/other.ext`
   ```

   Use a numbered Markdown list with one complete repository-relative
   deployment path per item, enclosed in inline code. Normalize displayed
   paths to `/` separators and sort them deterministically by the complete
   path. Build this list from the preview's final deployable queue, not from
   the raw changed-path list, so it includes every staged DLL such as
   `Tireweb Sites/Web/Bin/Customization.dll` and excludes files skipped by
   validation. Keep the remote root on its own line outside the numbered list.
   If the final queue is empty, report `Upload queue: empty` and do not ask for
   confirmation or deploy.
10. Select the confirmation behavior only after displaying that final queue:
   - **Standard mode (default):** ask the user for explicit confirmation after
     the queue is displayed.
   - **Autopilot mode:** when the user explicitly requests `autopilot`, display
     the same queue and remote root, then proceed directly to the real upload.
     Do not add a confirmation prompt.
11. Autopilot mode only skips the post-preview confirmation. It never skips:
    - remote directory selection or normalization;
    - the preview; or
    - scope validation.
12. After confirmation in standard mode, or immediately after displaying the
    queue in autopilot mode, run the same command without `-WhatIf`:

    ```powershell
    & "$HOME\.copilot\skills\deploy-files-staging\Deploy-StagingCustom.ps1" `
        -RepositoryRoot (Get-Location).Path `
        -RemoteRoot $remoteRoot `
        -IncludePaths '...'
    ```

13. Report success or the error emitted by the script. Always display the full
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
- Supported source paths are converted to DLL deployment artifacts by
  `Build-StagingCustomProjects.ps1`:

  | Changed-path prefix | Project | Staged Release DLL |
  | --- | --- | --- |
  | `Charlie/` | `Charlie\Charlie.csproj` | `Tireweb Sites\Web\Bin\Charlie.dll` |
  | `Tireweb Business/` | `Tireweb Business\Tireweb Business.csproj` | `Tireweb Sites\Web\Bin\Tireweb Business.dll` |
  | `Poindexter/` | `Poindexter\Poindexter.csproj` | `Tireweb Sites\Web\Bin\Poindexter.dll` |
  | `Wonky Wheel/Wonky/` | `Wonky Wheel\Wonky\Wonky.csproj` | `Tireweb Sites\Web\Bin\Wonky.dll` |
  | `Tireweb Sites/Sites/` | `Tireweb Sites\Sites\Sites.csproj` | `Tireweb Sites\Web\Bin\Tireweb.Sites.dll` |
  | `Customization/` | `Customization\Customization.csproj` | `Tireweb Sites\Web\Bin\Customization.dll` |

  Build each affected project at most once and preserve this dependency order.
  A source path outside these mappings remains excluded until its project and
  output DLL are explicitly added to the helper.
- Files outside `Tireweb Sites\Web` that do not match a supported project are
  reported as excluded and are not deployed.
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
