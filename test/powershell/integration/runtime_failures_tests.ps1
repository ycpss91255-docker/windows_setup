#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('windows_runtime_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture|Out-Null
. (Join-Path $root 'core/verification.ps1')
# Exercise the real orchestration body with filesystem-only module doubles.
# Privilege/preflight are excluded; no production system-setting module is loaded.
$body=". '"+(Join-Path $root 'core/configuration_library.ps1').Replace("'","''")+"'`nInvoke-SetupConfiguration -Hardware `$hardware -UserName `$UserName -AutoLogonPassword `$AutoLogonPassword"
$prefix=@'
$ErrorActionPreference='Stop'
$caseRoot=$PSScriptRoot
$UserName=$env:USERNAME;$AutoLogonPassword='fixture';$hardware=[pscustomobject]@{Name='Fixture'};$skippedModules=@()
function Resolve-NucPath([string]$Name){
 $path=Join-Path $caseRoot $Name
 if($Name.EndsWith('.ps1') -and -not(Microsoft.PowerShell.Management\Test-Path -LiteralPath $path)){
  $code="Add-Content -LiteralPath '"+(Join-Path $caseRoot 'executed.txt').Replace("'","''")+"' -Value '"+$Name+"'"
  if($env:CASE_MODE -eq 'module-fail' -and $Name -eq 'apply_power_settings.ps1'){$code+="`nthrow 'fixture module failure'"}
  [IO.File]::WriteAllText($path,$code,[Text.UTF8Encoding]::new($true))
 }
 return $path
}
function Start-Transcript {param($Path) }
function Stop-Transcript {Set-Content (Join-Path $caseRoot 'finally.txt') 'done'}
function Get-ItemProperty { [pscustomobject]@{DefaultUserName=$env:USERNAME;AutoAdminLogon='1'} }
function Get-SetupModuleDecision { [pscustomobject]@{Applicable=$true} }
function Get-PnpDevice {if($env:CASE_MODE -eq 'device-fail'){[pscustomobject]@{Status='ERROR'}}}
function Test-Path {param($Path);if([string]$Path -like 'HKLM:*'){return $false};Microsoft.PowerShell.Management\Test-Path -LiteralPath $Path}
'@
foreach($mode in @('success','module-fail','device-fail')){
 $dir=Join-Path $fixture $mode;New-Item -ItemType Directory $dir|Out-Null
 foreach($helper in @('start_pins_policy_library.ps1','start_pins_asset_library.ps1')){Copy-Item -LiteralPath (Join-Path $root ('modules/start_menu/'+$helper)) -Destination (Join-Path $dir $helper)}
 [IO.File]::WriteAllText((Join-Path $dir 'apply_start_menu_settings.ps1'),'param([switch]$NonInteractive);[pscustomobject]@{Success=$true;Status=''Confirmed'';PinCount=0}')
 Assert (Test-Path (Join-Path $dir 'start_pins_policy_library.ps1')) 'controller fixture includes actual Start completion helper'
 $runner=Join-Path $dir 'run.ps1';[IO.File]::WriteAllText($runner,$prefix+"`n"+$body,[Text.UTF8Encoding]::new($true))
 $oldMode=$env:CASE_MODE;$env:CASE_MODE=$mode;$oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner *> (Join-Path $dir 'output.txt');$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference;$env:CASE_MODE=$oldMode}
 $report=Get-Content (Join-Path $dir 'Setup-Result.json') -Raw|ConvertFrom-Json
 $progress=Get-Content (Join-Path $dir 'Setup-Progress.json') -Raw|ConvertFrom-Json
 Assert (($code -eq 0) -eq ($mode -eq 'success')) ('Configure child exit reflects '+$mode)
 Assert ($report.Success -eq ($mode -eq 'success') -and $progress.HasErrors -eq ($mode -ne 'success')) ('Configure persisted result and progress reflect '+$mode)
 Assert (Test-Path (Join-Path $dir 'finally.txt')) ('Configure finally runs after '+$mode)
 if($mode -eq 'module-fail'){
  Assert ($report.FailedModules -contains 'apply_power_settings.ps1') 'failed module remains available for retry'
  Assert ((Get-Content (Join-Path $dir 'executed.txt')) -contains 'desktop_icon_layout.ps1') 'later stages execute before aggregate failure'
 }
}
# Load the original file using its explicit no-package/PackageOnly early return.
# Any accidental installation path fails before native commands or system queries.
function Start-Process {throw 'fixture forbids installer processes'}
function pnputil.exe {throw 'fixture forbids pnputil'}
function Add-WindowsDriver {throw 'fixture forbids driver installation'}
function Get-CimInstance {throw 'fixture forbids device queries during safe loading'}
function Get-PnpDevice {throw 'fixture forbids driver device queries during safe loading'}
$previousSystemRoot=$env:SystemRoot
try{
 $env:SystemRoot=Join-Path $fixture 'blocked_native_root'
 $loaded=@(. (Join-Path $root 'modules/drivers/install_drivers.ps1') -PackageOnly -DriverPackagePath '')
 Assert ($loaded.Count -eq 1 -and $loaded[0].Status -eq 'Skipped') 'real driver source takes no-package PackageOnly return without installer commands'
}finally{
 $env:SystemRoot=$previousSystemRoot
 foreach($name in @('Start-Process','pnputil.exe','Add-WindowsDriver','Get-CimInstance','Get-PnpDevice')){Remove-Item -LiteralPath ('Function:\'+$name)}
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$cache=Join-Path $fixture 'cache';$archive=Join-Path $fixture 'same.zip'
$one=Join-Path $fixture 'one';$two=Join-Path $fixture 'two';New-Item -ItemType Directory $one,$two|Out-Null
[IO.File]::WriteAllText((Join-Path $one 'obsolete.inf'),'old');[IO.File]::WriteAllText((Join-Path $two 'current.inf'),'new')
[IO.Compression.ZipFile]::CreateFromDirectory($one,$archive);$hash1=(Get-FileHash $archive).Hash
$dest1=Expand-CachedDriverArchive -Archive $archive -CacheRoot $cache -SHA256 $hash1
$archive2=Join-Path $fixture 'new.zip';[IO.Compression.ZipFile]::CreateFromDirectory($two,$archive2);Copy-Item $archive2 $archive -Force
$dest2=Expand-CachedDriverArchive -Archive $archive -CacheRoot $cache -SHA256 (Get-FileHash $archive).Hash
Assert ($dest1 -ne $dest2) 'same archive name with new hash selects an independent cache'
Assert ((Test-Path (Join-Path $dest1 'obsolete.inf')) -and -not(Test-Path (Join-Path $dest2 'obsolete.inf')) -and (Test-Path (Join-Path $dest2 'current.inf'))) 'old INF is retained only in old cache and cannot enter new selection'
$reportPath=Join-Path $fixture 'verification.json';$verifyScript=Join-Path $fixture 'verify.ps1'
$writer=@'
param([string]$VerificationRunId)
$record=@{Success=$true;VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
if($env:CASE_MODE -eq 'throw'){throw 'fixture verification failed'}
if($env:CASE_MODE -eq 'stale'){return}
if($env:CASE_MODE -eq 'wrong-machine'){$record.Computer='different-machine'}
if($env:CASE_MODE -eq 'wrong-user'){$record.UserSID='different-user'}
$record|ConvertTo-Json|Set-Content -LiteralPath $env:CASE_REPORT -Encoding UTF8
'@
[IO.File]::WriteAllText($verifyScript,$writer,[Text.UTF8Encoding]::new($true))
$oldMode=$env:CASE_MODE;$oldReport=$env:CASE_REPORT;$env:CASE_REPORT=$reportPath
try{
 foreach($mode in @('success','throw','stale','wrong-machine','wrong-user')){
  $env:CASE_MODE=$mode;$accepted=$false
  try{$result=Invoke-FreshVerification -ScriptPath $verifyScript -ReportPath $reportPath;$accepted=[bool]$result.Success}catch{}
  Assert ($accepted -eq ($mode -eq 'success')) ('fresh verification rejects obsolete/failing/wrong-owner result: '+$mode)
 }
}finally{$env:CASE_MODE=$oldMode;$env:CASE_REPORT=$oldReport}
foreach($case in @(@{Selected=0;Updates=@();Expected=$true},@{Selected=1;Updates=@();Expected=$false},@{Selected=2;Updates=@(@{ResultCode=2});Expected=$false},@{Selected=2;Updates=@(@{ResultCode=2},@{ResultCode=3});Expected=$false},@{Selected=1;Updates=@(@{ResultCode=2});Expected=$true},@{Selected=-1;Updates=@();Expected=$false},@{Selected='0';Updates=@();Expected=$false})){
 $r=[pscustomobject]@{Selected=$case.Selected;Updates=$case.Updates}
 Assert ((Test-WindowsUpdateResult $r) -eq $case.Expected) ('update completeness selected='+$case.Selected+' count='+@($case.Updates).Count+' expected='+$case.Expected)
}
# The GUI library is definitions-only; replace the controller before calling the narrow dispatch boundary.
. (Join-Path $root 'core/gui_stage_library.ps1')
function Invoke-SetupGuiRole {param($PackageRoot,$Role,[switch]$Worker,[switch]$VerifyOnly,$VerificationRunId,$IconMode);$script:guiCallCount++;$script:capturedGuiCall=[pscustomobject]@{Root=$PackageRoot;Role=$Role;Worker=[bool]$Worker;VerifyOnly=[bool]$VerifyOnly;RunId=$VerificationRunId;IconMode=$IconMode;Parameters=@($PSBoundParameters.Keys)};if($VerificationRunId -eq 'invalid-id'){throw 'fixture controller rejected run ID'};[pscustomobject]@{Fixture='result'}}
function Start-Process {throw 'fixture forbids process launch'}
function Get-CimInstance {throw 'fixture forbids CIM'}
function Invoke-CimMethod {throw 'fixture forbids CIM'}
function Get-ItemProperty {throw 'fixture forbids registry reads'}
function Get-ScheduledTask {throw 'fixture forbids scheduling'}
function New-ScheduledTaskAction {throw 'fixture forbids scheduling'}
function New-ScheduledTaskPrincipal {throw 'fixture forbids scheduling'}
function Unregister-ScheduledTask {throw 'fixture forbids scheduling'}
function reg.exe {throw 'fixture forbids registry process'}
function schtasks.exe {throw 'fixture forbids scheduling process'}
function Register-ScheduledTask {throw 'fixture forbids scheduling'}
function Start-ScheduledTask {throw 'fixture forbids scheduling'}
function Set-ItemProperty {throw 'fixture forbids registry writes'}
function New-ItemProperty {throw 'fixture forbids registry writes'}
function Remove-ItemProperty {throw 'fixture forbids registry writes'}
function Add-Type {throw 'fixture forbids native loading'}
$tokens=$null;$parseErrors=$null
$libraryAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/gui_stage_library.ps1'),[ref]$tokens,[ref]$parseErrors)
$dispatchAst=$libraryAst.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-SetupGuiPublicDispatch'},$true)
$dispatchCommands=@($dispatchAst.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true))
$dispatchMethods=@($dispatchAst.FindAll({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst]},$true))
Assert ($parseErrors.Count -eq 0 -and $dispatchCommands.Count -eq 2 -and @($dispatchCommands|Where-Object {$_.GetCommandName() -ne 'Invoke-SetupGuiRole'}).Count -eq 0 -and $dispatchMethods.Count -eq 0) 'dispatch boundary contains only fixed controller calls and no member invocation'
foreach($role in @('Display','Theme','Icons')){
 $relative=if($role -eq 'Icons'){'modules/desktop/desktop_icon_layout.ps1'}else{'modules/'+$role.ToLowerInvariant()+'/apply_'+$role.ToLowerInvariant()+'_settings.ps1'}
 $tokens=$null;$parseErrors=$null;$entryAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative),[ref]$tokens,[ref]$parseErrors)
 $calls=@($entryAst.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-SetupGuiPublicDispatch'},$true))
 Assert ($parseErrors.Count -eq 0 -and $calls.Count -eq 1) ('public GUI entry wires one named dispatch: '+$relative)
 $parameters=@($calls[0].CommandElements|Where-Object {$_ -is [Management.Automation.Language.CommandParameterAst]}|ForEach-Object ParameterName)
 $expected=@('PackageRoot','Role','Worker','VerifyOnly','VerificationRunId');if($role -eq 'Icons'){$expected+=@('IconMode')}
 Assert ((@($parameters|Sort-Object) -join '|') -ceq (@($expected|Sort-Object) -join '|')) ('public GUI entry retains finite dispatch parameters: '+$relative)
 $elements=$calls[0].CommandElements
 $bound=@{}
 for($index=1;$index -lt $elements.Count;$index++){
  $item=$elements[$index]
  if($item -isnot [Management.Automation.Language.CommandParameterAst]){continue}
  if($item.Argument){$bound[$item.ParameterName]=$item.Argument}else{$index++;$bound[$item.ParameterName]=$elements[$index]}
 }
 $rootExpression=$bound.PackageRoot
 $invoke=if($rootExpression -is [Management.Automation.Language.ParenExpressionAst] -and $rootExpression.Pipeline.PipelineElements.Count -eq 1){$rootExpression.Pipeline.PipelineElements[0].Expression}
 $joined=if($invoke -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $invoke.Arguments.Count -eq 1 -and $invoke.Arguments[0] -is [Management.Automation.Language.ParenExpressionAst] -and $invoke.Arguments[0].Pipeline.PipelineElements.Count -eq 1){$invoke.Arguments[0].Pipeline.PipelineElements[0]}
 $rootValid=$invoke -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $invoke.Static -and $invoke.Expression -is [Management.Automation.Language.TypeExpressionAst] -and $invoke.Expression.TypeName.FullName -ieq 'IO.Path' -and $invoke.Member.Value -ieq 'GetFullPath' -and $joined -is [Management.Automation.Language.CommandAst] -and $joined.GetCommandName() -ieq 'Join-Path' -and $joined.CommandElements.Count -eq 3 -and $joined.CommandElements[1] -is [Management.Automation.Language.VariableExpressionAst] -and $joined.CommandElements[1].VariablePath.UserPath -ieq 'PSScriptRoot' -and $joined.CommandElements[2] -is [Management.Automation.Language.StringConstantExpressionAst] -and $joined.CommandElements[2].Value -ceq '../..'
 Assert $rootValid ('public GUI entry resolves the exact portable package root: '+$relative)
 Assert ($bound.Role -is [Management.Automation.Language.StringConstantExpressionAst] -and $bound.Role.Value -ceq $role -and $bound.Worker -is [Management.Automation.Language.VariableExpressionAst] -and $bound.Worker.VariablePath.UserPath -ieq 'Worker' -and $bound.VerificationRunId -is [Management.Automation.Language.VariableExpressionAst] -and $bound.VerificationRunId.VariablePath.UserPath -ieq 'VerificationRunId') ('public GUI entry binds role worker and run ID exactly: '+$relative)
 if($role -eq 'Icons'){
  $verify=if($bound.VerifyOnly -is [Management.Automation.Language.ParenExpressionAst] -and $bound.VerifyOnly.Pipeline.PipelineElements.Count -eq 1){$bound.VerifyOnly.Pipeline.PipelineElements[0].Expression}
  Assert ($bound.IconMode -is [Management.Automation.Language.VariableExpressionAst] -and $bound.IconMode.VariablePath.UserPath -ieq 'Mode' -and $verify -is [Management.Automation.Language.BinaryExpressionAst] -and $verify.Operator -eq [Management.Automation.Language.TokenKind]::Ieq -and $verify.Left -is [Management.Automation.Language.VariableExpressionAst] -and $verify.Left.VariablePath.UserPath -ieq 'Mode' -and $verify.Right -is [Management.Automation.Language.StringConstantExpressionAst] -and $verify.Right.Value -ceq 'Verify') 'Icons entry binds mode and derived VerifyOnly exactly'
 }else{Assert ($bound.VerifyOnly -is [Management.Automation.Language.VariableExpressionAst] -and $bound.VerifyOnly.VariablePath.UserPath -ieq 'VerifyOnly') ('public GUI entry binds VerifyOnly exactly: '+$relative)}
 Assert ($calls[0].Extent.Text -match ('(?i)-Role\s+'+$role+'\b') -and $calls[0].Extent.Text -match '(?i)\$PSScriptRoot' -and $calls[0].Extent.Text -match '(?i)\$VerificationRunId') ('public GUI entry retains role root and verification ID: '+$relative)
 Assert ($calls[0].Extent.Text -match '(?i)-Worker:\s*\$Worker' -and $calls[0].Extent.Text -match '(?i)-VerifyOnly:') ('public GUI entry forwards worker and verification mode: '+$relative)
 if($role -eq 'Icons'){Assert ($calls[0].Extent.Text -match '(?i)-IconMode\s+\$Mode' -and $calls[0].Extent.Text -match '(?i)\$Mode\s+-eq\s+''Verify''') 'Icons entry derives verify and forwards mode'}
 else{Assert ($calls[0].Extent.Text -match '(?i)-VerifyOnly:\s*\$VerifyOnly') ('public GUI entry forwards its VerifyOnly switch: '+$relative)}
 foreach($mode in @(@{Worker=$true;Verify=$true},@{Worker=$true;Verify=$false},@{Worker=$false;Verify=$true},@{Worker=$false;Verify=$false})){
  $id=[guid]::NewGuid().ToString();$script:capturedGuiCall=$null;$script:guiCallCount=0
  $args=@{PackageRoot=$root;Role=$role;Worker=$mode.Worker;VerifyOnly=$mode.Verify;VerificationRunId=$id}
  if($role -eq 'Icons'){$args.IconMode=if($mode.Verify){'Verify'}else{'Load'}}
  $forwarded=Invoke-SetupGuiPublicDispatch @args
  Assert ($script:guiCallCount -eq 1 -and $forwarded.Fixture -ceq 'result') ('controller result is returned unchanged: '+$relative)
  Assert ($script:capturedGuiCall.Root -ieq $root -and $script:capturedGuiCall.Role -ceq $role -and $script:capturedGuiCall.RunId -ceq $id) ('private GUI role receives portable root and exact ID: '+$relative+' worker='+$mode.Worker+' verify='+$mode.Verify)
  Assert ($script:capturedGuiCall.VerifyOnly -eq $mode.Verify -and $script:capturedGuiCall.Worker -eq $mode.Worker) ('private GUI role preserves Worker and VerifyOnly modes: '+$relative+' worker='+$mode.Worker+' verify='+$mode.Verify)
  if($role -eq 'Icons'){Assert ($script:capturedGuiCall.IconMode -ceq $args.IconMode) ('Icons preserves finite mode: '+$args.IconMode)}
  else{Assert ($script:capturedGuiCall.Parameters -notcontains 'IconMode') ('non-Icons does not receive IconMode: '+$relative)}
  Assert (@($script:capturedGuiCall.Parameters|Where-Object {$_ -in @('UserSID','Computer','SessionId','ScriptPath')}).Count -eq 0) ('controller retains ownership of identity: '+$relative)
 }
}
$script:capturedGuiCall=$null
Invoke-SetupGuiPublicDispatch -PackageRoot $root -Role Icons -IconMode Save|Out-Null
Assert ($script:capturedGuiCall.IconMode -ceq 'Save' -and -not $script:capturedGuiCall.VerifyOnly) 'Icons Save mode reaches the controller unchanged'
$script:capturedGuiCall=$null;$rejected=$false
try{Invoke-SetupGuiPublicDispatch -PackageRoot $root -Role Display -VerificationRunId 'invalid-id'}catch{$rejected=$_.Exception.Message -eq 'fixture controller rejected run ID'}
Assert ($rejected -and $script:capturedGuiCall.RunId -ceq 'invalid-id') 'controller rejects invalid run ID and its failure propagates'
$script:capturedGuiCall=$null;$rejected=$false
try{Invoke-SetupGuiPublicDispatch -PackageRoot $root -Role 'Other' -VerificationRunId ([guid]::NewGuid().ToString())}catch{$rejected=$true}
Assert ($rejected -and $null -eq $script:capturedGuiCall) 'unapproved role cannot reach the controller'
foreach($name in @('Start-Process','Register-ScheduledTask','Start-ScheduledTask','Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','Add-Type','Get-CimInstance','Invoke-CimMethod','Get-ItemProperty','Get-ScheduledTask','New-ScheduledTaskAction','New-ScheduledTaskPrincipal','Unregister-ScheduledTask','reg.exe','schtasks.exe')){Remove-Item -LiteralPath ('Function:\'+$name)}
# Execute the actual Verify-Only finalization and AfterRestart acceptance tail.
$verificationLibrary=Join-Path $root 'core/verification_library.ps1'
foreach($mode in @('fresh-failure','stale-success')){
 $dir=Join-Path $fixture $mode;New-Item -ItemType Directory $dir|Out-Null
 $verifyPrefix=@'
param([string]$VerificationRunId)
$ErrorActionPreference='Stop'
$hardware=[pscustomobject]@{Name='Fixture'}
$checks=New-Object Collections.Generic.List[object]
$checks.Add([pscustomobject]@{Name='fixture-check';Status='Failed';Passed=$false})
function Test-SetupChecksPassed {param($Checks);return $false}
function Resolve-NucPath([string]$Name){if($Name -cne 'Verification-Result.json'){throw 'unexpected report path'};Join-Path $PSScriptRoot $Name}
function Get-ItemProperty {throw 'fixture forbids registry access'}
function Set-ItemProperty {throw 'fixture forbids registry access'}
function Get-CimInstance {throw 'fixture forbids system queries'}
function Get-Service {throw 'fixture forbids service access'}
function Set-Service {throw 'fixture forbids service access'}
function Start-Service {throw 'fixture forbids service access'}
function Get-NetFirewallRule {throw 'fixture forbids firewall access'}
function Set-NetFirewallRule {throw 'fixture forbids firewall access'}
function New-NetFirewallRule {throw 'fixture forbids firewall access'}
function Get-AppxPackage {throw 'fixture forbids Appx access'}
function Get-AppxProvisionedPackage {throw 'fixture forbids Appx access'}
function Start-Process {throw 'fixture forbids process start'}
'@
 $verifier=Join-Path $dir 'verify_only.ps1'
 [IO.File]::WriteAllText($verifier,$verifyPrefix+"`n. '"+$verificationLibrary.Replace("'","''")+"'`nComplete-SetupVerificationResult -Checks `$checks -Hardware `$hardware -VerificationRunId `$VerificationRunId",[Text.UTF8Encoding]::new($true))
 if($mode -eq 'stale-success'){
  [IO.File]::WriteAllText($verifier,"param([string]`$VerificationRunId)`nthrow 'fixture could not run'",[Text.UTF8Encoding]::new($true))
  @{Passed=$true;Checks=@();VerificationRunId='old-run';Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}|ConvertTo-Json|Set-Content (Join-Path $dir 'Verification-Result.json') -Encoding UTF8
 }
 $afterPrefix=@'
$ErrorActionPreference='Stop'
$errors=@();$hardware=[pscustomobject]@{Name='Fixture'}
function Resolve-NucPath([string]$Name){Join-Path $PSScriptRoot $Name}
'@
 $library=(Join-Path $root 'core/after_restart_library.ps1').Replace("'","''")
 $runner=Join-Path $dir 'acceptance.ps1';[IO.File]::WriteAllText($runner,$afterPrefix+"`n. '"+$library+"'`nComplete-SetupAfterRestartAcceptance -Hardware `$hardware -Errors `$errors -Previous `$null -ResultPath `$null -Sid `$null",[Text.UTF8Encoding]::new($true))
 $oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner *> (Join-Path $dir 'output.txt');$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
 $accepted=Get-Content (Join-Path $dir 'Acceptance-Result.json') -Raw|ConvertFrom-Json
 Assert ($code -ne 0 -and -not $accepted.Success) ('acceptance persists failed result then returns nonzero: '+$mode)
 if($mode -eq 'fresh-failure'){Assert (@($accepted.FailedChecks).Count -eq 1) 'Verify-Only exception does not discard current failed checks'}
 else{Assert (@($accepted.Errors|Where-Object {$_ -match '本輪'}).Count -gt 0) 'stale successful verification cannot bypass acceptance'}
}
Write-Host ('ALL PASS: '+$count+' runtime regression assertions; temporary files only, no host configuration or driver installation.')
