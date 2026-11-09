param(
    [Parameter(Position = 0)][string]$ProjectPath,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$BuildArguments
)

if (Test-Path -LiteralPath (Join-Path (Split-Path $ProjectPath -Parent) 'fail-build')) {
    Write-Output 'Fixture build failure.'
    $global:LASTEXITCODE = 1
    return
}
if ($BuildArguments -contains '/t:Restore') {
    $restoreLog = Join-Path (Split-Path $ProjectPath -Parent) 'restore-called'
    [System.IO.File]::WriteAllText($restoreLog, 'restored')
    $global:LASTEXITCODE = 0
    return
}
if (Test-Path -LiteralPath (Join-Path (Split-Path $ProjectPath -Parent) 'missing-output')) {
    $global:LASTEXITCODE = 0
    return
}
$output = Join-Path (Split-Path $ProjectPath -Parent) 'bin\Release'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$name = [System.IO.Path]::GetFileNameWithoutExtension($ProjectPath)
if ($name -eq 'Sites') {
    $name = 'Tireweb.Sites'
}
[System.IO.File]::WriteAllText((Join-Path $output "$name.dll"), "built:$([System.IO.File]::ReadAllText($ProjectPath))")
$global:LASTEXITCODE = 0
