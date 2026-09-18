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

function ConvertTo-PowerShellLiteral {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return "'" + $Value.Replace("'", "''") + "'"
}

function Assert-BlockedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $didThrow = $false
    try {
        Assert-NotSensitivePath -RelativePath $RelativePath
    }
    catch {
        $didThrow = $true
    }

    Assert-Condition -Condition $didThrow -Message "Sensitive path was not blocked: $RelativePath"
}

function Assert-CallerSurvivesInvocation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [switch]$WhatIf
    )

    $powerShellCommand = Get-Command pwsh, powershell -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $powerShellCommand) {
        throw 'No PowerShell executable was found for invocation validation.'
    }

    $wrapperPath = Join-Path $RepositoryRoot ("invoke-{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
    $whatIfArgument = if ($WhatIf) { ' -WhatIf' } else { '' }
    $wrapper = @(
        "`$ErrorActionPreference = 'Stop'"
        "& $(ConvertTo-PowerShellLiteral -Value $ScriptPath) -RepositoryRoot $(ConvertTo-PowerShellLiteral -Value $RepositoryRoot) -RemoteRoot '/offline' -IncludePaths 'Tireweb Sites/Web/missing.js'$whatIfArgument"
        "Write-Output 'caller-survived'"
    ) -join [Environment]::NewLine

    try {
        [System.IO.File]::WriteAllText($wrapperPath, $wrapper)
        $output = @(& $powerShellCommand.Source -NoLogo -NoProfile -File $wrapperPath 2>&1)
        Assert-Condition -Condition ($LASTEXITCODE -eq 0) -Message "Invocation validation failed: $($output -join [Environment]::NewLine)"
        Assert-Condition -Condition ($output -contains 'caller-survived') -Message 'The caller did not survive the script invocation.'
    }
    finally {
        if (Test-Path -LiteralPath $wrapperPath -PathType Leaf) {
            Remove-Item -LiteralPath $wrapperPath -Force
        }
    }
}

$scriptPath = Join-Path $SkillRoot 'Deploy-StagingCustom.ps1'
$scriptText = Get-FileText -Path $scriptPath

$tokens = $null
$parseErrors = $null
$scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
)
Assert-Condition -Condition ($parseErrors.Count -eq 0) -Message 'Deploy-StagingCustom.ps1 does not parse.'

$sensitiveFunctionAsts = @(
    $scriptAst.Find(
        {
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Assert-NotSensitivePath'
        },
        $true
    )
)
Assert-Condition -Condition ($sensitiveFunctionAsts.Count -eq 1) -Message 'Assert-NotSensitivePath was not found.'
. ([scriptblock]::Create($sensitiveFunctionAsts[0].Extent.Text))

foreach ($blockedPath in @(
    'Tireweb Sites/Web/.env',
    'Tireweb Sites/Web/.env.production.local',
    'Tireweb Sites/Web/secrets.json',
    'Tireweb Sites/Web/secrets.prod.local.json',
    'Tireweb Sites/Web/appsettings.json',
    'Tireweb Sites/Web/appsettings.Production.Local.json',
    'Tireweb Sites/Web/certificate.pfx',
    'Tireweb Sites/Web/private.key',
    'Tireweb Sites/Web/certificate.pem'
)) {
    Assert-BlockedPath -RelativePath $blockedPath
}

$allowedPath = 'Tireweb Sites/Web/Scripts/site.js'
$allowedPathIsValid = $false
try {
    Assert-NotSensitivePath -RelativePath $allowedPath
    $allowedPathIsValid = $true
}
catch {
    $allowedPathIsValid = $false
}
Assert-Condition -Condition $allowedPathIsValid -Message "A normal web file was incorrectly blocked: $allowedPath"

Assert-Condition -Condition ($scriptText -notmatch '(?m)^\s*exit\b') -Message 'Deploy-StagingCustom.ps1 must not terminate its caller with exit.'
Assert-Condition -Condition ($scriptText -match "(?s)Write-Host 'Dry run complete\. No files were uploaded\.'\s+return") -Message 'The dry-run no-file path must return.'
Assert-Condition -Condition ($scriptText -match "(?s)Write-Host 'No files need to be uploaded\.'\s+return") -Message 'The normal no-file path must return.'
Assert-Condition -Condition ($scriptText -match '(?s)Write-Host \("Dry run selected .*?\r?\n\s*foreach .*?\r?\n\s*}\s*\r?\n\s*return') -Message 'The dry-run selected-file path must return.'
Assert-Condition -Condition (-not (Test-Path -LiteralPath (Join-Path $SkillRoot 'WinSCP\WinSCP.ini'))) -Message 'Generated WinSCP configuration must not be published.'

$temporaryRepository = Join-Path ([System.IO.Path]::GetTempPath()) ("validate-deploy-{0}" -f [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $temporaryRepository 'Tireweb Sites\Web') -Force | Out-Null
try {
    & git init --quiet $temporaryRepository
    Assert-Condition -Condition ($LASTEXITCODE -eq 0) -Message 'Unable to initialize the offline validation repository.'
    Assert-CallerSurvivesInvocation -ScriptPath $scriptPath -RepositoryRoot $temporaryRepository -WhatIf
    Assert-CallerSurvivesInvocation -ScriptPath $scriptPath -RepositoryRoot $temporaryRepository
}
finally {
    if (Test-Path -LiteralPath $temporaryRepository) {
        Remove-Item -LiteralPath $temporaryRepository -Recurse -Force
    }
}

Write-Host 'Deploy-files-staging parser, sensitive-path, and invocation validation passed.'
