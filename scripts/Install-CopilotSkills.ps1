[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$DestinationRoot = (Join-Path $HOME '.copilot\skills'),

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$sourceRoot = Join-Path $repositoryRoot 'skills'
$markerFileName = '.copilot-skills-repository.json'

if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "The skills directory was not found: $sourceRoot"
}

$skillDirectories = @(
    Get-ChildItem -LiteralPath $sourceRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
        Sort-Object Name
)

if ($skillDirectories.Count -eq 0) {
    Write-Warning "No skills were found under $sourceRoot."
    return
}

if (-not (Test-Path -LiteralPath $DestinationRoot -PathType Container)) {
    if ($PSCmdlet.ShouldProcess($DestinationRoot, 'Create Copilot skills directory')) {
        New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    }
}

foreach ($skillDirectory in $skillDirectories) {
    $destinationPath = Join-Path $DestinationRoot $skillDirectory.Name
    $markerPath = Join-Path $destinationPath $markerFileName

    if (Test-Path -LiteralPath $destinationPath) {
        if (-not $Force) {
            throw "The destination skill already exists: $destinationPath. Use -Force only to replace a skill previously installed by this repository."
        }

        if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
            throw "Refusing to replace a skill that is not managed by this repository: $destinationPath"
        }

        $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        if ($marker.repository -ne 'copilot-skills' -or $marker.skill -ne $skillDirectory.Name) {
            throw "Refusing to replace a skill with an invalid repository marker: $destinationPath"
        }

        if ($PSCmdlet.ShouldProcess($destinationPath, 'Replace installed Copilot skill')) {
            Remove-Item -LiteralPath $destinationPath -Recurse -Force
        }
    }

    if ($PSCmdlet.ShouldProcess($destinationPath, 'Install Copilot skill')) {
        Copy-Item -LiteralPath $skillDirectory.FullName -Destination $destinationPath -Recurse -Force
        $marker = [PSCustomObject]@{
            repository = 'copilot-skills'
            skill = $skillDirectory.Name
        }
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText((Join-Path $destinationPath $markerFileName), ($marker | ConvertTo-Json), $utf8WithoutBom)
        Write-Host "Installed skill: $($skillDirectory.Name)"
    }
}
