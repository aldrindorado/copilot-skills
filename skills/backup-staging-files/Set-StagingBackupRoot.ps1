[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackupRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'StagingBackupSettings.ps1')

$savedRoot = Set-StagingBackupRoot -BackupRoot $BackupRoot
Write-Host "Staging backup directory saved: $savedRoot"
