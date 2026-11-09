[CmdletBinding()]
param(
    [string]$PowerShellExecutable = (Get-Process -Id $PID).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path $PSScriptRoot -Parent
$engine = Join-Path $skillRoot 'Deploy-Staging.ps1'
$fixtureRoot = Join-Path $env:TEMP ("staging-tests-{0}" -f [guid]::NewGuid().ToString('N'))
$repository = Join-Path $fixtureRoot 'developer checkout'
$releases = Join-Path $fixtureRoot 'releases'
$checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
    $script:checks++
}

function Write-FixtureFile {
    param([string]$RelativePath, [string]$Content)
    $path = Join-Path $repository $RelativePath
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    [System.IO.File]::WriteAllText($path, $Content)
}

function Invoke-FixtureGit {
    param([string[]]$GitArguments)
    & git -C $repository @GitArguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Fixture git failed: $($GitArguments -join ' ')"
    }
}

function Invoke-Deployment {
    param([hashtable]$Options, [string]$ExpectedError)
    $parameters = @{
        RepositoryRoot = $repository
        RemoteRoot = '/EOSB-test'
        WhatIf = $true
    }
    foreach ($key in $Options.Keys) {
        $parameters[$key] = $Options[$key]
    }
    $parameterFile = Join-Path $releases ("parameters-{0}.json" -f [guid]::NewGuid().ToString('N'))
    $parameters | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $parameterFile -Encoding UTF8
    $output = @(& $PowerShellExecutable -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-DeploymentFixture.ps1') -Engine $engine -ParameterFile $parameterFile 2>&1)
    $exitCode = $LASTEXITCODE
    $text = $output -join "`n"
    if ($ExpectedError) {
        Assert-True ($exitCode -ne 0 -and $text.Contains($ExpectedError)) "Expected '$ExpectedError', received: $text"
    }
    else {
        Assert-True ($exitCode -eq 0) "Deployment preview failed: $text"
    }
    return $text
}

function New-ManifestPath {
    Join-Path $releases ("release-{0}.json" -f [guid]::NewGuid().ToString('N'))
}

try {
    New-Item -ItemType Directory -Path $repository,$releases -Force | Out-Null
    Invoke-FixtureGit @('init', '--quiet')
    $repository = [System.IO.Path]::GetFullPath((& git -C $repository rev-parse --show-toplevel).Trim())
    Invoke-FixtureGit @('config', 'user.name', 'Deployment fixture')
    Invoke-FixtureGit @('config', 'user.email', 'fixture@example.invalid')
    Invoke-FixtureGit @('config', 'core.autocrlf', 'false')
    Write-FixtureFile 'Tireweb Sites\Web\Scripts\base.js' 'base'
    Write-FixtureFile 'Tireweb Sites\Web\Scripts\space [asset].js' 'special'
    Write-FixtureFile '.gitignore' "**/Bin/`n**/bin/"
    Write-FixtureFile 'Customization\Customization.csproj' '<Project />'
    Write-FixtureFile 'Customization\obsolete.cs' 'old class'
    Invoke-FixtureGit @('add', '.')
    Invoke-FixtureGit @('commit', '--quiet', '-m', 'base')
    Invoke-FixtureGit @('branch', 'development')
    Write-FixtureFile 'Tireweb Sites\Web\Scripts\feature.js' 'committed'
    Invoke-FixtureGit @('add', '.')
    Invoke-FixtureGit @('commit', '--quiet', '-m', 'feature')
    Write-FixtureFile 'Tireweb Sites\Web\Scripts\feature.js' 'dirty'
    Write-FixtureFile 'Tireweb Sites\Web\Scripts\untracked.js' 'untracked'
    Write-FixtureFile 'Tireweb Sites\Web\Scripts\staged.js' 'staged'
    Invoke-FixtureGit @('add', 'Tireweb Sites/Web/Scripts/staged.js')

    $all = New-ManifestPath
    $null = Invoke-Deployment @{ ChangeScope = 'All'; BaseRef = 'development'; CreateDeploymentManifestPath = $all }
    $manifest = Get-Content $all -Raw | ConvertFrom-Json
    Assert-True ($manifest.assets.Count -eq 3) 'Mixed release includes committed, staged, and untracked paths.'
    Assert-True ($manifest.source_root -eq $repository -and $manifest.source_mode -eq 'WorkingTree') "Delegated release binds the developer checkout. Actual: $($manifest.source_root), $($manifest.source_mode). Expected: $repository"
    Assert-True ($manifest.remote_root -eq '/EOSB-test') 'Manifest binds staging root.'
    $hash = (Get-FileHash $all -Algorithm SHA256).Hash
    $null = Invoke-Deployment @{ DeploymentManifestPath = $all; DeploymentManifestSha256 = $hash }
    $null = Invoke-Deployment @{ DeploymentManifestPath = $all; DeploymentManifestSha256 = $hash; RemoteRoot = '/other' } 'does not match'
    $otherCheckout = Join-Path $fixtureRoot 'deploying checkout'
    & git clone --quiet --local $repository $otherCheckout
    Assert-True ($LASTEXITCODE -eq 0) 'Second-session checkout fixture is available.'
    $null = Invoke-Deployment @{ DeploymentManifestPath = $all; DeploymentManifestSha256 = $hash; RepositoryRoot = $otherCheckout } 'does not match'
    $null = Invoke-Deployment @{ DeploymentManifestPath = $all; DeploymentManifestSha256 = ('0' * 64) } 'manifest changed'
    $null = Invoke-Deployment @{ DeploymentManifestPath = $all; WhatIf = $false } 'Manifest SHA256'
    $null = Invoke-Deployment @{ DeploymentManifestPath = $all; IncludePaths = @('base.js') } 'cannot be combined'
    $null = Invoke-Deployment @{ CreateDeploymentManifestPath = $all } 'overwrite'
    Write-FixtureFile 'Tireweb Sites\Web\Scripts\feature.js' 'changed after preview'
    $null = Invoke-Deployment @{ DeploymentManifestPath = $all; DeploymentManifestSha256 = $hash } 'hash does not match'

    $branch = New-ManifestPath
    $null = Invoke-Deployment @{ ChangeScope = 'Branch'; BaseRef = 'development'; CreateDeploymentManifestPath = $branch }
    $committed = Get-Content $branch -Raw | ConvertFrom-Json
    Assert-True ($committed.assets.Count -eq 1 -and $committed.source_mode -eq 'Committed') 'Branch release excludes uncommitted paths.'
    Assert-True ([System.IO.File]::ReadAllText((Join-Path $committed.source_root 'Tireweb Sites\Web\Scripts\feature.js')) -eq 'committed') 'Branch release uses committed bytes, not dirty bytes.'
    $null = Invoke-Deployment @{ DeploymentManifestPath = $branch; DeploymentManifestSha256 = (Get-FileHash $branch).Hash }
    $null = Invoke-Deployment @{ ChangeScope = 'Branch'; BaseRef = 'missing'; CreateDeploymentManifestPath = (New-ManifestPath) } 'does not resolve'

    Write-FixtureFile 'Tireweb Sites\Web\Bin\manual.dll' 'ignored DLL'
    $explicit = New-ManifestPath
    $null = Invoke-Deployment @{
        IncludePaths = @('base.js','Scripts\space [asset].js','Tireweb Sites\Web\Bin\manual.dll','Scripts\base.js')
        CreateDeploymentManifestPath = $explicit
    }
    $listed = Get-Content $explicit -Raw | ConvertFrom-Json
    Assert-True ($listed.assets.Count -eq 3) 'Explicit unchanged paths, web-relative paths, special characters, ignored DLLs and deduplication work.'
    $null = Invoke-Deployment @{ IncludePaths = @('missing.js'); CreateDeploymentManifestPath = (New-ManifestPath) } 'No deployable file'
    Write-FixtureFile 'Tireweb Sites\Web\Other\base.js' 'duplicate'
    $null = Invoke-Deployment @{ IncludePaths = @('base.js'); CreateDeploymentManifestPath = (New-ManifestPath) } 'Ambiguous filename'
    $null = Invoke-Deployment @{ IncludePaths = @('..\outside.js'); CreateDeploymentManifestPath = (New-ManifestPath) } 'unsafe repository path'
    foreach ($sensitive in @('.env.production.local','secrets.production.local.json','WebsiteOptions.config','App_Files\options.config')) {
        Write-FixtureFile "Tireweb Sites\Web\$sensitive" 'fixture-only'
        $null = Invoke-Deployment @{ IncludePaths = @("Tireweb Sites\Web\$sensitive"); CreateDeploymentManifestPath = (New-ManifestPath) } 'sensitive file'
        Remove-Item -LiteralPath (Join-Path $repository "Tireweb Sites\Web\$sensitive") -Force
    }
    $null = Invoke-Deployment @{ IncludePaths = @('Scripts\feature.js'); GenerateListFromGitLogArgs = @('HEAD') } 'cannot be combined'
    $null = Invoke-Deployment @{ IncludePaths = @('Scripts\feature.js'); VerificationAssets = @('Tireweb Sites/Web/Scripts/feature.js|file:///invalid') } 'HTTP(S)'
    $linkedDirectory = Join-Path $repository 'Tireweb Sites\Web\Linked'
    New-Item -ItemType Junction -Path $linkedDirectory -Target (Join-Path $repository 'Tireweb Sites\Web\Scripts') | Out-Null
    $null = Invoke-Deployment @{ IncludePaths = @('Tireweb Sites\Web\Linked\feature.js') } 'symbolic link or junction'
    [System.IO.Directory]::Delete($linkedDirectory)
    $nestedManifest = Join-Path $releases 'new manifest directory\release.json'
    $null = Invoke-Deployment @{ IncludePaths = @('Scripts\feature.js'); CreateDeploymentManifestPath = $nestedManifest; VerificationAssets = @('Tireweb Sites/Web/Scripts/feature.js|https://staging.example.invalid/Scripts/feature.js') }
    Assert-True (Test-Path -LiteralPath $nestedManifest -PathType Leaf) 'WhatIf prepares the manifest in a new artifact directory.'
    $staticManifest = Get-Content $nestedManifest -Raw | ConvertFrom-Json
    Assert-True ($staticManifest.verification_assets.Count -eq 1) 'Public verification mappings are bound to the manifest before upload.'

    $log = New-ManifestPath
    $null = Invoke-Deployment @{ GenerateListFromGitLogArgs = @('development..HEAD'); CreateDeploymentManifestPath = $log }
    Assert-True ((Get-Content $log -Raw | ConvertFrom-Json).assets.Count -eq 1) 'Git log paths are selected independently of working-tree edits.'
    $null = Invoke-Deployment @{ GenerateListFromGitLogArgs = @('--output=unexpected'); CreateDeploymentManifestPath = (New-ManifestPath) } 'cannot override'

    Write-FixtureFile 'Customization\Customization.csproj' '<Project>dirty source</Project>'
    $built = New-ManifestPath
    $null = Invoke-Deployment @{ IncludePaths = @('Customization\Customization.csproj'); MSBuildPath = (Join-Path $PSScriptRoot 'Fake-MSBuild.ps1'); CreateDeploymentManifestPath = $built }
    $builtManifest = Get-Content $built -Raw | ConvertFrom-Json
    Assert-True ($builtManifest.assets.Count -eq 1 -and $builtManifest.assets[0].repository_source_path -eq 'Tireweb Sites/Web/Bin/Customization.dll') 'Source project is replaced by its rebuilt DLL.'
    Write-FixtureFile 'Customization\fail-build' 'fail'
    $null = Invoke-Deployment @{ IncludePaths = @('Customization\Customization.csproj'); MSBuildPath = (Join-Path $PSScriptRoot 'Fake-MSBuild.ps1'); CreateDeploymentManifestPath = (New-ManifestPath) } 'MSBuild failed'
    Remove-Item -LiteralPath (Join-Path $repository 'Customization\fail-build') -Force
    Write-FixtureFile 'Customization\missing-output' 'missing'
    $null = Invoke-Deployment @{ IncludePaths = @('Customization\Customization.csproj'); MSBuildPath = (Join-Path $PSScriptRoot 'Fake-MSBuild.ps1'); CreateDeploymentManifestPath = (New-ManifestPath) } 'expected DLL was not found'
    Remove-Item -LiteralPath (Join-Path $repository 'Customization\missing-output') -Force

    Write-FixtureFile 'Tireweb Sites\Sites\packages.config' '<packages><package id="fixture" version="1.0" /></packages>'
    Write-FixtureFile 'Tireweb Sites\Tireweb Sites.sln' 'fixture solution'
    $null = Invoke-Deployment @{ IncludePaths = @('Customization\Customization.csproj'); MSBuildPath = (Join-Path $PSScriptRoot 'Fake-MSBuild.ps1'); CreateDeploymentManifestPath = (New-ManifestPath) }
    Assert-True (Test-Path -LiteralPath (Join-Path $repository 'Tireweb Sites\restore-called')) 'Missing declared package directories trigger existing package restore.'
    Remove-Item -LiteralPath (Join-Path $repository 'Tireweb Sites\Sites\packages.config') -Force
    Remove-Item -LiteralPath (Join-Path $repository 'Tireweb Sites\Tireweb Sites.sln') -Force
    Remove-Item -LiteralPath (Join-Path $repository 'Tireweb Sites\restore-called') -Force

    Remove-Item -LiteralPath (Join-Path $repository 'Customization\obsolete.cs') -Force
    $deletedSource = New-ManifestPath
    $deletedPreview = Invoke-Deployment @{ MSBuildPath = (Join-Path $PSScriptRoot 'Fake-MSBuild.ps1'); CreateDeploymentManifestPath = $deletedSource }
    $deletedManifest = Get-Content $deletedSource -Raw | ConvertFrom-Json
    Assert-True (@($deletedManifest.assets | Where-Object { $_.repository_source_path -eq 'Tireweb Sites/Web/Bin/Customization.dll' }).Count -eq 1) 'Deleted project source still triggers a DLL rebuild.'
    Assert-True ($deletedPreview.Contains('Customization/obsolete.cs')) 'Deleted source is reported rather than uploaded.'

    Invoke-FixtureGit @('add', 'Customization')
    Invoke-FixtureGit @('commit', '--quiet', '-m', 'compiled feature')
    Write-FixtureFile 'Customization\Customization.csproj' '<Project>new dirty source</Project>'
    $compiledBranch = New-ManifestPath
    $null = Invoke-Deployment @{ ChangeScope = 'Branch'; BaseRef = 'development'; MSBuildPath = (Join-Path $PSScriptRoot 'Fake-MSBuild.ps1'); CreateDeploymentManifestPath = $compiledBranch }
    $compiled = Get-Content $compiledBranch -Raw | ConvertFrom-Json
    Assert-True ([System.IO.File]::ReadAllText((Join-Path $compiled.source_root 'Tireweb Sites\Web\Bin\Customization.dll')) -eq 'built:<Project>dirty source</Project>') 'Committed DLLs are rebuilt from committed project inputs, not dirty project inputs.'
    $null = Invoke-Deployment @{ DeploymentManifestPath = $branch; DeploymentManifestSha256 = (Get-FileHash $branch).Hash } 'does not match manifest release_commit'

    $backupScript = Join-Path (Split-Path (Split-Path $skillRoot -Parent) -Parent) 'backup-staging-files\Backup-StagingFiles.ps1'
    if (Test-Path -LiteralPath $backupScript -PathType Leaf) {
        $backupDirectory = Join-Path $fixtureRoot 'backups'
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        Remove-Item -LiteralPath (Join-Path $repository 'Tireweb Sites\Web\Bin\Customization.dll') -Force
        $engine = $backupScript
        try {
            $backupPreview = Invoke-Deployment @{
                IncludePaths = @('Tireweb Sites/Web/Bin/Customization.dll')
                ContentRoot = $compiled.source_root
                DeploySkillRoot = $skillRoot
                BackupRoot = $backupDirectory
            }
            Assert-True ($backupPreview.Contains('/EOSB-test/Bin/Customization.dll')) 'Backup maps committed snapshot DLLs even when the developer checkout lacks the staged DLL.'
        }
        finally {
            $engine = Join-Path $skillRoot 'Deploy-Staging.ps1'
        }
    }

    $tampered = Get-Content $explicit -Raw | ConvertFrom-Json
    $tampered.assets[0].repository_source_path = 'Tireweb Sites/Web/WebsiteOptions.config'
    $tampered | ConvertTo-Json -Depth 5 | Set-Content $explicit -Encoding UTF8
    $tampered.release_commit = (& git -C $repository rev-parse HEAD).Trim()
    $tampered | ConvertTo-Json -Depth 5 | Set-Content $explicit -Encoding UTF8
    $null = Invoke-Deployment @{ DeploymentManifestPath = $explicit } 'sensitive file'

    Write-FixtureFile 'Tireweb Sites\Web\Scripts\base.js' 'temporary committed edit'
    Invoke-FixtureGit @('add', 'Tireweb Sites/Web/Scripts/base.js')
    Invoke-FixtureGit @('commit', '--quiet', '-m', 'temporary change')
    Write-FixtureFile 'Tireweb Sites\Web\Scripts\base.js' 'base'
    Invoke-FixtureGit @('add', 'Tireweb Sites/Web/Scripts/base.js')
    Invoke-FixtureGit @('commit', '--quiet', '-m', 'revert change')
    $netBranch = New-ManifestPath
    $null = Invoke-Deployment @{ ChangeScope = 'Branch'; BaseRef = 'development'; MSBuildPath = (Join-Path $PSScriptRoot 'Fake-MSBuild.ps1'); CreateDeploymentManifestPath = $netBranch }
    $netManifest = Get-Content $netBranch -Raw | ConvertFrom-Json
    Assert-True (@($netManifest.assets | Where-Object { $_.repository_source_path -eq 'Tireweb Sites/Web/Scripts/base.js' }).Count -eq 0) 'Committed selection uses net feature changes, excluding reverted history.'

    Write-FixtureFile '.gitattributes' 'Tireweb?Sites/Web/Scripts/feature.js export-ignore'
    Invoke-FixtureGit @('add', '.gitattributes')
    Invoke-FixtureGit @('commit', '--quiet', '-m', 'export omission fixture')
    $null = Invoke-Deployment @{ ChangeScope = 'Branch'; BaseRef = 'development'; MSBuildPath = (Join-Path $PSScriptRoot 'Fake-MSBuild.ps1'); CreateDeploymentManifestPath = (New-ManifestPath) } 'snapshot omitted a selected file'

    . (Join-Path $skillRoot 'StagingDeploymentSettings.ps1')
    $settingsA = Join-Path $releases 'chat-a.json'
    $settingsB = Join-Path $releases 'chat-b.json'
    $null = Set-StagingDeploymentRemoteRoot -SettingsPath $settingsA -RemoteRoot 'EOSB-a'
    $null = Set-StagingDeploymentRemoteRoot -SettingsPath $settingsB -RemoteRoot 'EOSB-b'
    Assert-True ((Get-StagingDeploymentRemoteRoot -SettingsPath $settingsA) -eq '/EOSB-a') 'Chat targets remain independent.'
    Assert-True ((Get-StagingDeploymentSettingsPath -SessionId 'chat-a') -ne (Get-StagingDeploymentSettingsPath -SessionId 'chat-b')) 'Default settings paths are session-scoped.'
    $rejected = $false
    try { Get-StagingDeploymentSettingsPath -SessionId '' | Out-Null } catch { $rejected = $true }
    Assert-True $rejected 'Missing session ID cannot fall back to a user-wide target.'

    Write-Host "Passed $checks staging-deployment checks. No staging connection was opened."
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}
