param(
    [string]$CompareUrl,
    [string]$Repo,
    [string]$Base,
    [string]$Head,
    [switch]$WithStatus
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-CompareTarget {
    param(
        [string]$CompareUrl,
        [string]$Repo,
        [string]$Base,
        [string]$Head
    )

    if ($CompareUrl) {
        $pattern = '^https?://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)/compare/(?<base>.+)\.\.\.(?<head>[^?]+)(?:\?.*)?$'
        $match = [regex]::Match($CompareUrl, $pattern)
        if (-not $match.Success) {
            throw "Invalid compare URL format: $CompareUrl"
        }

        $owner = $match.Groups["owner"].Value
        $repoName = $match.Groups["repo"].Value
        $baseRef = [System.Uri]::UnescapeDataString($match.Groups["base"].Value)
        $headRef = [System.Uri]::UnescapeDataString($match.Groups["head"].Value)
        return @{
            Repo = $owner + "/" + $repoName
            Base = $baseRef
            Head = $headRef
        }
    }

    if (-not $Repo -or -not $Base -or -not $Head) {
        throw "Provide either -CompareUrl or all of -Repo, -Base, and -Head."
    }

    return @{
        Repo = $Repo
        Base = $Base
        Head = $Head
    }
}

$target = Resolve-CompareTarget -CompareUrl $CompareUrl -Repo $Repo -Base $Base -Head $Head
$jqFilter = ".files[].filename"
if ($WithStatus) {
    $jqFilter = '.files[] | "\(.status)`t\(.filename)"'
}

& gh api ("repos/" + $target.Repo + "/compare/" + $target.Base + "..." + $target.Head) --jq $jqFilter
