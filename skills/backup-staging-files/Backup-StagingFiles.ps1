[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$RepositoryRoot = (Get-Location).Path,
    [string]$LocalRoot = 'Tireweb Sites\Web',
    [Parameter(Mandatory = $true)]
    [string[]]$IncludePaths,
    [string]$RemoteRoot,
    [string]$BackupRoot,
    [string]$BackupRunName,
    [string]$HostName = '52.44.202.235',
    [int]$Port = 22,
    [string]$UserName = 'aldrin.d',
    [string]$CredentialTarget = 'Ezytire.Staging.SFTP',
    [string]$DeploySkillRoot = (Join-Path $HOME '.copilot\skills\deploy-files-staging'),
    [string]$WinScpDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$backupSettingsScript = Join-Path $PSScriptRoot 'StagingBackupSettings.ps1'
if (-not (Test-Path -LiteralPath $backupSettingsScript -PathType Leaf)) {
    throw "The staging backup settings helper was not found: $backupSettingsScript"
}
. $backupSettingsScript

$deploymentSettingsScript = Join-Path $DeploySkillRoot 'StagingDeploymentSettings.ps1'
$credentialScript = Join-Path $DeploySkillRoot 'StagingCredential.ps1'
if (-not (Test-Path -LiteralPath $deploymentSettingsScript -PathType Leaf)) {
    throw "The deploy-files-staging settings helper was not found: $deploymentSettingsScript"
}
if (-not (Test-Path -LiteralPath $credentialScript -PathType Leaf)) {
    throw "The deploy-files-staging credential helper was not found: $credentialScript"
}
. $deploymentSettingsScript
. $credentialScript

if ([string]::IsNullOrWhiteSpace($WinScpDirectory)) {
    $WinScpDirectory = Join-Path $DeploySkillRoot 'WinSCP'
}

function Get-RepositoryRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedRoot = (& git -C $Path rev-parse --show-toplevel).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolvedRoot)) {
        throw 'Unable to locate the Git repository root.'
    }

    return [System.IO.Path]::GetFullPath($resolvedRoot)
}

function Get-SafeRepositoryPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|/)\.\.(/|$)') {
        throw "Refusing to back up an unsafe repository path: $RelativePath"
    }

    $localPath = [System.IO.Path]::GetFullPath((Join-Path $Root ($RelativePath -replace '/', '\')))
    $repositoryPrefix = $Root.TrimEnd('\') + '\'
    if (-not $localPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to back up a file outside the repository: $RelativePath"
    }

    return $localPath
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $normalizedPath = $Path.TrimEnd('\')
    $normalizedRoot = $Root.TrimEnd('\')
    return $normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($normalizedRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NotSensitivePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $normalizedPath = $RelativePath.Replace('\', '/').TrimStart('/')
    $fileName = [System.IO.Path]::GetFileName($normalizedPath)

    $blockedExactFileNames = @(
        'WebsiteOptions.config'
    )

    $blockedNamePatterns = @(
        '^\.env$'
        '^\.env\.\w+$'
        '^secrets\.json$'
        '^secrets\.\w+\.json$'
        '^appsettings\.json$'
        '^appsettings\.\w+\.json$'
        '^.*\.pfx$'
        '^.*\.key$'
        '^.*\.pem$'
        '^.*\.cer$'
        '^.*\.crt$'
    )

    $blockedPathPatterns = @(
        '(^|/)App_Files/WebsiteOptions\.config$'
        '(^|/)App_Files/.*\.config$'
    )

    foreach ($exactName in $blockedExactFileNames) {
        if ($fileName -eq $exactName) {
            throw "Refusing to back up sensitive file: $RelativePath"
        }
    }

    foreach ($pattern in $blockedNamePatterns) {
        if ($fileName -match $pattern) {
            throw "Refusing to back up sensitive file matching pattern '$pattern': $RelativePath"
        }
    }

    foreach ($pattern in $blockedPathPatterns) {
        if ($normalizedPath -match $pattern) {
            throw "Refusing to back up sensitive file matching path pattern '$pattern': $RelativePath"
        }
    }
}

function Get-WinScpAssemblyPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory
    )

    $netFrameworkAssembly = Join-Path $Directory 'WinSCPnet.dll'
    $netStandardAssembly = Join-Path $Directory 'netstandard2.0\WinSCPnet.dll'
    $assemblyPath = if ($PSVersionTable.PSEdition -eq 'Core') {
        $netStandardAssembly
    }
    else {
        $netFrameworkAssembly
    }

    if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
        throw "WinSCP .NET assembly was not found: $assemblyPath"
    }

    return $assemblyPath
}

function Get-BackupRunName {
    param(
        [string]$RequestedName
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedName)) {
        $trimmedName = $RequestedName.Trim()
        if ($trimmedName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
            throw "BackupRunName may contain only letters, numbers, '.', '_', and '-': $RequestedName"
        }

        return $trimmedName
    }

    return 'staging-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')
}

function Get-AvailableRunDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RunName
    )

    $candidate = Join-Path $Root $RunName
    $suffix = 1
    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $Root ("{0}-{1}" -f $RunName, $suffix)
        $suffix++
    }

    return $candidate
}

function Write-BackupManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Manifest
    )

    $manifestJson = $Manifest | ConvertTo-Json -Depth 10
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $manifestJson, $utf8WithoutBom)
}

$repositoryRoot = Get-RepositoryRoot -Path $RepositoryRoot
$localRootPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $LocalRoot))
$repositoryPrefix = $repositoryRoot.TrimEnd('\') + '\'
if (-not $localRootPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "LocalRoot must be inside the repository: $LocalRoot"
}
if (-not (Test-Path -LiteralPath $localRootPath -PathType Container)) {
    throw "The local deployment root does not exist: $localRootPath"
}

$backupRootPath = if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    Get-StagingBackupRoot
}
else {
    Normalize-StagingBackupRoot -BackupRoot $BackupRoot
}
if ([string]::IsNullOrWhiteSpace($backupRootPath)) {
    throw 'No local staging backup directory is configured. Run Set-StagingBackupRoot.ps1 first.'
}
if (Test-PathWithinRoot -Path $backupRootPath -Root $repositoryRoot) {
    throw "The staging backup directory must be outside the repository: $backupRootPath"
}
if (-not (Test-Path -LiteralPath $backupRootPath -PathType Container)) {
    throw "The configured staging backup directory does not exist: $backupRootPath"
}

if ([string]::IsNullOrWhiteSpace($RemoteRoot)) {
    $RemoteRoot = Get-StagingDeploymentRemoteRoot
}
if ([string]::IsNullOrWhiteSpace($RemoteRoot)) {
    throw 'No staging remote directory is configured. Run deploy-files-staging setup first.'
}
$remoteRootPath = Normalize-StagingRemoteRoot -RemoteRoot $RemoteRoot

$localRootPrefix = $localRootPath.TrimEnd('\') + '\'
$filesToBackup = @()
foreach ($includePath in ($IncludePaths | Sort-Object -Unique)) {
    if ([string]::IsNullOrWhiteSpace($includePath)) {
        continue
    }

    $normalizedIncludePath = $includePath.Trim().Replace('\', '/')
    Assert-NotSensitivePath -RelativePath $normalizedIncludePath

    $localPath = Get-SafeRepositoryPath -Root $repositoryRoot -RelativePath $normalizedIncludePath
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        throw "Cannot back up a missing local deployment file: $normalizedIncludePath"
    }
    if (-not $localPath.StartsWith($localRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Backup paths must be under '$LocalRoot': $normalizedIncludePath"
    }

    $deploymentRelativePath = $localPath.Substring($localRootPrefix.Length).Replace('\', '/')
    $remotePath = $remoteRootPath.TrimEnd('/') + '/' + $deploymentRelativePath
    $filesToBackup += [PSCustomObject]@{
        RelativePath = $normalizedIncludePath
        DeploymentRelativePath = $deploymentRelativePath
        LocalPath = $localPath
        RemotePath = $remotePath
    }
}

if ($filesToBackup.Count -eq 0) {
    throw 'No valid files were provided for backup.'
}

$runName = Get-BackupRunName -RequestedName $BackupRunName

$winScpExecutablePath = Join-Path $WinScpDirectory 'WinSCP.exe'
if (-not (Test-Path -LiteralPath $winScpExecutablePath -PathType Leaf)) {
    throw "WinSCP executable was not found: $winScpExecutablePath"
}

$winScpAssemblyPath = Get-WinScpAssemblyPath -Directory $WinScpDirectory
if ($null -eq ('WinSCP.Session' -as [type])) {
    Add-Type -Path $winScpAssemblyPath
}

$credential = $null
$plainPassword = $null
$sessionOptions = $null
$session = $null
$runDirectory = $null
$manifest = $null
$manifestPath = $null
$manifestFiles = @()

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
        SshHostKeyFingerprint = 'ssh-rsa 1024 Yxo6FcvF30RCXrUQYJep89aRHkX8a6MAMY2XwFXPV6w'
    }

    $session = New-Object WinSCP.Session
    $session.ExecutablePath = $winScpExecutablePath
    $session.Open($sessionOptions)

    $remoteFileInfos = @{}
    foreach ($file in $filesToBackup) {
        try {
            $remoteFileInfo = $session.GetFileInfo($file.RemotePath)
        }
        catch {
            throw "Remote file preflight failed for '$($file.RemotePath)': $($_.Exception.Message)"
        }

        if ($null -eq $remoteFileInfo -or $remoteFileInfo.IsDirectory) {
            throw "The remote backup path is not a regular file: $($file.RemotePath)"
        }

        $remoteFileInfos[$file.RemotePath] = $remoteFileInfo
    }

    $availableRunDirectory = Get-AvailableRunDirectory -Root $backupRootPath -RunName $runName
    if ($WhatIfPreference) {
        Write-Host ("Dry run SFTP preflight succeeded for {0} remote file(s) from {1}:" -f $filesToBackup.Count, $remoteRootPath)
        foreach ($file in $filesToBackup) {
            $previewBackupPath = Join-Path $availableRunDirectory ($file.DeploymentRelativePath -replace '/', '\')
            $remoteFileInfo = $remoteFileInfos[$file.RemotePath]
            Write-Host ("- {0} ({1} bytes) -> {2}" -f $file.RemotePath, $remoteFileInfo.Length, $previewBackupPath)
        }
        Write-Host ("Proposed backup directory (not reserved; execution may use a higher collision suffix): {0}" -f $availableRunDirectory)
        return
    }

    $runDirectory = $null
    $candidateRunDirectory = $availableRunDirectory
    while ($null -eq $runDirectory) {
        try {
            New-Item -ItemType Directory -Path $candidateRunDirectory -ErrorAction Stop | Out-Null
            $runDirectory = $candidateRunDirectory
        }
        catch {
            if (-not (Test-Path -LiteralPath $candidateRunDirectory)) {
                throw
            }

            $candidateRunDirectory = Get-AvailableRunDirectory -Root $backupRootPath -RunName $runName
        }
    }

    $manifestPath = Join-Path $runDirectory 'manifest.json'
    $manifest = [ordered]@{
        SchemaVersion = 1
        Status = 'in_progress'
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        CompletedUtc = $null
        RepositoryRoot = $repositoryRoot
        RemoteRoot = $remoteRootPath
        HostName = $HostName
        UserName = $UserName
        BackupDirectory = $runDirectory
        Files = @()
    }
    Write-BackupManifest -Path $manifestPath -Manifest $manifest

    $transferOptions = New-Object WinSCP.TransferOptions
    $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary

    foreach ($file in $filesToBackup) {
        $localBackupPath = Join-Path $runDirectory ($file.DeploymentRelativePath -replace '/', '\')
        $localBackupDirectory = Split-Path -Path $localBackupPath -Parent
        if (-not (Test-Path -LiteralPath $localBackupDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $localBackupDirectory -Force | Out-Null
        }
        if (Test-Path -LiteralPath $localBackupPath) {
            throw "The backup destination already exists: $localBackupPath"
        }

        if (-not $PSCmdlet.ShouldProcess($file.RemotePath, "Download to $localBackupPath")) {
            continue
        }

        $transferResult = $session.GetFiles($file.RemotePath, $localBackupPath, $false, $transferOptions)
        $transferResult.Check()

        $localFileLength = [Int64](Get-Item -LiteralPath $localBackupPath -ErrorAction Stop).Length
        $remoteFileInfoAfter = $session.GetFileInfo($file.RemotePath)
        if ($remoteFileInfoAfter.Length -ne $localFileLength) {
            throw "Backup size mismatch for '$($file.RemotePath)'. Local: $localFileLength bytes. Remote: $($remoteFileInfoAfter.Length) bytes."
        }

        $manifestFiles += [PSCustomObject][ordered]@{
            RelativePath = $file.RelativePath
            RemotePath = $file.RemotePath
            BackupPath = $localBackupPath
            RemoteSize = [Int64]$remoteFileInfoAfter.Length
            LocalSize = $localFileLength
            Status = 'completed'
        }
        $manifest.Files = $manifestFiles
        Write-BackupManifest -Path $manifestPath -Manifest $manifest
    }

    if ($manifestFiles.Count -ne $filesToBackup.Count) {
        throw 'The backup was not completed because one or more files were skipped.'
    }

    $manifest.Status = 'completed'
    $manifest.CompletedUtc = [DateTime]::UtcNow.ToString('o')
    $manifest.Files = $manifestFiles
    Write-BackupManifest -Path $manifestPath -Manifest $manifest
}
catch {
    if ($null -ne $manifest -and -not [string]::IsNullOrWhiteSpace($manifestPath)) {
        $manifest.Status = 'failed'
        $manifest.CompletedUtc = [DateTime]::UtcNow.ToString('o')
        $manifest.Error = $_.Exception.Message
        $manifest.Files = $manifestFiles
        Write-BackupManifest -Path $manifestPath -Manifest $manifest
    }

    throw
}
finally {
    if ($null -ne $session) {
        $session.Dispose()
    }

    if ($null -ne $sessionOptions) {
        $sessionOptions.Password = $null
    }

    $plainPassword = $null
    $credential = $null
}

Write-Host ("Backed up and size-verified {0} file(s) from {1} to {2}" -f $filesToBackup.Count, $remoteRootPath, $runDirectory)
Write-Host ("Manifest: {0}" -f $manifestPath)
Write-Host 'Backed up files:'
foreach ($file in $manifestFiles) {
    Write-Host ("- {0} -> {1} ({2} bytes)" -f $file.RemotePath, $file.BackupPath, $file.LocalSize)
}
