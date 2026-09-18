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

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is required to locate the repository root.'
}

$repositoryRoot = (& git -C $RepositoryRoot rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to locate the Git repository root.'
}
$repositoryRoot = [System.IO.Path]::GetFullPath($repositoryRoot)

$webBinPath = Join-Path $repositoryRoot 'Tireweb Sites\Web\Bin'
if (-not (Test-Path -LiteralPath $webBinPath -PathType Container)) {
    throw "The web Bin directory does not exist: $webBinPath"
}

$normalizedChangedPaths = @(
    $ChangedPaths |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim().Replace('\', '/') } |
        Sort-Object -Unique
)
if ($normalizedChangedPaths.Count -eq 0) {
    throw 'At least one changed path is required.'
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

$msbuild = Get-MSBuildExecutable -ConfiguredPath $MSBuildPath
$referencePath = Join-Path $repositoryRoot 'Assemblies'
$preparedDlls = @()

foreach ($mapping in $affectedMappings) {
    $projectPath = Join-Path $repositoryRoot $mapping.ProjectPath
    if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
        throw "The mapped project was not found: $projectPath"
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

    $projectDirectory = Split-Path -Path $projectPath -Parent
    $sourceDllPath = Join-Path $projectDirectory ("bin\{0}\{1}" -f $Configuration, $mapping.DllName)
    if (-not (Test-Path -LiteralPath $sourceDllPath -PathType Leaf)) {
        throw "The build succeeded but the expected DLL was not found: $sourceDllPath"
    }

    $webDllPath = Join-Path $webBinPath $mapping.DllName
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
