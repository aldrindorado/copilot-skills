[CmdletBinding()]
param(
    [string]$KeyPath = (Join-Path $HOME '.ssh\ezytire-staging'),
    [string]$Comment = 'aldrin.d@ezytire-staging'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue)) {
    throw 'Windows OpenSSH Client is required to generate a staging key.'
}

if (-not (Get-Command ssh-add.exe -ErrorAction SilentlyContinue)) {
    throw 'Windows OpenSSH Authentication Agent is required to load a staging key.'
}

$KeyPath = [System.IO.Path]::GetFullPath($KeyPath)
$publicKeyPath = $KeyPath + '.pub'
if ((Test-Path -LiteralPath $KeyPath) -or (Test-Path -LiteralPath $publicKeyPath)) {
    throw "A staging key already exists at $KeyPath. Refusing to overwrite it."
}

$keyDirectory = Split-Path -Path $KeyPath -Parent
if (-not (Test-Path -LiteralPath $keyDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $keyDirectory -Force | Out-Null
}

Write-Host 'Enter a strong passphrase when prompted. The passphrase is not stored by this script.'
& ssh-keygen.exe -t rsa -b 4096 -f $KeyPath -C $Comment
if ($LASTEXITCODE -ne 0) {
    throw 'SSH key generation failed.'
}

& ssh-add.exe $KeyPath
if ($LASTEXITCODE -ne 0) {
    throw "The key was created but could not be loaded into ssh-agent. Start the ssh-agent service, then run: ssh-add `"$KeyPath`""
}

Write-Host ''
Write-Host 'Give this public key to the staging-server administrator for the aldrin.d account:'
Get-Content -LiteralPath $publicKeyPath
