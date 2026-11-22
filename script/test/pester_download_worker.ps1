#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$OutFile)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../docker/download_library.ps1')
try {
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 Invoke-ContainerOfficialDownload -Uri 'https://www.powershellgallery.com/api/v2/package/Pester/6.0.0' -OutFile $OutFile -MaxAttempts 1 -RequestTimeoutSeconds 30 | Out-Null
 exit 0
} catch {
 $kind=Get-ContainerDownloadFailureKind -Exception $_.Exception
 [Console]::Out.WriteLine('PESTER-FAILURE:'+ $kind)
 exit 1
}
