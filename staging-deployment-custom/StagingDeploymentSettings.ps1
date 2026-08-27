Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-StagingDeploymentCustomSettingsPath {
    $settingsDirectory = Join-Path $env:LOCALAPPDATA 'GitHub Copilot\staging-deployment-custom'
    return Join-Path $settingsDirectory 'settings.json'
}

function Normalize-StagingRemoteRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteRoot
    )

    if ([string]::IsNullOrWhiteSpace($RemoteRoot)) {
        throw 'A remote staging directory is required.'
    }

    $normalizedRemoteRoot = $RemoteRoot.Trim().Replace('\', '/')
    if ($normalizedRemoteRoot.IndexOf('"') -ge 0 -or
        $normalizedRemoteRoot.IndexOf("`n") -ge 0 -or
        $normalizedRemoteRoot.IndexOf("`r") -ge 0) {
        throw "The remote staging directory contains unsupported characters: $RemoteRoot"
    }

    if (-not $normalizedRemoteRoot.StartsWith('/')) {
        $normalizedRemoteRoot = '/' + $normalizedRemoteRoot
    }

    $pathSegments = @(
        $normalizedRemoteRoot -split '/' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($pathSegments.Count -eq 0) {
        throw 'The remote staging directory cannot be the SFTP root directory.'
    }

    foreach ($pathSegment in $pathSegments) {
        if ($pathSegment -eq '.' -or $pathSegment -eq '..') {
            throw "The remote staging directory cannot contain '.' or '..': $RemoteRoot"
        }
    }

    return '/' + ($pathSegments -join '/')
}

function Get-StagingDeploymentRemoteRoot {
    [CmdletBinding()]
    param(
        [string]$SettingsPath = (Get-StagingDeploymentCustomSettingsPath)
    )

    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
        return $null
    }

    $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    if ($null -eq $settings -or [string]::IsNullOrWhiteSpace($settings.RemoteRoot)) {
        throw "The staging deployment settings file does not contain a remote directory: $SettingsPath"
    }

    return Normalize-StagingRemoteRoot -RemoteRoot $settings.RemoteRoot
}

function Set-StagingDeploymentRemoteRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteRoot,

        [string]$SettingsPath = (Get-StagingDeploymentCustomSettingsPath)
    )

    $normalizedRemoteRoot = Normalize-StagingRemoteRoot -RemoteRoot $RemoteRoot
    $settingsDirectory = Split-Path -Path $SettingsPath -Parent
    if (-not (Test-Path -LiteralPath $settingsDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
    }

    $settings = [PSCustomObject]@{
        RemoteRoot = $normalizedRemoteRoot
    }
    $settingsJson = $settings | ConvertTo-Json
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($SettingsPath, $settingsJson, $utf8WithoutBom)

    return $normalizedRemoteRoot
}

function Remove-StagingDeploymentRemoteRoot {
    [CmdletBinding()]
    param(
        [string]$SettingsPath = (Get-StagingDeploymentCustomSettingsPath)
    )

    if (Test-Path -LiteralPath $SettingsPath -PathType Leaf) {
        Remove-Item -LiteralPath $SettingsPath -Force
    }
}
