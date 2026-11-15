#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $root 'core/after_restart_library.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('afterrestart_acceptance_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture|Out-Null
function Assert([bool]$condition,[string]$message){Write-Host ('@@ASSERT@@'+(@{Name=$message;Passed=$condition}|ConvertTo-Json -Compress));if(-not $condition){throw ('FAIL: '+$message)};Write-Host ('PASS: '+$message)}
function Resolve-NucPath([string]$Name){Join-Path $script:caseDir $Name}
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/after_restart_library.ps1'),[ref]$tokens,[ref]$parseErrors)
$entry=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-SetupAfterRestart'},$true)
$calls=@($entry.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Complete-SetupAfterRestartAcceptance'},$true))
Assert ($parseErrors.Count -eq 0 -and $calls.Count -eq 1) 'AfterRestart entry calls the named acceptance boundary once'
$verifier=@'
param([string]$VerificationRunId)
$check=[pscustomobject]@{Name='開始選單釘選清空';Status='Passed';Passed=$true}
$record=@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Passed=$true;Checks=@($check)}
if($env:ACCEPTANCE_FIXTURE_MODE -eq 'wrong-id'){$record.VerificationRunId='old-run'}
if($env:ACCEPTANCE_FIXTURE_MODE -eq 'wrong-machine'){$record.Computer='other-machine'}
if($env:ACCEPTANCE_FIXTURE_MODE -eq 'wrong-user'){$record.UserSID='other-user'}
if($env:ACCEPTANCE_FIXTURE_MODE -eq 'two-start'){$record.Checks=@($check,$check)}
$record|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot 'Verification-Result.json') -Encoding UTF8
if($env:ACCEPTANCE_FIXTURE_MODE -eq 'throw') {throw 'fixture failure'}
'@
$oldMode=$env:ACCEPTANCE_FIXTURE_MODE
$seenIds=@()
try{
 foreach($mode in @('success','wrong-id','wrong-machine','wrong-user','two-start','throw','prior-error','previous-other')){
  $script:caseDir=Join-Path $fixture $mode;New-Item -ItemType Directory $script:caseDir|Out-Null
  [IO.File]::WriteAllText((Join-Path $script:caseDir 'verify_only.ps1'),$verifier,[Text.UTF8Encoding]::new($true))
  $env:ACCEPTANCE_FIXTURE_MODE=$mode
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $previous=[pscustomobject]@{Computer=$env:COMPUTERNAME;UserSID=$sid;Success=$false;PendingModules=@([pscustomobject]@{Module='apply_start_menu_settings.ps1'})}
  if($mode -eq 'previous-other'){$previous.Computer='other-machine'}
  $errors=@();if($mode -eq 'prior-error'){$errors=@('fixture prior failure')}
  $resultPath=Join-Path $script:caseDir 'Setup-Result.json';$threw=$false
  try{Complete-SetupAfterRestartAcceptance -Hardware ([pscustomobject]@{Name='Fixture'}) -Errors $errors -Previous $previous -ResultPath $resultPath -Sid $sid}catch{$threw=$true}
  $report=Get-Content (Join-Path $script:caseDir 'Acceptance-Result.json') -Raw|ConvertFrom-Json
  if($mode -notin @('wrong-id','wrong-machine','wrong-user')){
   $current=(Get-Content (Join-Path $script:caseDir 'Verification-Result.json') -Raw|ConvertFrom-Json).VerificationRunId
   $parsed=[guid]::Empty
   Assert ([guid]::TryParse($current,[ref]$parsed) -and $current -notin $seenIds) ('fresh unique run ID is supplied: '+$mode)
   $seenIds+=@($current)
  }
  $expected=$mode -in @('success','two-start','previous-other')
  Assert (($report.Success -eq $expected) -and ($threw -ne $expected)) ('report and throw retain acceptance outcome: '+$mode)
  if($mode -eq 'previous-other'){Assert (-not (Test-Path $resultPath)) 'different previous owner is not updated'}
  elseif($mode -eq 'success'){Assert (@($previous.PendingModules).Count -eq 0 -and $previous.Success) 'single passed Start check clears matching pending module'}
  elseif($mode -eq 'two-start'){Assert (@($previous.PendingModules).Count -eq 1) 'duplicate passed Start checks retain pending module'}
  if($mode -in @('wrong-id','wrong-machine','wrong-user')){Assert (@($report.Errors|Where-Object {$_ -match '驗證結果'}).Count -eq 1) ('identity mismatch is rejected: '+$mode)}
 }
}finally{$env:ACCEPTANCE_FIXTURE_MODE=$oldMode}
Write-Host 'ALL PASS: AfterRestart acceptance boundary fixtures'
