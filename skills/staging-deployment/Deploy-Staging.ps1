[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$RepositoryRoot = (Get-Location).Path,
    [string]$LocalRoot = 'Tireweb Sites\Web',
    [string[]]$IncludePaths,
    [string]$DeploymentManifestPath,
    [string]$CreateDeploymentManifestPath,
    [string[]]$VerificationAssets,
    [ValidateSet('Uncommitted', 'Branch')]
    [string]$ChangeScope = 'Uncommitted',
    [string]$BaseRef = 'development',
    [string]$HostName = '52.44.202.235',
    [int]$Port = 22,
    [Parameter(Mandatory = $true)]
    [string]$UserName,
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
The script discovers added and modified files inside the local web root using
NUL-delimited Git output, preserving paths with spaces and other special
characters. A preview can write an immutable deployment manifest containing the
selected paths and SHA-256 hashes. Uploads require that manifest and revalidate
each source file before transfer. Removed files are intentionally not deleted
from staging. The SFTP password is read from the current user's Windows
Credential Manager entry at runtime. Each uploaded file is checked against its
remote byte length. VerificationAssets can additionally hash browser-served
assets from staging after upload.

.EXAMPLE
$manifestPath = Join-Path $env:TEMP 'ezytire-staging-release.json'
& "$HOME\.copilot\skills\staging-deployment\Deploy-Staging.ps1" -RepositoryRoot (Get-Location).Path -RemoteRoot '/EOSB-757' -CreateDeploymentManifestPath $manifestPath -WhatIf
& "$HOME\.copilot\skills\staging-deployment\Deploy-Staging.ps1" -RepositoryRoot (Get-Location).Path -RemoteRoot '/EOSB-757' -DeploymentManifestPath $manifestPath

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

function Get-LocalFilePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|/)\.\.(/|$)') {
        throw "Refusing to deploy an unsafe repository path: $RelativePath"
    }

    $localPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($RelativePath -replace '/', '\')))
    $repositoryPrefix = $RepositoryRoot.TrimEnd('\') + '\'
    if (-not $localPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to deploy a file outside the repository: $RelativePath"
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
        New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
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
        schema_version = '1.0'
        release_commit = $releaseCommit
        assets = $assets
    }
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($manifestFullPath, ($manifest | ConvertTo-Json -Depth 4), $utf8WithoutBom)
    Write-Host "Wrote deployment manifest: $manifestFullPath"
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

    try {
        $manifest = Get-Content -LiteralPath $manifestFullPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "The deployment manifest is not valid JSON: $manifestFullPath"
    }

    if ($manifest.schema_version -ne '1.0') {
        throw 'The deployment manifest must declare schema_version 1.0.'
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

        $localPath = Get-LocalFilePath -RepositoryRoot $RepositoryRoot -RelativePath $repositoryPath
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

if (-not [string]::IsNullOrWhiteSpace($CreateDeploymentManifestPath)) {
    if (-not $WhatIfPreference) {
        throw 'CreateDeploymentManifestPath can only be used with -WhatIf.'
    }

    if (-not [string]::IsNullOrWhiteSpace($DeploymentManifestPath)) {
        throw 'CreateDeploymentManifestPath cannot be combined with DeploymentManifestPath.'
    }
}

if (-not $WhatIfPreference -and [string]::IsNullOrWhiteSpace($DeploymentManifestPath)) {
    throw 'Uploads require DeploymentManifestPath. Run a -WhatIf preview with CreateDeploymentManifestPath, then upload using that manifest.'
}

if (-not [string]::IsNullOrWhiteSpace($DeploymentManifestPath)) {
    if ($IncludePaths -and $IncludePaths.Count -gt 0) {
        throw 'IncludePaths cannot be combined with DeploymentManifestPath.'
    }

    $changedFiles = Get-ManifestFiles -ManifestPath $DeploymentManifestPath -RepositoryRoot $repositoryRoot -LocalRootPrefix $localRootPrefix -RemoteRoot $remoteRootPath
    $manifest = Get-Content -LiteralPath $DeploymentManifestPath -Raw | ConvertFrom-Json
    foreach ($asset in @($manifest.assets)) {
        $script:ManifestHashes[$asset.repository_source_path.Replace('\', '/')] = $asset.sha256
    }
}
elseif ($ChangeScope -eq 'Branch') {
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
            ($BaseRef + '...HEAD')
        )
    )
}
else {
    $changedFiles = @(
        Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments @('diff', '--name-only', '-z', '--diff-filter=ACMR', '--cached')
        Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments @('diff', '--name-only', '-z', '--diff-filter=ACMR')
        Get-GitFiles -RepositoryRoot $repositoryRoot -Arguments @('ls-files', '--others', '--exclude-standard', '-z')
    )
}

if ($IncludePaths -and $IncludePaths.Count -gt 0) {
    $normalizedIncludePaths = @()
    foreach ($includePath in $IncludePaths) {
        if ([string]::IsNullOrWhiteSpace($includePath)) {
            throw 'IncludePaths cannot contain an empty path.'
        }

        $normalizedIncludePath = $includePath.Trim().Replace('\', '/')
        if ([System.IO.Path]::IsPathRooted($normalizedIncludePath) -or $normalizedIncludePath -match '(^|/)\.\.(/|$)') {
            throw "Refusing to deploy an unsafe included path: $includePath"
        }

        $normalizedIncludePaths += $normalizedIncludePath
    }

    $normalizedChangedFiles = @(
        $changedFiles |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Replace('\', '/') }
    )
    $missingIncludePaths = @(
        $normalizedIncludePaths |
            Where-Object { $normalizedChangedFiles -notcontains $_ } |
            Sort-Object -Unique
    )
    if ($missingIncludePaths.Count -gt 0) {
        throw "The requested file(s) are not added or modified uncommitted files: $($missingIncludePaths -join ', ')"
    }

    $changedFiles = @(
        $changedFiles |
            Where-Object { $normalizedIncludePaths -contains $_.Replace('\', '/') }
    )
}

$filesToUpload = @()
foreach ($relativePath in ($changedFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
    $localPath = Get-LocalFilePath -RepositoryRoot $repositoryRoot -RelativePath $relativePath
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        continue
    }

    if (-not $localPath.StartsWith($localRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
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

if ($filesToUpload.Count -eq 0) {
    if ($WhatIfPreference) {
        Write-Host 'Dry run complete. No files were uploaded.'
        exit 0
    }

    Write-Host 'No added or modified files need to be uploaded.'
    exit 0
}

if ($WhatIfPreference) {
    Write-Host ("Dry run selected {0} file(s) for upload to {1}:" -f $filesToUpload.Count, $remoteRootPath)
    foreach ($file in ($filesToUpload | Sort-Object RelativePath)) {
        Write-Host ("- {0} -> {1}" -f $file.RelativePath, $file.RemotePath)
    }
    if (-not [string]::IsNullOrWhiteSpace($CreateDeploymentManifestPath)) {
        Write-DeploymentManifest -ManifestPath $CreateDeploymentManifestPath -RepositoryRoot $repositoryRoot -Files $filesToUpload
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
        $currentHash = Get-FileSha256 -Path $file.LocalPath
        if ($currentHash -ne $file.Sha256) {
            throw "Source file changed after manifest validation: '$($file.RelativePath)'. Expected: $($file.Sha256). Actual: $currentHash."
        }

        $transferResult = $session.PutFiles($file.LocalPath, $file.RemotePath, $false, $transferOptions)
        $transferResult.Check()

        $localFileLength = [Int64](Get-Item -LiteralPath $file.LocalPath -ErrorAction Stop).Length
        $remoteFileInfo = $session.GetFileInfo($file.RemotePath)
        if ($remoteFileInfo.Length -ne $localFileLength) {
            throw "Remote file size mismatch for '$($file.RemotePath)'. Local: $localFileLength bytes. Remote: $($remoteFileInfo.Length) bytes."
        }
    }
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
