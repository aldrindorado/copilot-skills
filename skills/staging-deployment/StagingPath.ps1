Set-StrictMode -Version Latest

function Assert-StagingRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/')
    if ([System.IO.Path]::IsPathRooted($normalized) -or
        $normalized -match '(^|/)\.\.(/|$)' -or $normalized.Contains(':')) {
        throw "Refusing to deploy an unsafe repository path: $RelativePath"
    }
    foreach ($component in $normalized.Split('/')) {
        if ([string]::IsNullOrEmpty($component) -or $component -match '[. ]$') {
            throw "Refusing to deploy a noncanonical repository path: $RelativePath"
        }
    }
}

function Get-StagingSafeLocalPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    Assert-StagingRelativePath -RelativePath $RelativePath
    $root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    $localPath = [System.IO.Path]::GetFullPath((Join-Path $root $RelativePath.Replace('/', '\')))
    if (-not $localPath.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to deploy a file outside the repository: $RelativePath"
    }
    $currentPath = $localPath
    while ($currentPath.Length -ge $root.Length) {
        if (Test-Path -LiteralPath $currentPath) {
            $item = Get-Item -LiteralPath $currentPath -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to deploy through a symbolic link or junction: $RelativePath"
            }
        }
        $currentPath = Split-Path -Path $currentPath -Parent
    }
    return $localPath
}
