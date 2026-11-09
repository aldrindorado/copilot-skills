[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$RepositoryRoot = (Get-Location).Path,
    [string]$LocalRoot = 'Tireweb Sites\Web',
    [string[]]$IncludePaths,
    [string[]]$GenerateListFromGitLogArgs,
    [string]$DeploymentManifestPath,
    [string]$DeploymentManifestSha256,
    [string]$CreateDeploymentManifestPath,
    [string[]]$VerificationAssets,
    [ValidateSet('Uncommitted', 'Branch', 'All')]
    [string]$ChangeScope = 'Uncommitted',
    [string]$BaseRef = 'development',
    [string]$MSBuildPath,
    [string]$HostName = '52.44.202.235',
    [int]$Port = 22,
    [string]$UserName = 'aldrin.d',
    [Parameter(Mandatory = $true)]
    [string]$RemoteRoot,
    [string]$CredentialTarget = 'Ezytire.Staging.SFTP',
    [string]$WinScpDirectory,
    [string]$SshHostKeyFingerprint = 'ssh-rsa 1024 Yxo6FcvF30RCXrUQYJep89aRHkX8a6MAMY2XwFXPV6w'
)

<#
.SYNOPSIS
Uploads Ezytire web files to the staging server using WinSCP.

.DESCRIPTION
Select uncommitted changes, committed feature changes, their union, explicit
paths or filenames, or Git log paths. Committed selections export HEAD outside
the repository so dirty files cannot enter the release. Previews prepare required
project DLLs and a version 2 manifest binding source, target, paths and hashes.
Uploads require the approved manifest and its SHA-256, revalidate every file,
and never delete remote files. Authentication uses Windows Credential Manager.
Remote size checks and optional public-asset hashes verify the uploaded release.

.EXAMPLE
$manifestPath = Join-Path $env:TEMP 'ezytire-staging-release.json'
& "$HOME\.copilot\skills\staging-deployment\Deploy-Staging.ps1" -RepositoryRoot (Get-Location).Path -RemoteRoot '/EOSB-757' -CreateDeploymentManifestPath $manifestPath -WhatIf
& "$HOME\.copilot\skills\staging-deployment\Deploy-Staging.ps1" -RepositoryRoot (Get-Location).Path -RemoteRoot '/EOSB-757' -DeploymentManifestPath $manifestPath -DeploymentManifestSha256 '<hash emitted by preview>'

#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WinScpDirectory)) {
    $WinScpDirectory = Join-Path $PSScriptRoot 'WinSCP'
}

function Get-GitFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $quoteArgument = {
        param([string]$Value)

        if ($Value -notmatch '[\s"]') {
            return $Value
        }

        $escapedValue = [System.Text.RegularExpressions.Regex]::Replace($Value, '(\\*)"', '$1$1\"')
        $escapedValue = [System.Text.RegularExpressions.Regex]::Replace($escapedValue, '(\\+)$', '$1$1')
        return '"' + $escapedValue + '"'
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'git'
    $startInfo.Arguments = (@('-C', $RepositoryRoot) + $Arguments | ForEach-Object { & $quoteArgument $_ }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $null = $process.Start()
    $output = New-Object System.IO.MemoryStream
    $process.StandardOutput.BaseStream.CopyTo($output)
    $errorOutput = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $errorOutput"
    }

    $outputText = [System.Text.Encoding]::UTF8.GetString($output.ToArray())
    $output.Dispose()
    return @($outputText.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries))
}

function Assert-NotSensitivePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $path = $RelativePath.Replace('\', '/')
    $name = [System.IO.Path]::GetFileName($path)
    if ($name -eq 'WebsiteOptions.config' -or
        $name -match '^\.env($|\.)|^(secrets|appsettings)(\..*)?\.json$|\.(pfx|key|pem|cer|crt)$' -or
        $path -match '(^|/)App_Files/.*\.config$') {
        throw "Refusing to deploy sensitive file: $RelativePath"
    }
}

function Resolve-IncludePaths {
    param([string[]]$Paths, [string]$Root, [string]$WebRoot)

    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            throw 'IncludePaths cannot contain an empty path.'
        }
        $normalized = $path.Trim().Replace('\', '/')
        $null = Get-LocalFilePath -RepositoryRoot $Root -RelativePath $normalized
        if (-not $normalized.Contains('/')) {
            $matches = @(Get-ChildItem -LiteralPath $WebRoot -File -Recurse |
                Where-Object { $_.Name -eq $normalized })
            if ($matches.Count -eq 0) {
                throw "No deployable file matches '$path'."
            }
            if ($matches.Count -gt 1) {
                $candidates = @($matches | ForEach-Object { $_.FullName.Substring($Root.Length + 1).Replace('\', '/') } | Sort-Object)
                throw "Ambiguous filename '$path'. Specify one of: $($candidates -join ', ')"
            }
            $normalized = $matches[0].FullName.Substring($Root.Length + 1).Replace('\', '/')
        }
        elseif (-not (Test-Path -LiteralPath (Get-LocalFilePath -RepositoryRoot $Root -RelativePath $normalized) -PathType Leaf)) {
            $normalized = $LocalRoot.Replace('\', '/').TrimEnd('/') + '/' + $normalized
        }
        $localPath = Get-LocalFilePath -RepositoryRoot $Root -RelativePath $normalized
        if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
            throw "The requested file does not exist: $path"
        }
        Assert-NotSensitivePath -RelativePath $normalized
        $normalized
    }
}

function Get-LocalFilePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $RelativePath = $RelativePath.Replace('\', '/')
    if ([System.IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|/)\.\.(/|$)' -or $RelativePath.Contains(':')) {
        throw "Refusing to deploy an unsafe repository path: $RelativePath"
    }

    $localPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($RelativePath -replace '/', '\')))
    $repositoryPrefix = $RepositoryRoot.TrimEnd('\') + '\'
    if (-not $localPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to deploy a file outside the repository: $RelativePath"
    }

    if ((Get-Item -LiteralPath $RepositoryRoot -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "Refusing to deploy through a symbolic link or junction source root: $RepositoryRoot"
    }
    $currentPath = $localPath
    while ($currentPath.Length -gt $RepositoryRoot.TrimEnd('\').Length) {
        if (Test-Path -LiteralPath $currentPath) {
            $item = Get-Item -LiteralPath $currentPath -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to deploy through a symbolic link or junction: $RelativePath"
            }
        }
        $currentPath = Split-Path -Path $currentPath -Parent
    }
    return $localPath
}

function Get-FileSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $hash = $algorithm.ComputeHash($stream)
        return -join ($hash | ForEach-Object { $_.ToString('x2') })
    }

    finally {
        $stream.Dispose()
        $algorithm.Dispose()
    }
}

function Write-DeploymentManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [object[]]$Files
    )

    $manifestFullPath = [System.IO.Path]::GetFullPath($ManifestPath)
    $repositoryPrefix = $RepositoryRoot.TrimEnd('\') + '\'
    if ($manifestFullPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Deployment manifests must be written outside the repository: $manifestFullPath"
    }

    $manifestDirectory = Split-Path -Path $manifestFullPath -Parent
    if (-not (Test-Path -LiteralPath $manifestDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $manifestDirectory -Force -WhatIf:$false | Out-Null
    }

    $releaseCommit = (& git -C $RepositoryRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to determine the deployment release commit.'
    }

    $assets = @(
        $Files |
            Sort-Object RelativePath |
            ForEach-Object {
                [PSCustomObject]@{
                    repository_source_path = $_.RelativePath
                    staging_upload_path = $_.DeploymentRelativePath
                    sha256 = $_.Sha256
                }
            }
    )
    $manifest = [PSCustomObject]@{
        schema_version = '2.0'
        release_commit = $releaseCommit
        source_repository_root = $RepositoryRoot
        source_root = $script:SourceRoot
        source_mode = $script:SourceMode
        local_root = $LocalRoot
        remote_root = $remoteRootPath
        host_name = $HostName
        port = $Port
        user_name = $UserName
        credential_target = $CredentialTarget
        ssh_host_key_fingerprint = $SshHostKeyFingerprint
        verification_assets = @($VerificationAssets | Where-Object { $_ })
        assets = $assets
    }
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $stream = [System.IO.File]::Open($manifestFullPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    try {
        $bytes = $utf8WithoutBom.GetBytes(($manifest | ConvertTo-Json -Depth 4))
        $stream.Write($bytes, 0, $bytes.Length)
        $algorithm = [System.Security.Cryptography.SHA256]::Create()
        try {
            $manifestHash = -join ($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
        }
        finally {
            $algorithm.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
    Write-Host "Wrote deployment manifest: $manifestFullPath"
    Write-Host ("Manifest SHA256: {0}" -f $manifestHash)
}

function Test-VerificationAssets {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Assets,

        [Parameter(Mandatory = $true)]
        [hashtable]$ExpectedHashes
    )

    foreach ($asset in $Assets) {
        $parts = $asset -split '\|', 2
        if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
            throw "VerificationAssets entries must use '<repository path>|<public URL>': $asset"
        }

        $repositoryPath = $parts[0].Trim().Replace('\', '/')
        if (-not $ExpectedHashes.ContainsKey($repositoryPath)) {
            throw "The verification asset is not part of this deployment: $repositoryPath"
        }

        $verificationUrl = $parts[1].Trim()
        $separator = if ($verificationUrl.Contains('?')) { '&' } else { '?' }
        $cacheBypassUrl = $verificationUrl + $separator + 'staging_deploy_verify=' + [System.Guid]::NewGuid().ToString('N')
        $webClient = New-Object System.Net.WebClient
        $algorithm = [System.Security.Cryptography.SHA256]::Create()
        try {
            $actualHash = -join ($algorithm.ComputeHash($webClient.DownloadData($cacheBypassUrl)) | ForEach-Object { $_.ToString('x2') })
        }
        finally {
            $algorithm.Dispose()
            $webClient.Dispose()
        }

        if ($actualHash -ne $ExpectedHashes[$repositoryPath]) {
            throw "Staging verification hash mismatch for '$verificationUrl'. Expected: $($ExpectedHashes[$repositoryPath]). Actual: $actualHash."
        }

        Write-Host "Staging verification passed: $verificationUrl"
    }
}

function ConvertTo-SftpPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($Path.IndexOf('"') -ge 0 -or $Path.IndexOf("`n") -ge 0 -or $Path.IndexOf("`r") -ge 0) {
        throw "Paths containing quotation marks or line breaks cannot be deployed safely: $Path"
    }

    return $Path.Replace('\', '/')
}

function Get-SftpParentPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $lastSlash = $Path.LastIndexOf('/')
    if ($lastSlash -le 0) {
        return '/'
    }

    return $Path.Substring(0, $lastSlash)
}

function Get-SftpDirectoryHierarchy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,

        [Parameter(Mandatory = $true)]
        [string]$RemoteRoot
    )

    $remoteRootPrefix = $RemoteRoot.TrimEnd('/') + '/'
    if ($Directory -ne $RemoteRoot -and -not $Directory.StartsWith($remoteRootPrefix, [System.StringComparison]::Ordinal)) {
        throw "Refusing to create a remote directory outside the selected remote root: $Directory"
    }

    $directories = @()
    $currentDirectory = $Directory
    while ($true) {
        $directories += $currentDirectory
        if ($currentDirectory -eq $RemoteRoot) {
            break
        }

        $currentDirectory = Get-SftpParentPath -Path $currentDirectory
    }

    return $directories
}

function Get-WinScpAssemblyPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $netFrameworkAssembly = Join-Path $Directory 'WinSCPnet.dll'
    $netStandardAssembly = Join-Path $Directory 'netstandard2.0\WinSCPnet.dll'
    $assemblyPath = $netFrameworkAssembly
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $assemblyPath = $netStandardAssembly
    }

    if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
        throw "WinSCP .NET assembly was not found: $assemblyPath"
    }

    return $assemblyPath
}

function Ensure-SftpDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [WinSCP.Session]$Session,

        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    try {
        $Session.ListDirectory($Directory) | Out-Null
    }
    catch [WinSCP.SessionRemoteException] {
        $Session.CreateDirectory($Directory)
    }
}

function Get-ManifestFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$LocalRootPrefix,

        [Parameter(Mandatory = $true)]
        [string]$RemoteRoot
    )

    $manifestFullPath = [System.IO.Path]::GetFullPath($ManifestPath)
    if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) {
        throw "The deployment manifest was not found: $manifestFullPath"
    }

    $manifestStream = [System.IO.File]::Open($manifestFullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        $script:ManifestDocumentHash = Get-FileSha256 -Path $manifestFullPath
        if (-not [string]::IsNullOrWhiteSpace($DeploymentManifestSha256) -and
            $script:ManifestDocumentHash -ne $DeploymentManifestSha256) {
            throw 'The deployment manifest changed after preview. Create and approve a new manifest.'
        }
        try {
            $manifest = Get-Content -LiteralPath $manifestFullPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "The deployment manifest is not valid JSON: $manifestFullPath"
        }
    }
    finally {
        $manifestStream.Dispose()
    }
    if ($manifest.schema_version -ne '2.0') {
        throw 'The deployment manifest must declare schema_version 2.0. Create and approve a new preview for older manifests.'
    }
    if ($manifest.source_repository_root -ne $RepositoryRoot -or
        $manifest.remote_root -cne $RemoteRoot -or
        $manifest.local_root -ne $LocalRoot -or
        $manifest.host_name -ne $HostName -or
        $manifest.port -ne $Port -or
        $manifest.user_name -ne $UserName -or
        $manifest.credential_target -ne $CredentialTarget -or
        $manifest.ssh_host_key_fingerprint -ne $SshHostKeyFingerprint) {
        throw 'The checkout, staging target, or connection does not match the approved deployment manifest.'
    }
    if ($manifest.source_mode -notin @('WorkingTree', 'Committed')) {
        throw 'The deployment manifest source_mode must be WorkingTree or Committed.'
    }
    $script:SourceMode = $manifest.source_mode
    $script:SourceRoot = [System.IO.Path]::GetFullPath([string]$manifest.source_root)
    if ($script:SourceMode -eq 'WorkingTree' -and $script:SourceRoot -ne $RepositoryRoot) {
        throw 'A working-tree manifest must use the authorized repository checkout.'
    }
    if ($script:SourceMode -eq 'Committed' -and $script:SourceRoot -ne ($manifestFullPath + '.source')) {
        throw 'A committed manifest must use its sibling committed snapshot.'
    }
    $LocalRootPrefix = (Join-Path $script:SourceRoot $LocalRoot).TrimEnd('\') + '\'
    $script:ManifestVerificationAssets = @($manifest.verification_assets)
    if ($VerificationAssets -and (@($VerificationAssets) -join "`n") -cne ($script:ManifestVerificationAssets -join "`n")) {
        throw 'VerificationAssets must match the approved deployment manifest.'
    }

    if ([string]::IsNullOrWhiteSpace($manifest.release_commit) -or $manifest.release_commit -notmatch '^[a-f0-9]{40}$') {
        throw 'The deployment manifest must declare a lowercase 40-character release_commit SHA.'
    }

    $headCommit = (& git -C $RepositoryRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $headCommit -ne $manifest.release_commit) {
        throw "The deployment checkout HEAD '$headCommit' does not match manifest release_commit '$($manifest.release_commit)'."
    }

    $assets = @($manifest.assets)
    if ($assets.Count -eq 0) {
        throw 'The deployment manifest must contain at least one asset.'
    }

    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $files = @()
    foreach ($asset in $assets) {
        $repositoryPath = [string]$asset.repository_source_path
        $stagingPath = [string]$asset.staging_upload_path
        $expectedHash = [string]$asset.sha256

        if ([string]::IsNullOrWhiteSpace($repositoryPath) -or [string]::IsNullOrWhiteSpace($stagingPath)) {
            throw 'Every deployment manifest asset must declare repository_source_path and staging_upload_path.'
        }

        if ($expectedHash -notmatch '^[a-f0-9]{64}$') {
            throw "The deployment manifest SHA-256 is invalid for '$repositoryPath'."
        }

        $normalizedRepositoryPath = $repositoryPath.Replace('\', '/')
        if (-not $paths.Add($normalizedRepositoryPath)) {
            throw "The deployment manifest contains the same repository path more than once: $repositoryPath"
        }

        Assert-NotSensitivePath -RelativePath $repositoryPath
        $localPath = Get-LocalFilePath -RepositoryRoot $script:SourceRoot -RelativePath $repositoryPath
        if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
            throw "The deployment manifest file does not exist: $repositoryPath"
        }

        if (-not $localPath.StartsWith($LocalRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "The deployment manifest file is outside the local deployment root: $repositoryPath"
        }

        $actualHash = Get-FileSha256 -Path $localPath
        if ($actualHash -ne $expectedHash) {
            throw "The deployment manifest hash does not match '$repositoryPath'. Expected: $expectedHash. Actual: $actualHash."
        }

        $deploymentRelativePath = $localPath.Substring($LocalRootPrefix.Length)
        $actualRemotePath = $RemoteRoot.TrimEnd('/') + '/' + (ConvertTo-SftpPath -Path $deploymentRelativePath)
        $declaredRemotePath = $RemoteRoot.TrimEnd('/') + '/' + (ConvertTo-SftpPath -Path $stagingPath.TrimStart('\', '/'))
        if ($actualRemotePath -ne $declaredRemotePath) {
            throw "The deployment manifest staging path does not match '$repositoryPath'. Expected: $actualRemotePath. Declared: $declaredRemotePath."
        }

        $script:ManifestHashes[$normalizedRepositoryPath] = $expectedHash
        $files += $repositoryPath
    }

    return $files
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is required to determine the files to deploy.'
}

$repositoryRoot = (& git -C $RepositoryRoot rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to locate the Git repository root.'
}
$repositoryRoot = [System.IO.Path]::GetFullPath($repositoryRoot)

$settingsScript = Join-Path $PSScriptRoot 'StagingDeploymentSettings.ps1'
if (-not (Test-Path -LiteralPath $settingsScript -PathType Leaf)) {
    throw "The staging deployment settings helper was not found: $settingsScript"
}

. $settingsScript

if ([System.IO.Path]::IsPathRooted($LocalRoot)) {
    throw 'LocalRoot must be a repository-relative path.'
}

$localRootPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $LocalRoot))
$repositoryPrefix = $repositoryRoot.TrimEnd('\') + '\'
if (-not $localRootPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "LocalRoot must be inside the repository: $LocalRoot"
}

if (-not (Test-Path -LiteralPath $localRootPath -PathType Container)) {
    throw "The local deployment root does not exist: $localRootPath"
}

$localRootPrefix = $localRootPath.TrimEnd('\') + '\'
$remoteRootPath = Normalize-StagingRemoteRoot -RemoteRoot $RemoteRoot
$script:ManifestHashes = @{}
$script:SourceRoot = $repositoryRoot
$script:SourceMode = 'WorkingTree'
$script:ManifestVerificationAssets = @()
$selectionCommit = (& git -C $repositoryRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to determine the source commit.'
}

if ($LocalRoot.Replace('\', '/').TrimEnd('/') -ne 'Tireweb Sites/Web') {
    throw 'LocalRoot must be Tireweb Sites\Web. Other deployment roots are not supported.'
}
$LocalRoot = 'Tireweb Sites\Web'
if ($IncludePaths -and $GenerateListFromGitLogArgs) {
    throw 'IncludePaths cannot be combined with GenerateListFromGitLogArgs.'
}
if (($IncludePaths -or $GenerateListFromGitLogArgs) -and $PSBoundParameters.ContainsKey('ChangeScope')) {
    throw 'Explicit paths, Git log selection, and ChangeScope are separate selection modes.'
}
if (-not [string]::IsNullOrWhiteSpace($DeploymentManifestSha256) -and $DeploymentManifestSha256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw 'DeploymentManifestSha256 must be a 64-character SHA-256 hash.'
}

if (-not [string]::IsNullOrWhiteSpace($CreateDeploymentManifestPath)) {
    if (-not $WhatIfPreference) {
        throw 'CreateDeploymentManifestPath can only be used with -WhatIf.'
    }

    if (-not [string]::IsNullOrWhiteSpace($DeploymentManifestPath)) {
        throw 'CreateDeploymentManifestPath cannot be combined with DeploymentManifestPath.'
    }
    if (Test-Path -LiteralPath $CreateDeploymentManifestPath) {
        throw 'Refusing to overwrite an existing deployment manifest. Use a new manifest path.'
    }
}

if (-not $WhatIfPreference -and [string]::IsNullOrWhiteSpace($DeploymentManifestPath)) {
    throw 'Uploads require DeploymentManifestPath. Run a -WhatIf preview with CreateDeploymentManifestPath, then upload using that manifest.'
}
if (-not $WhatIfPreference -and [string]::IsNullOrWhiteSpace($DeploymentManifestSha256)) {
    throw 'Uploads require the Manifest SHA256 emitted by the approved preview.'
}

if (-not [string]::IsNullOrWhiteSpace($DeploymentManifestPath)) {
    if ($IncludePaths -or $GenerateListFromGitLogArgs -or $PSBoundParameters.ContainsKey('ChangeScope') -or $PSBoundParameters.ContainsKey('BaseRef') -or $MSBuildPath) {
        throw 'DeploymentManifestPath cannot be combined with selection or build options.'
    }

    $changedFiles = Get-ManifestFiles -ManifestPath $DeploymentManifestPath -RepositoryRoot $repositoryRoot -LocalRootPrefix $localRootPrefix -RemoteRoot $remoteRootPath
}
elseif ($IncludePaths) {
    $changedFiles = @(Resolve-IncludePaths -Paths $IncludePaths -Root $repositoryRoot -WebRoot $localRootPath)
}
elseif ($GenerateListFromGitLogArgs) {
    if ($GenerateListFromGitLogArgs -contains '--' -or @($GenerateListFromGitLogArgs | Where-Object { $_ -match '^--(output|format|pretty|name|raw|stat|numstat|patch|diff-filter|no-diff|no-name|quiet|exit-code)|^-[pz]$' }).Count -gt 0) {
        throw 'Git log arguments may select revisions, dates, and merge traversal, but cannot override the file-list output format.'
    }
    $changedFiles = @(Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments (@('log') + $GenerateListFromGitLogArgs + @('--name-only', '--pretty=format:', '--no-renames', '-z')))
    $changedFiles = @($changedFiles | ForEach-Object { $_.TrimStart("`r", "`n") } | Where-Object { $_ })
    $script:SourceMode = 'Committed'
}
elseif ($ChangeScope -in @('Branch', 'All')) {
    if ([string]::IsNullOrWhiteSpace($BaseRef)) {
        throw 'BaseRef is required when ChangeScope is Branch.'
    }

    $baseCommit = @(& git -C $repositoryRoot rev-parse --verify --quiet ($BaseRef + '^{commit}'))
    if ($LASTEXITCODE -ne 0 -or $baseCommit.Count -eq 0) {
        throw "The base ref '$BaseRef' does not resolve to a commit."
    }

    $changedFiles = @(
        Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments @(
            'diff',
            '--name-only',
            '-z',
            '--diff-filter=ACMR',
            '--no-renames',
            ($BaseRef + '...HEAD')
        )
    )
    $removedFiles = @(Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments @('diff', '--name-only', '-z', '--no-renames', '--diff-filter=D', ($BaseRef + '...HEAD')))
    $changedFiles += $removedFiles
    if ($ChangeScope -eq 'Branch') {
        $script:SourceMode = 'Committed'
    }
    else {
        $changedFiles += @(Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments @('diff', '--name-only', '-z', '--no-renames', '--diff-filter=ACMRD', '--cached'))
        $changedFiles += @(Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments @('diff', '--name-only', '-z', '--no-renames', '--diff-filter=ACMRD'))
        $changedFiles += @(Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments @('ls-files', '--others', '--exclude-standard', '-z'))
    }
}
else {
    $changedFiles = @(
        Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments @('diff', '--name-only', '-z', '--no-renames', '--diff-filter=ACMRD', '--cached')
        Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments @('diff', '--name-only', '-z', '--no-renames', '--diff-filter=ACMRD')
        Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments @('ls-files', '--others', '--exclude-standard', '-z')
    )
}

if ($script:SourceMode -eq 'Committed' -and [string]::IsNullOrWhiteSpace($DeploymentManifestPath)) {
    if ([string]::IsNullOrWhiteSpace($CreateDeploymentManifestPath)) {
        throw 'Committed previews require CreateDeploymentManifestPath to retain the committed snapshot.'
    }
    $manifestFullPath = [System.IO.Path]::GetFullPath($CreateDeploymentManifestPath)
    if ($manifestFullPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Committed snapshots and manifests must be outside the repository.'
    }
    $script:SourceRoot = $manifestFullPath + '.source'
    $archivePath = $manifestFullPath + '.zip'
    if ((Test-Path -LiteralPath $script:SourceRoot) -or (Test-Path -LiteralPath $archivePath)) {
        throw 'Refusing to overwrite an existing committed snapshot or archive.'
    }
    $committedEntries = @(Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments @('ls-tree', '-r', '-z', $selectionCommit))
    foreach ($entry in $committedEntries) {
        if ($entry -match '^120000 blob [a-f0-9]+\t(.+)$' -and $changedFiles -contains $Matches[1]) {
            throw "Refusing to export a selected symbolic link: $($Matches[1])"
        }
    }
    New-Item -ItemType Directory -Path (Split-Path -Path $manifestFullPath -Parent) -Force -WhatIf:$false | Out-Null
    & git -C $repositoryRoot archive --format=zip "--output=$archivePath" $selectionCommit
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to export the committed source snapshot.'
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $script:SourceRoot)
    }
    finally {
        Remove-Item -LiteralPath $archivePath -Force -WhatIf:$false
    }
    foreach ($entry in $committedEntries) {
        if ($entry -match '^\d+ blob [a-f0-9]+\t(.+)$' -and $changedFiles -contains $Matches[1] -and
            -not (Test-Path -LiteralPath (Get-LocalFilePath -RepositoryRoot $script:SourceRoot -RelativePath $Matches[1]) -PathType Leaf)) {
            throw "The committed snapshot omitted a selected file (check export-ignore attributes): $($Matches[1])"
        }
    }
}

$localRootPrefix = (Join-Path $script:SourceRoot $LocalRoot).TrimEnd('\') + '\'
if ([string]::IsNullOrWhiteSpace($DeploymentManifestPath)) {
    $changedFiles = @($changedFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    foreach ($path in $changedFiles) {
        $null = Get-LocalFilePath -RepositoryRoot $script:SourceRoot -RelativePath $path
        Assert-NotSensitivePath -RelativePath $path
    }
    if ($changedFiles.Count -gt 0) {
        $preparedDlls = @(& (Join-Path $PSScriptRoot 'Build-StagingProjects.ps1') -RepositoryRoot $script:SourceRoot -ChangedPaths $changedFiles -MSBuildPath $MSBuildPath)
        $changedFiles += @($preparedDlls | ForEach-Object { $_.WebRelativePath })
    }
}

$filesToUpload = @()
foreach ($relativePath in ($changedFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
    $localPath = Get-LocalFilePath -RepositoryRoot $script:SourceRoot -RelativePath $relativePath
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        if ($IncludePaths -or $DeploymentManifestPath) {
            throw "The selected file does not exist: $relativePath"
        }
        Write-Warning "Excluded deleted or missing file; remote deletion is not performed: $relativePath"
        continue
    }

    if (-not $localPath.StartsWith($localRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Warning "Source path is not uploaded directly (supported projects produce DLLs): $relativePath"
        continue
    }

    $deploymentRelativePath = $localPath.Substring($localRootPrefix.Length)
    $remotePath = $remoteRootPath + '/' + (ConvertTo-SftpPath -Path $deploymentRelativePath)
    $normalizedRelativePath = $relativePath.Replace('\', '/')
    $actualHash = Get-FileSha256 -Path $localPath
    $expectedHash = $actualHash
    if ($script:ManifestHashes.ContainsKey($normalizedRelativePath)) {
        $expectedHash = $script:ManifestHashes[$normalizedRelativePath]
        if ($actualHash -ne $expectedHash) {
            throw "The deployment manifest hash does not match '$relativePath'. Expected: $expectedHash. Actual: $actualHash."
        }
    }

    if ($WhatIfPreference) {
        $null = $PSCmdlet.ShouldProcess($remotePath, "Upload $relativePath")
        $filesToUpload += [PSCustomObject]@{
            RelativePath = $relativePath
            LocalPath = $localPath
            RemotePath = $remotePath
            DeploymentRelativePath = ConvertTo-SftpPath -Path $deploymentRelativePath
            Sha256 = $expectedHash
        }
    }
    elseif ($PSCmdlet.ShouldProcess($remotePath, "Upload $relativePath")) {
        $filesToUpload += [PSCustomObject]@{
            RelativePath = $relativePath
            LocalPath = $localPath
            RemotePath = $remotePath
            DeploymentRelativePath = ConvertTo-SftpPath -Path $deploymentRelativePath
            Sha256 = $expectedHash
        }
    }
}

$currentCommit = (& git -C $repositoryRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $currentCommit -ne $selectionCommit) {
    throw 'The source checkout HEAD changed during preparation. Create a new preview.'
}
if ($DeploymentManifestPath) {
    $VerificationAssets = $script:ManifestVerificationAssets
}
$verificationPaths = @($filesToUpload | ForEach-Object { $_.RelativePath.Replace('\', '/') })
foreach ($asset in @($VerificationAssets | Where-Object { $_ })) {
    $parts = $asset -split '\|', 2
    $uri = $null
    if ($parts.Count -ne 2 -or
        $verificationPaths -notcontains $parts[0].Trim().Replace('\', '/') -or
        -not [System.Uri]::TryCreate($parts[1].Trim(), [System.UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http', 'https')) {
        throw "VerificationAssets must map a selected repository path to an absolute HTTP(S) URL: $asset"
    }
}

if ($filesToUpload.Count -eq 0) {
    if ($WhatIfPreference) {
        Write-Host ("Remote root: {0}" -f $remoteRootPath)
        Write-Host 'Upload queue: empty. No files were uploaded.'
        exit 0
    }

    Write-Host 'No added or modified files need to be uploaded.'
    exit 0
}

if ($WhatIfPreference) {
    Write-Host ("Source checkout: {0}" -f $repositoryRoot)
    Write-Host ("Source commit: {0}; content mode: {1}; content root: {2}" -f $selectionCommit, $script:SourceMode, $script:SourceRoot)
    Write-Host ("Remote root: {0}" -f $remoteRootPath)
    Write-Host 'Upload queue:'
    $queueIndex = 0
    foreach ($file in ($filesToUpload | Sort-Object RelativePath)) {
        $queueIndex++
        Write-Host ('{0}. `{1}` -> {2}' -f $queueIndex, $file.RelativePath.Replace('\', '/'), $file.RemotePath)
    }
    if (-not [string]::IsNullOrWhiteSpace($CreateDeploymentManifestPath)) {
        Write-DeploymentManifest -ManifestPath $CreateDeploymentManifestPath -RepositoryRoot $repositoryRoot -Files $filesToUpload
    }
    elseif ($DeploymentManifestPath) {
        Write-Host ("Manifest SHA256: {0}" -f $script:ManifestDocumentHash)
    }
    exit 0
}

$credentialScript = Join-Path $PSScriptRoot 'StagingCredential.ps1'
if (-not (Test-Path -LiteralPath $credentialScript -PathType Leaf)) {
    throw "The staging credential helper was not found: $credentialScript"
}

. $credentialScript

$winScpExecutablePath = Join-Path $WinScpDirectory 'WinSCP.exe'
if (-not (Test-Path -LiteralPath $winScpExecutablePath -PathType Leaf)) {
    throw "WinSCP executable was not found: $winScpExecutablePath"
}

$winScpAssemblyPath = Get-WinScpAssemblyPath -Directory $WinScpDirectory
if ($null -eq ('WinSCP.Session' -as [type])) {
    Add-Type -Path $winScpAssemblyPath
}

$remoteDirectories = @()
foreach ($file in $filesToUpload) {
    $remoteParentPath = Get-SftpParentPath -Path $file.RemotePath
    $remoteDirectories += Get-SftpDirectoryHierarchy -Directory $remoteParentPath -RemoteRoot $remoteRootPath
}

$credential = $null
$plainPassword = $null
$sessionOptions = $null
$session = $null
$uploadedPaths = @()
try {
    $credential = Get-StagingCredential -Target $CredentialTarget
    if ($credential.UserName -ne $UserName) {
        throw "The stored credential user '$($credential.UserName)' does not match the configured SFTP user '$UserName'."
    }

    $plainPassword = $credential.GetNetworkCredential().Password
    $sessionOptions = New-Object WinSCP.SessionOptions -Property @{
        Protocol = [WinSCP.Protocol]::Sftp
        HostName = $HostName
        PortNumber = $Port
        UserName = $UserName
        Password = $plainPassword
        SshHostKeyFingerprint = $SshHostKeyFingerprint
    }

    $session = New-Object WinSCP.Session
    $session.ExecutablePath = $winScpExecutablePath
    $session.Open($sessionOptions)

    foreach ($directory in (($remoteDirectories | Sort-Object -Unique) | Sort-Object { ($_ -split '/').Count })) {
        Ensure-SftpDirectory -Session $session -Directory $directory
    }

    $transferOptions = New-Object WinSCP.TransferOptions
    $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary
    foreach ($file in $filesToUpload) {
        # Keep the approved bytes locked against writers until their transfer finishes.
        $sourceStream = [System.IO.File]::Open($file.LocalPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            $currentHash = Get-FileSha256 -Path $file.LocalPath
            if ($currentHash -ne $file.Sha256) {
                throw "Source file changed after manifest validation: '$($file.RelativePath)'. Expected: $($file.Sha256). Actual: $currentHash."
            }
            $escapedSourcePath = [WinSCP.RemotePath]::EscapeFileMask($file.LocalPath)
            $transferResult = $session.PutFiles($escapedSourcePath, $file.RemotePath, $false, $transferOptions)
            $transferResult.Check()
            $remoteFileInfo = $session.GetFileInfo($file.RemotePath)
            if ($remoteFileInfo.Length -ne $sourceStream.Length) {
                throw "Remote file size mismatch for '$($file.RemotePath)'. Local: $($sourceStream.Length) bytes. Remote: $($remoteFileInfo.Length) bytes."
            }
            $uploadedPaths += $file.RemotePath
            Write-Host ("Uploaded and size-verified: {0} -> {1}" -f $file.RelativePath, $file.RemotePath)
        }
        finally {
            $sourceStream.Dispose()
        }
    }
}
catch {
    Write-Warning ("Deployment failed; staging may be partially updated. Completed paths: {0}. The failing transfer may also have written bytes." -f ($uploadedPaths -join ', '))
    throw
}
finally {
    if ($session -ne $null) {
        $session.Dispose()
    }

    if ($sessionOptions -ne $null) {
        $sessionOptions.Password = $null
    }

    $plainPassword = $null
    $credential = $null
}

if ($VerificationAssets -and $VerificationAssets.Count -gt 0) {
    $expectedHashes = @{}
    foreach ($file in $filesToUpload) {
        $expectedHashes[$file.RelativePath.Replace('\', '/')] = $file.Sha256
    }
    Test-VerificationAssets -Assets $VerificationAssets -ExpectedHashes $expectedHashes
}

Write-Host ("Uploaded and size-verified {0} file(s) to {1}@{2}:{3}" -f $filesToUpload.Count, $UserName, $HostName, $remoteRootPath)
Write-Host 'Deployed files:'
foreach ($file in ($filesToUpload | Sort-Object RelativePath)) {
    Write-Host ("- {0} -> {1}" -f $file.RelativePath, $file.RemotePath)
}
