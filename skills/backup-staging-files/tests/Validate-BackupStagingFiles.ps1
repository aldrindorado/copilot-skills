[CmdletBinding()]
param(
    [string]$SkillRoot = (Split-Path -Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "Validation failed: $Message"
    }
}

function Get-FileText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Validation input was not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Assert-Condition -Condition ($Text -match $Pattern) -Message $Message
}

$scriptPath = Join-Path $SkillRoot 'Backup-StagingFiles.ps1'
$skillPath = Join-Path $SkillRoot 'SKILL.md'
$scriptText = Get-FileText -Path $scriptPath
$skillText = Get-FileText -Path $skillPath

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null
Assert-Condition -Condition ($parseErrors.Count -eq 0) -Message 'Backup-StagingFiles.ps1 does not parse.'

Assert-Condition -Condition ($scriptText -notmatch '(?m)^\s*exit\s+') -Message 'The backup script must not terminate the PowerShell host with exit.'
Assert-Contains -Text $scriptText -Pattern '\$session\.Open\(\$sessionOptions\)' -Message 'The script must open SFTP before preview succeeds.'
Assert-Contains -Text $scriptText -Pattern '\$session\.GetFileInfo\(\$file\.RemotePath\)' -Message 'The script must preflight every remote file.'
Assert-Contains -Text $scriptText -Pattern '(?s)if \(\$WhatIfPreference\).*?return' -Message 'Preview must return after SFTP preflight without creating a run.'
Assert-Contains -Text $scriptText -Pattern 'Get-AvailableRunDirectory -Root \$backupRootPath -RunName \$runName' -Message 'Preview and execution must use collision-aware run allocation.'
Assert-Contains -Text $scriptText -Pattern 'New-Item -ItemType Directory -Path \$candidateRunDirectory -ErrorAction Stop' -Message 'Execution must reserve a run directory without overwriting a collision.'
Assert-Condition -Condition (
    $scriptText.IndexOf('$session.Open($sessionOptions)', [System.StringComparison]::Ordinal) -lt
    $scriptText.IndexOf('$session.GetFileInfo($file.RemotePath)', [System.StringComparison]::Ordinal) -and
    $scriptText.IndexOf('$session.GetFileInfo($file.RemotePath)', [System.StringComparison]::Ordinal) -lt
    $scriptText.IndexOf('if ($WhatIfPreference)', [System.StringComparison]::Ordinal)
) -Message 'Preview must not report success before the SFTP connection and remote preflight.'
Assert-Contains -Text $skillText -Pattern '\$backupRunName = .*DateTime\]::UtcNow' -Message 'The workflow must generate one run name.'
Assert-Contains -Text $skillText -Pattern '-BackupRunName \$backupRunName' -Message 'The workflow must reuse the run name for preview and execution.'
Assert-Contains -Text $skillText -Pattern '-Confirm:\$false' -Message 'The workflow must suppress duplicate high-impact prompts after confirmation.'

Write-Host 'Backup-staging-files parser and workflow validation passed.'
