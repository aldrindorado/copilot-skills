[CmdletBinding()]
param(
    [string]$Target = 'Ezytire.Staging.SFTP',
    [Parameter(Mandatory = $true)]
    [string]$UserName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'StagingCredential.ps1')

$credential = Get-Credential -UserName $UserName -Message 'Enter the FileZilla Normal-login password for Ezytire staging.'
if ($null -eq $credential) {
    throw 'No staging credential was entered.'
}

if ($credential.UserName -ne $UserName) {
    throw "The staging SFTP user must be '$UserName'."
}

Set-StagingCredential -Target $Target -Credential $credential
Write-Host "Saved the staging SFTP credential in Windows Credential Manager as '$Target'."
