[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Get-Location).Path,

    [Parameter(Mandatory = $true)]
    [string[]]$ChangedPaths,

    [string]$Configuration = 'Release',

    [string]$MSBuildPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Deployment -WhatIf previews prepare real local artifacts, never remote writes.
$WhatIfPreference = $false

. (Join-Path $PSScriptRoot 'StagingPath.ps1')

function Get-MSBuildExecutable {
    param(
        [string]$ConfiguredPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        $resolvedConfiguredPath = [System.IO.Path]::GetFullPath($ConfiguredPath)
        if (-not (Test-Path -LiteralPath $resolvedConfiguredPath -PathType Leaf)) {
            throw "The configured MSBuild executable was not found: $resolvedConfiguredPath"
        }

        return $resolvedConfiguredPath
    }

    $msbuildCommand = Get-Command msbuild -ErrorAction SilentlyContinue
    if ($null -ne $msbuildCommand) {
        return $msbuildCommand.Source
    }

    $vswherePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswherePath -PathType Leaf) {
        $discoveredPaths = @(
            & $vswherePath -latest -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe'
        )
        $discoveredPath = $discoveredPaths | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($discoveredPath)) {
            return $discoveredPath
        }
    }

    $knownPaths = @(
        'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe',
        'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
    )
    foreach ($knownPath in $knownPaths) {
        if (Test-Path -LiteralPath $knownPath -PathType Leaf) {
            return $knownPath
        }
    }

    throw 'MSBuild was not found. Install Visual Studio Build Tools or supply -MSBuildPath.'
}

$repositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
$webRootPath = Get-StagingSafeLocalPath -RepositoryRoot $repositoryRoot -RelativePath 'Tireweb Sites\Web'
if (-not (Test-Path -LiteralPath $webRootPath -PathType Container)) {
    throw "The source checkout or committed snapshot has no web root: $repositoryRoot"
}

$normalizedChangedPaths = @(
    $ChangedPaths |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Replace('\', '/') } |
        Sort-Object -Unique
)
if ($normalizedChangedPaths.Count -eq 0) {
    throw 'At least one changed path is required.'
}
foreach ($changedPath in $normalizedChangedPaths) {
    $null = Get-StagingSafeLocalPath -RepositoryRoot $repositoryRoot -RelativePath $changedPath
}

# Keep this explicit so an unrelated project is never built or deployed implicitly.
$projectMappings = @(
    [PSCustomObject]@{
        Prefix = 'Charlie/'
        ProjectPath = 'Charlie\Charlie.csproj'
        DllName = 'Charlie.dll'
    },
    [PSCustomObject]@{
        Prefix = 'Tireweb Business/'
        ProjectPath = 'Tireweb Business\Tireweb Business.csproj'
        DllName = 'Tireweb Business.dll'
    },
    [PSCustomObject]@{
        Prefix = 'Poindexter/'
        ProjectPath = 'Poindexter\Poindexter.csproj'
        DllName = 'Poindexter.dll'
    },
    [PSCustomObject]@{
        Prefix = 'Wonky Wheel/Wonky/'
        ProjectPath = 'Wonky Wheel\Wonky\Wonky.csproj'
        DllName = 'Wonky.dll'
    },
    [PSCustomObject]@{
        Prefix = 'Tireweb Sites/Sites/'
        ProjectPath = 'Tireweb Sites\Sites\Sites.csproj'
        DllName = 'Tireweb.Sites.dll'
    },
    [PSCustomObject]@{
        Prefix = 'Customization/'
        ProjectPath = 'Customization\Customization.csproj'
        DllName = 'Customization.dll'
    }
)

$affectedMappings = @(
    foreach ($mapping in $projectMappings) {
        $hasChangedPath = $false
        foreach ($changedPath in $normalizedChangedPaths) {
            if ($changedPath.StartsWith($mapping.Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $hasChangedPath = $true
                break
            }
        }

        if ($hasChangedPath) {
            $mapping
        }
    }
)

if ($affectedMappings.Count -eq 0) {
    Write-Host 'No supported source projects were selected for building.'
    return
}

$webBinPath = Get-StagingSafeLocalPath -RepositoryRoot $repositoryRoot -RelativePath 'Tireweb Sites\Web\Bin'
foreach ($mapping in $affectedMappings) {
    $null = Get-StagingSafeLocalPath -RepositoryRoot $repositoryRoot -RelativePath $mapping.ProjectPath
    $projectRelativeDirectory = Split-Path -Path $mapping.ProjectPath -Parent
    $null = Get-StagingSafeLocalPath -RepositoryRoot $repositoryRoot -RelativePath (Join-Path $projectRelativeDirectory ("bin\{0}\{1}" -f $Configuration, $mapping.DllName))
    $null = Get-StagingSafeLocalPath -RepositoryRoot $repositoryRoot -RelativePath ("Tireweb Sites\Web\Bin\{0}" -f $mapping.DllName)
}
$msbuild = Get-MSBuildExecutable -ConfiguredPath $MSBuildPath
if (-not (Test-Path -LiteralPath $webBinPath -PathType Container)) {
    New-Item -ItemType Directory -Path $webBinPath -Force | Out-Null
}
$referencePath = Join-Path $repositoryRoot 'Assemblies'
$preparedDlls = @()

# Restore only when this checkout lacks its existing packages.config dependencies.
$packageConfigs = @(Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'Tireweb Sites') -Filter packages.config -Recurse -File)
$packagesMissing = $false
foreach ($packageConfig in $packageConfigs) {
    [xml]$packages = Get-Content -LiteralPath $packageConfig.FullName -Raw
    foreach ($package in @($packages.SelectNodes('/packages/package'))) {
        $packageDirectory = Join-Path $repositoryRoot ("Tireweb Sites\packages\{0}.{1}" -f $package.id, $package.version)
        if (-not (Test-Path -LiteralPath $packageDirectory -PathType Container)) {
            $packagesMissing = $true
        }
    }
}
if ($packagesMissing) {
    $solution = Join-Path $repositoryRoot 'Tireweb Sites\Tireweb Sites.sln'
    if (-not (Test-Path -LiteralPath $solution -PathType Leaf)) {
        throw "The package restore solution was not found: $solution"
    }
    $restoreOutput = @(& $msbuild $solution /t:Restore /p:RestorePackagesConfig=true /m /nologo /verbosity:minimal 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Package restore failed:`r`n$($restoreOutput -join [Environment]::NewLine)"
    }
    Write-Host ($restoreOutput -join [Environment]::NewLine)
}

foreach ($mapping in $affectedMappings) {
    $projectPath = Get-StagingSafeLocalPath -RepositoryRoot $repositoryRoot -RelativePath $mapping.ProjectPath
    if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
        throw "The mapped project was not found: $projectPath"
    }

    $projectRelativeDirectory = Split-Path -Path $mapping.ProjectPath -Parent
    $sourceRelativePath = Join-Path $projectRelativeDirectory ("bin\{0}\{1}" -f $Configuration, $mapping.DllName)
    $sourceDllPath = Get-StagingSafeLocalPath -RepositoryRoot $repositoryRoot -RelativePath $sourceRelativePath
    if (Test-Path -LiteralPath $sourceDllPath -PathType Leaf) {
        Remove-Item -LiteralPath $sourceDllPath -Force
    }
    Write-Host ("Building {0} ({1})..." -f $mapping.ProjectPath, $Configuration)
    $buildArguments = @(
        $projectPath,
        '/t:Rebuild',
        "/p:Configuration=$Configuration",
        '/p:GenerateSerializationAssemblies=Off',
        "/p:ReferencePath=$referencePath",
        '/m',
        '/nologo',
        '/verbosity:minimal'
    )
    $buildOutput = @(& $msbuild @buildArguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "MSBuild failed for '$($mapping.ProjectPath)':`r`n$($buildOutput -join [Environment]::NewLine)"
    }
    if ($buildOutput.Count -gt 0) {
        Write-Host ($buildOutput -join [Environment]::NewLine)
    }

    $sourceDllPath = Get-StagingSafeLocalPath -RepositoryRoot $repositoryRoot -RelativePath $sourceRelativePath
    if (-not (Test-Path -LiteralPath $sourceDllPath -PathType Leaf)) {
        throw "The build succeeded but the expected DLL was not found: $sourceDllPath"
    }

    $webDllPath = Get-StagingSafeLocalPath -RepositoryRoot $repositoryRoot -RelativePath ("Tireweb Sites\Web\Bin\{0}" -f $mapping.DllName)
    Copy-Item -LiteralPath $sourceDllPath -Destination $webDllPath -Force

    $webDll = Get-Item -LiteralPath $webDllPath
    $preparedDlls += [PSCustomObject]@{
        ProjectPath = $mapping.ProjectPath
        SourceDllPath = $sourceDllPath
        WebRelativePath = ('Tireweb Sites/Web/Bin/' + $mapping.DllName)
        WebDllPath = $webDll.FullName
        Length = $webDll.Length
        SHA256 = (Get-FileHash -LiteralPath $webDll.FullName -Algorithm SHA256).Hash
    }
}

Write-Host ("Prepared {0} DLL(s) in Tireweb Sites\Web\Bin:" -f $preparedDlls.Count)
foreach ($preparedDll in $preparedDlls) {
    Write-Host ("- {0} -> {1} ({2} bytes, SHA256 {3})" -f $preparedDll.ProjectPath, $preparedDll.WebRelativePath, $preparedDll.Length, $preparedDll.SHA256)
}

return $preparedDlls
