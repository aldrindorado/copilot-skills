Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-StagingBackupSettingsPath {
    $settingsDirectory = Join-Path $env:LOCALAPPDATA 'GitHub Copilot\backup-staging-files'
    return Join-Path $settingsDirectory 'settings.json'
}

function Normalize-StagingBackupRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupRoot
    )

    if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
        throw 'A local staging backup directory is required.'
    }

    $trimmedRoot = $BackupRoot.Trim()
    if ($trimmedRoot.IndexOf('"') -ge 0 -or
        $trimmedRoot.IndexOf("`n") -ge 0 -or
        $trimmedRoot.IndexOf("`r") -ge 0) {
        throw "The local staging backup directory contains unsupported characters: $BackupRoot"
    }

    if (-not [System.IO.Path]::IsPathRooted($trimmedRoot)) {
        throw "The local staging backup directory must be an absolute path: $BackupRoot"
    }

    return (New-Object System.IO.DirectoryInfo([System.IO.Path]::GetFullPath($trimmedRoot))).FullName
}

function Get-StagingBackupRoot {
    [CmdletBinding()]
    param(
        [string]$SettingsPath = (Get-StagingBackupSettingsPath)
    )

    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
        return $null
    }

    $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    if ($null -eq $settings -or [string]::IsNullOrWhiteSpace($settings.BackupRoot)) {
        throw "The staging backup settings file does not contain a backup directory: $SettingsPath"
    }

    return Normalize-StagingBackupRoot -BackupRoot $settings.BackupRoot
}

function Set-StagingBackupRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupRoot,

        [string]$SettingsPath = (Get-StagingBackupSettingsPath)
    )

    $normalizedBackupRoot = Normalize-StagingBackupRoot -BackupRoot $BackupRoot
    if (Test-Path -LiteralPath $normalizedBackupRoot -PathType Leaf) {
        throw "The staging backup path is an existing file, not a directory: $normalizedBackupRoot"
    }

    if (-not (Test-Path -LiteralPath $normalizedBackupRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $normalizedBackupRoot -Force | Out-Null
    }

    $settingsDirectory = Split-Path -Path $SettingsPath -Parent
    if (-not (Test-Path -LiteralPath $settingsDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
    }

    $settings = [PSCustomObject]@{
        BackupRoot = $normalizedBackupRoot
    }
    $settingsJson = $settings | ConvertTo-Json
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($SettingsPath, $settingsJson, $utf8WithoutBom)

    return $normalizedBackupRoot
}

function Remove-StagingBackupRoot {
    [CmdletBinding()]
    param(
        [string]$SettingsPath = (Get-StagingBackupSettingsPath)
    )

    if (Test-Path -LiteralPath $SettingsPath -PathType Leaf) {
        Remove-Item -LiteralPath $SettingsPath -Force
    }
}
