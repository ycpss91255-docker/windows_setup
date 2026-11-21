#Requires -Version 5.1
function Get-SetupEntryIdentity { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
function Test-SetupEntryAdministrator {
 $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
 return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Start-SetupEntryElevated {
 param([string]$Command,[switch]$UseSystemPowerShell)
 $executable=if($UseSystemPowerShell){Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell/v1.0/powershell.exe'}else{'powershell.exe'}
 Start-Process $executable -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command)))
}
