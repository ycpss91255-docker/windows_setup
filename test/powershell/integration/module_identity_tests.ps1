#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
. (Join-Path $root 'core/hardware.ps1')
. (Join-Path $root 'core/entry_os_boundary.ps1')
Assert ((Test-SetupAdministrator) -eq (Test-SetupEntryAdministrator)) 'old and entry administrator boundaries agree for current identity'
$boundaryFixture=Join-Path $env:TEMP ('run_module_boundary_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($boundaryFixture)
$boundaryEntry=Join-Path $boundaryFixture 'run_module.ps1'
Copy-Item -LiteralPath (Join-Path $root 'core/run_module.ps1') -Destination $boundaryEntry
[IO.File]::WriteAllText((Join-Path $boundaryFixture 'entry_os_boundary.ps1'),"function Get-SetupEntryIdentity { 'fixture-sid' }`nfunction Test-SetupEntryAdministrator { `$env:RUN_MODULE_FIXTURE_ADMIN -eq 'true' }`nfunction Start-SetupEntryElevated { param(`$Command) [IO.File]::WriteAllText((Join-Path `$PSScriptRoot 'captured.txt'),`$Command) }",[Text.UTF8Encoding]::new($true))
[IO.File]::WriteAllText((Join-Path $boundaryFixture 'paths.ps1'),"[IO.File]::WriteAllText((Join-Path `$PSScriptRoot 'paths_loaded.txt'),'loaded')`nfunction Test-SetupAdministrator { throw 'legacy admin boundary reached' }`nfunction Start-Process { throw 'blocked process' }`nfunction Add-Type { throw 'blocked native' }`nfunction Get-ItemProperty { throw 'blocked registry' }`nfunction Set-ItemProperty { throw 'blocked registry' }`nfunction New-ItemProperty { throw 'blocked registry' }`nfunction Remove-ItemProperty { throw 'blocked registry' }`nfunction Get-Service { throw 'blocked service' }`nfunction Set-Service { throw 'blocked service' }`nfunction Start-Service { throw 'blocked service' }`nfunction Register-ScheduledTask { throw 'blocked task' }`nfunction Resolve-NucPath { param(`$Name) if(`$Name -notmatch '^[A-Za-z0-9-]+[.]ps1`$'){throw 'unexpected module'};Join-Path `$PSScriptRoot 'dummy.ps1' }",[Text.UTF8Encoding]::new($true))
[IO.File]::WriteAllText((Join-Path $boundaryFixture 'dummy.ps1'),"param([switch]`$VerifyOnly,[switch]`$Restore,[switch]`$SyncOnly,[string]`$Mode,[string]`$DriverPackagePath,[string]`$ConfirmedBoard,[string]`$ConfirmationComputer,[switch]`$NonInteractive,[switch]`$ApplyPolicy)`n`$PSBoundParameters|ConvertTo-Json -Compress|Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'dummy.json') -Encoding UTF8",[Text.UTF8Encoding]::new($true))
$env:RUN_MODULE_FIXTURE_ADMIN='false'
$boundaryError='';try{& $boundaryEntry -Module Apply-HostsSync -ExpectedUserSID 'fixture-sid' -VerifyOnly -Mode SSH}catch{$boundaryError=$_.Exception.Message}
Assert (Test-Path -LiteralPath (Join-Path $boundaryFixture 'captured.txt')) ('run_module uses replaceable identity and elevation boundary: '+$boundaryError)
function Read-BoundaryCommand {
 $text=[IO.File]::ReadAllText((Join-Path $boundaryFixture 'captured.txt'));$t=$null;$e=$null
 $tree=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$t,[ref]$e);$statements=@($tree.EndBlock.Statements)
 if($e.Count -or $statements.Count -ne 1 -or $statements[0] -isnot [Management.Automation.Language.PipelineAst] -or $statements[0].PipelineElements.Count -ne 1){throw 'unexpected captured syntax'}
 $cmd=$statements[0].PipelineElements[0]
 if($cmd -isnot [Management.Automation.Language.CommandAst] -or $cmd.InvocationOperator -ne 'Ampersand' -or $cmd.Redirections.Count){throw 'unexpected captured command'}
 $parts=@($cmd.CommandElements)
 if($parts[0] -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $parts[0].Value -cne $boundaryEntry){throw 'unexpected captured target'}
 $values=@{};for($i=1;$i -lt $parts.Count;$i++){
  if($parts[$i] -isnot [Management.Automation.Language.CommandParameterAst] -or $null -ne $parts[$i].Argument){throw 'unexpected captured argument'}
  $key=$parts[$i].ParameterName;if($key -notin @('Module','ExpectedUserSID','VerifyOnly','ApplyPolicy','Restore','Mode','SyncOnly','DriverPackagePath','NonInteractive','ConfirmedBoard','ConfirmationComputer') -or $values.ContainsKey($key)){throw 'unexpected or duplicate parameter'}
  if($i+1 -lt $parts.Count -and $parts[$i+1] -is [Management.Automation.Language.StringConstantExpressionAst]){$i++;$values[$key]=$parts[$i].Value}else{$values[$key]=$true}
 }
 return $values
}
$capture=Read-BoundaryCommand
Assert ($capture.Module -ceq 'Apply-HostsSync' -and $capture.ExpectedUserSID -ceq 'fixture-sid' -and $capture.VerifyOnly -and $capture.Mode -ceq 'SSH') 'captured elevation retains original identity and requested flags'
foreach($provided in @($false,$true)){
 $args=@{Module='Install-Drivers';ExpectedUserSID='fixture-sid'};if($provided){$args.DriverPackagePath=''}
 & $boundaryEntry @args;$capture=Read-BoundaryCommand
 Assert ($capture.ContainsKey('DriverPackagePath') -eq $provided -and (-not $provided -or $capture.DriverPackagePath -ceq '')) ('captured elevation preserves omitted versus empty driver path: '+$provided)
}
$quoted=Join-Path $boundaryFixture "drivers ' 中文"
& $boundaryEntry -Module Install-Drivers -ExpectedUserSID 'fixture-sid' -DriverPackagePath $quoted -ConfirmedBoard 'board''quoted' -ConfirmationComputer 'machine''quoted' -NonInteractive
$capture=Read-BoundaryCommand
Assert ($capture.DriverPackagePath -ceq $quoted -and $capture.ConfirmedBoard -ceq "board'quoted" -and $capture.ConfirmationComputer -ceq "machine'quoted" -and $capture.NonInteractive) 'captured elevation preserves quoted paths and hardware confirmation'
$capturePath=Join-Path $boundaryFixture 'captured.txt';$dummyPath=Join-Path $boundaryFixture 'dummy.json'
$pathsMarker=Join-Path $boundaryFixture 'paths_loaded.txt'
[IO.File]::Delete($capturePath);[IO.File]::Delete($dummyPath);[IO.File]::Delete($pathsMarker);$rejected=$false;try{& $boundaryEntry -Module Apply-UACSettings -ExpectedUserSID 'other'}catch{$rejected=$true}
Assert ($rejected -and -not (Test-Path $capturePath) -and -not (Test-Path $dummyPath) -and -not (Test-Path $pathsMarker)) 'different elevation account is rejected before paths, launch or module'
foreach($admin in @('false','true')){
 $env:RUN_MODULE_FIXTURE_ADMIN=$admin
 foreach($invalid in @(@{Module='Unknown'},@{Module='Apply-UACSettings';ApplyPolicy=$true},@{Module='Apply-UACSettings';Restore=$true;VerifyOnly=$true},@{Module='Apply-PrivacySettings';Restore=$true},@{Module='Apply-PrivacySettings';SyncOnly=$true},@{Module='Apply-PrivacySettings';Mode='SSH'})){
  [IO.File]::Delete($capturePath);[IO.File]::Delete($dummyPath);$rejected=$false
  try{& $boundaryEntry @invalid}catch{$rejected=$true}
  Assert ($rejected -and -not (Test-Path $capturePath) -and -not (Test-Path $dummyPath)) ('invalid arguments rejected before launcher or module '+$admin+': '+($invalid|ConvertTo-Json -Compress))
 }
}
$allowed=@('Apply-UACSettings','Apply-PrivacySettings','Apply-HostsSync','Remove-OneDrive','Remove-SetupResidue','Apply-ExplorerSettings','Apply-TerminalHotkey','Apply-InputMethodSettings','Apply-StartMenuSettings','Apply-AMDPrivacySettings','Apply-CopilotSettings','Apply-AutologonSettings','Apply-PowerSettings','Apply-SSHSettings','Apply-MdnsSettings','Install-Drivers','Install-WindowsUpdates','Apply-Debloat','Apply-TaskbarSettings','Apply-DisplaySettings','Apply-DesktopSettings','Apply-ThemeSettings','Desktop-IconLayout','Apply-PagefileSettings')
foreach($module in $allowed){$env:RUN_MODULE_FIXTURE_ADMIN='false';& $boundaryEntry -Module $module;$capture=Read-BoundaryCommand;Assert ($capture.Module -ceq $module -and $capture.ExpectedUserSID -ceq 'fixture-sid') ('allowed module reaches only fake elevation: '+$module)}
$env:RUN_MODULE_FIXTURE_ADMIN='false';& $boundaryEntry -Module Apply-UACSettings -Restore;$capture=Read-BoundaryCommand
Assert $capture.Restore 'UAC restore survives elevation'
& $boundaryEntry -Module Apply-StartMenuSettings -ApplyPolicy -VerifyOnly;$capture=Read-BoundaryCommand
Assert ($capture.VerifyOnly -and -not $capture.ContainsKey('ApplyPolicy')) 'VerifyOnly suppresses ApplyPolicy during elevation'
$env:RUN_MODULE_FIXTURE_ADMIN='true'
foreach($module in $allowed){[IO.File]::Delete($dummyPath);& $boundaryEntry -Module $module;Assert (Test-Path $dummyPath) ('allowed module reaches only fixed dummy: '+$module)}
foreach($provided in @($false,$true)){
 $args=@{Module='Install-Drivers'};if($provided){$args.DriverPackagePath=''}
 & $boundaryEntry @args;$direct=Get-Content $dummyPath -Raw|ConvertFrom-Json
 Assert (($null -ne $direct.PSObject.Properties['DriverPackagePath']) -eq $provided) ('direct dispatch preserves omitted versus empty driver path: '+$provided)
}
& $boundaryEntry -Module Install-Drivers -DriverPackagePath $quoted -ConfirmedBoard "board'quoted" -ConfirmationComputer "machine'quoted" -NonInteractive -VerifyOnly;$direct=Get-Content $dummyPath -Raw|ConvertFrom-Json
Assert ($direct.DriverPackagePath -ceq $quoted -and $direct.ConfirmedBoard -ceq "board'quoted" -and $direct.ConfirmationComputer -ceq "machine'quoted" -and $direct.NonInteractive.IsPresent -and $direct.VerifyOnly.IsPresent) 'direct dispatch preserves quoted path and hardware confirmation'
& $boundaryEntry -Module Apply-UACSettings -Restore;$direct=Get-Content $dummyPath -Raw|ConvertFrom-Json
Assert $direct.Restore.IsPresent 'direct UAC restore reaches fixed dummy'
& $boundaryEntry -Module Apply-HostsSync -Mode Hosts -SyncOnly;$direct=Get-Content $dummyPath -Raw|ConvertFrom-Json
Assert ($direct.Mode -ceq 'Hosts' -and $direct.SyncOnly.IsPresent) 'direct hosts sync retains mode and sync-only'
& $boundaryEntry -Module Apply-HostsSync -Mode SSH -VerifyOnly -SyncOnly;$direct=Get-Content $dummyPath -Raw|ConvertFrom-Json
Assert ($direct.Mode -ceq 'SSH' -and $direct.VerifyOnly.IsPresent -and $null -eq $direct.PSObject.Properties['SyncOnly']) 'hosts verification has priority over sync-only'
& $boundaryEntry -Module Apply-StartMenuSettings -VerifyOnly -ApplyPolicy -NonInteractive;$direct=Get-Content $dummyPath -Raw|ConvertFrom-Json
Assert ($direct.VerifyOnly.IsPresent -and -not $direct.ApplyPolicy.IsPresent -and $direct.NonInteractive.IsPresent) 'start verification suppresses policy application'
& $boundaryEntry -Module Desktop-IconLayout -VerifyOnly;$direct=Get-Content $dummyPath -Raw|ConvertFrom-Json
Assert ($direct.Mode -ceq 'Verify') 'desktop verification passes finite mode to fixed dummy'
Remove-Item Env:RUN_MODULE_FIXTURE_ADMIN
$tokens=$null;$errors=$null
$entry=Join-Path $boundaryFixture 'desktop_dummy.ps1'
[IO.File]::WriteAllText($entry,'param($ExpectedUserSID,$Mode)',[Text.UTF8Encoding]::new($true))
function Start-Process {param($FilePath,$Verb,$ArgumentList);$script:captured=$ArgumentList}
# The layout Save shortcut calls its script directly rather than run_module.
$layout=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'modules/desktop/desktop_icon_layout.ps1'),[ref]$tokens,[ref]$errors)
$layoutElevation=$layout.Find({param($a) $a -is [Management.Automation.Language.IfStatementAst] -and $a.Clauses[0].Item1.Extent.Text -like '-not $principal.IsInRole*'},$true)
$layoutBody=(@($layoutElevation.Clauses[0].Item2.Statements|Where-Object {$_ -isnot [Management.Automation.Language.ExitStatementAst]}|ForEach-Object {$_.Extent.Text}) -join "`n").Replace('$PSCommandPath','$entry')
$Mode='Save';$sid='S-1-5-21-111-222-333-1001';$currentSID=$sid;$Worker=$false;$VerificationRunId=''
& ([scriptblock]::Create($layoutBody))
$layoutCommand=$script:captured
if($layoutCommand.Contains('-EncodedCommand ')){$layoutCommand=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($layoutCommand -split '-EncodedCommand ')[1]))}
Assert ($layoutCommand.Contains('-ExpectedUserSID') -and $layoutCommand.Contains($sid)) 'direct layout Save elevation also binds the original user'
$layoutGuard=$layout.Find({param($a) $a -is [Management.Automation.Language.IfStatementAst] -and $a.Clauses[0].Item1.Extent.Text -match '^\$ExpectedUserSID -and'},$true)
Assert ($null -ne $layoutGuard) 'direct layout Save contains an executable identity guard'
$ExpectedUserSID='original';$sid='different';$currentSID=$sid;$refused=$false
try{. ([scriptblock]::Create($layoutGuard.Extent.Text))}catch{$refused=$true}
Assert $refused 'direct layout Save rejects a changed elevation account before saving'
& {
 . (Join-Path $root 'core/entry_os_boundary.ps1')
 $script:launchFile='';$script:launchVerb='';$script:launchArgs=''
 function Start-Process {param($FilePath,$Verb,$ArgumentList);$script:launchFile=$FilePath;$script:launchVerb=$Verb;$script:launchArgs=$ArgumentList}
 $literal="fixture ' 中文"
 Start-SetupEntryElevated -Command $literal
 $parts=@($script:launchArgs -split ' ');$index=[Array]::IndexOf($parts,'-EncodedCommand')
 $options=@($parts|Where-Object {$_ -ne $parts[$index+1]})
 Assert ($script:launchFile -ceq 'powershell.exe' -and $script:launchVerb -ceq 'RunAs' -and $index -ge 0 -and $options.Count -eq 5 -and $options -contains '-NoProfile' -and $options -contains '-NoExit' -and $options -contains '-ExecutionPolicy' -and $options -contains 'Bypass' -and $options -contains '-EncodedCommand' -and [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($parts[$index+1])) -ceq $literal) 'existing entry launcher preserves same PowerShell options and encoded command data'
}
