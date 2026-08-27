[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$RepositoryRoot = (Get-Location).Path,
    [string]$LocalRoot = 'Tireweb Sites\Web',
    [string[]]$IncludePaths,
    [string[]]$GenerateListFromGitLogArgs,
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
Uploads a user-supplied list of Ezytire web files to the staging server using WinSCP.

.DESCRIPTION
This script deploys an explicit list of files supplied via -IncludePaths or generated
from a git log expression via -GenerateListFromGitLog. It maps local paths under
'Tireweb Sites\Web' to the selected remote staging directory, skips files outside the
web root, verifies each uploaded file's remote size, and does not delete files from the
remote server.

The SFTP password is read from the current user's Windows Credential Manager entry at
runtime.

.EXAMPLE
& "$HOME\.copilot\skills\staging-deployment-custom\Deploy-StagingCustom.ps1" `
    -RepositoryRoot (Get-Location).Path `
    -RemoteRoot '/EOSB-757' `
    -IncludePaths 'Tireweb Sites/Web/App_Modules/248-GMapLiteStore/BrakesPlus.ascx','Tireweb Sites/Web/App_Modules/248-GMapLiteStore/Default.ascx.cs' `
    -WhatIf

.EXAMPLE
& "$HOME\.copilot\skills\staging-deployment-custom\Deploy-StagingCustom.ps1" `
    -RepositoryRoot (Get-Location).Path `
    -RemoteRoot '/EOSB-757' `
    -GenerateListFromGitLogArgs 'development','--since=2026-08-01','--until=2026-08-08' `
    -WhatIf

.EXAMPLE
& "$HOME\.copilot\skills\staging-deployment-custom\Deploy-StagingCustom.ps1" `
    -RepositoryRoot (Get-Location).Path `
    -RemoteRoot '/EOSB-757' `
    -IncludePaths 'Tireweb Sites/Web/App_Modules/248-GMapLiteStore/BrakesPlus.ascx'
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WinScpDirectory)) {
    $WinScpDirectory = Join-Path $PSScriptRoot 'WinSCP'
}

function Get-GitLogFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$LogArgs
    )

    $gitArguments = @('log', '--name-only', '--pretty=format:')
        if ($LogArgs -and $LogArgs.Count -gt 0) {
            $gitArguments += $LogArgs
        }

        $files = @(& git -C $RepositoryRoot @gitArguments)
        if ($LASTEXITCODE -ne 0) {
            throw "git log failed for arguments: $($LogArgs -join ' ')"
        }

        return $files | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
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
            throw "Refusing to deploy sensitive file: $RelativePath"
        }
    }

    foreach ($pattern in $blockedNamePatterns) {
        if ($fileName -match $pattern) {
            throw "Refusing to deploy sensitive file matching pattern '$pattern': $RelativePath"
        }
    }

    foreach ($pattern in $blockedPathPatterns) {
        if ($normalizedPath -match $pattern) {
            throw "Refusing to deploy sensitive file matching path pattern '$pattern': $RelativePath"
        }
    }
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

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is required when generating a file list from a git log expression.'
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

if ($GenerateListFromGitLogArgs -and $GenerateListFromGitLogArgs.Count -gt 0 -and $IncludePaths -and $IncludePaths.Count -gt 0) {
    throw 'GenerateListFromGitLogArgs cannot be combined with IncludePaths.'
}

$resolvedIncludePaths = @()
if ($GenerateListFromGitLogArgs -and $GenerateListFromGitLogArgs.Count -gt 0) {
    $resolvedIncludePaths = @(Get-GitLogFiles -RepositoryRoot $repositoryRoot -LogArgs $GenerateListFromGitLogArgs)
    if ($resolvedIncludePaths.Count -eq 0) {
        throw "The git log arguments '$($GenerateListFromGitLogArgs -join ' ')' did not return any files."
    }
}
elseif ($IncludePaths -and $IncludePaths.Count -gt 0) {
    $resolvedIncludePaths = $IncludePaths
}
else {
    throw 'Either IncludePaths or GenerateListFromGitLog must be provided.'
}

$normalizedIncludePaths = @()
foreach ($includePath in $resolvedIncludePaths) {
    if ([string]::IsNullOrWhiteSpace($includePath)) {
        continue
    }

    $normalizedIncludePath = $includePath.Trim().Replace('\', '/')
    if ([System.IO.Path]::IsPathRooted($normalizedIncludePath) -or $normalizedIncludePath -match '(^|/)\.\.(/|$)') {
        throw "Refusing to deploy an unsafe included path: $includePath"
    }

    $normalizedIncludePaths += $normalizedIncludePath
}

if ($normalizedIncludePaths.Count -eq 0) {
    throw 'No valid file paths were provided for deployment.'
}

$filesToUpload = @()
foreach ($relativePath in ($normalizedIncludePaths | Sort-Object -Unique)) {
    Assert-NotSensitivePath -RelativePath $relativePath

    $localPath = Get-LocalFilePath -RepositoryRoot $repositoryRoot -RelativePath $relativePath
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        Write-Warning "Skipping missing file: $relativePath"
        continue
    }

    if (-not $localPath.StartsWith($localRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Warning "Skipping file outside local deployment root: $relativePath"
        continue
    }

    $deploymentRelativePath = $localPath.Substring($localRootPrefix.Length)
    $remotePath = $remoteRootPath + '/' + (ConvertTo-SftpPath -Path $deploymentRelativePath)
    if ($WhatIfPreference) {
        $null = $PSCmdlet.ShouldProcess($remotePath, "Upload $relativePath")
        $filesToUpload += [PSCustomObject]@{
            RelativePath = $relativePath
            LocalPath = $localPath
            RemotePath = $remotePath
        }
    }
    elseif ($PSCmdlet.ShouldProcess($remotePath, "Upload $relativePath")) {
        $filesToUpload += [PSCustomObject]@{
            RelativePath = $relativePath
            LocalPath = $localPath
            RemotePath = $remotePath
        }
    }
}

if ($filesToUpload.Count -eq 0) {
    if ($WhatIfPreference) {
        Write-Host 'Dry run complete. No files were uploaded.'
        exit 0
    }

    Write-Host 'No files need to be uploaded.'
    exit 0
}

if ($WhatIfPreference) {
    Write-Host ("Dry run selected {0} file(s) for upload to {1}:" -f $filesToUpload.Count, $remoteRootPath)
    foreach ($file in ($filesToUpload | Sort-Object RelativePath)) {
        Write-Host ("- {0} -> {1}" -f $file.RelativePath, $file.RemotePath)
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

Write-Host ("Uploaded and size-verified {0} file(s) to {1}@{2}:{3}" -f $filesToUpload.Count, $UserName, $HostName, $remoteRootPath)
Write-Host 'Deployed files:'
foreach ($file in ($filesToUpload | Sort-Object RelativePath)) {
    Write-Host ("- {0} -> {1}" -f $file.RelativePath, $file.RemotePath)
}
