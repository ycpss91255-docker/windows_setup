#Requires -Version 5.1
param([ValidateSet('All','Restore','Verification')][string]$Case='All')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$scene=Join-Path $root 'test/powershell/fixtures/nuc_scene_autologon'
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'test/powershell/helpers/run_module_fixture.ps1')
. (Join-Path $root 'core/hardware.ps1')
$kindNames=@{REG_SZ='String';REG_DWORD='DWord';REG_QWORD='QWord'}
function Read-SceneRegistry([string]$Name){
 $state=[ordered]@{}
 foreach($line in [IO.File]::ReadAllLines((Join-Path $scene $Name))){if($line -match '^ {4}(\S+) {4}(REG_\w+) {4}(.*)$'){$state[$Matches[1]]=[pscustomobject]@{Kind=$kindNames[$Matches[2]];Value=$Matches[3]}}}
 return $state
}
function Read-SceneExcerpt([string]$Name){
 $values=[ordered]@{};$secret=$null
 foreach($line in [IO.File]::ReadAllLines((Join-Path $scene $Name))){
  if($line -match '^DefaultPassword\tExists=True'){throw '現場 fixture 不得含明文密碼值'}
  if($line -match '^(\w+)\tExists=True\tKind=(\w+)\tValue=(.*)$'){$values[$Matches[1]]=[pscustomobject]@{Kind=$Matches[2];Value=$Matches[3]}}
  elseif($line -match '^LsaSecretPresent=(True|False)$'){$secret=[bool]::Parse($Matches[1])}
 }
 if($null -eq $secret){throw 'fixture lacks the captured LSA existence'}
 [pscustomobject]@{Values=$values;Secret=$secret}
}
function Get-Item {param($LiteralPath,$ErrorAction,[switch]$Force) if($LiteralPath -like 'HKLM:*'){$o=[pscustomobject]@{};$o|Add-Member ScriptMethod GetValueNames {,@($global:SceneState.Keys)};$o|Add-Member ScriptMethod GetValue {param($n) $global:SceneState[$n].Value};$o|Add-Member ScriptMethod GetValueKind {param($n) $global:SceneState[$n].Kind};return $o};Microsoft.PowerShell.Management\Get-Item @PSBoundParameters}
function Get-ItemProperty {param($Path,$LiteralPath,$ErrorAction) $o=[ordered]@{};foreach($n in $global:SceneState.Keys){$o[$n]=$global:SceneState[$n].Value};[pscustomobject]$o}
function New-ItemProperty {param($LiteralPath,$Name,$Value,$PropertyType,[switch]$Force,$ErrorAction) $global:SceneState[$Name]=[pscustomobject]@{Kind=$PropertyType;Value=$Value}}
function Remove-ItemProperty {param($LiteralPath,$Name,$ErrorAction) $global:SceneState.Remove($Name)}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('autologon_scene_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$library=Join-Path $root 'modules/accounts/autologon_library.ps1'
# LSA is the only replaced boundary; it answers with the captured existence flag and never holds any content.
$shim=Join-Path $dir 'autologon_library.ps1'
$shimText=@'
. '@LIBRARY@'
function Invoke-SetupLsaSecret {param($Name,$Action) $had=$global:SceneSecret;if($Action -eq 'Remove'){$global:SceneSecret=$false};$had}
'@
[IO.File]::WriteAllText($shim,$shimText.Replace('@LIBRARY@',$library.Replace("'","''")),(New-Object Text.UTF8Encoding($true)))
function Resolve-NucPath {param($Name) if($Name -ne 'autologon_library.ps1'){throw ('unexpected path '+$Name)};$shim}
# Execute the real statements of the aggregate verification that decide this one check.
function Invoke-SceneVerification {
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/verification_library.ps1'),[ref]$tokens,[ref]$errors)
 $function=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-SetupVerification'},$true))
 $statements=@($function[0].Body.EndBlock.Statements);$first=-1;$last=-1
 for($i=0;$i -lt $statements.Count;$i++){if($statements[$i].Extent.Text -match '^\$auto=Get-ItemProperty '){$first=$i};if($statements[$i].Extent.Text -match '^\$driverDecision='){$last=$i}}
 if($first -lt 0 -or $last -le $first){throw 'aggregate autologon statements not found'}
 $checks=New-Object Collections.Generic.List[object]
 function Add-Check([string]$Name,[bool]$Passed,[string]$Detail){$checks.Add([pscustomobject]@{Name=$Name;Status=$(if($Passed){'Passed'}else{'Failed'});Detail=$Detail})}
 for($i=$first;$i -lt $last;$i++){. ([scriptblock]::Create($statements[$i].Extent.Text))}
 if($checks.Count -ne 1 -or $checks[0].Name -ne '自動登入設定'){throw 'unexpected aggregate checks'}
 $checks[0]
}
$saved=@{USERNAME=$env:USERNAME;COMPUTERNAME=$env:COMPUTERNAME;ProgramData=$env:ProgramData}
try{
 $env:USERNAME='fixture_user';$env:COMPUTERNAME='FIXTURE-PC';$env:ProgramData=$dir
 $reportPath=Join-Path $dir 'NUC8-Setup\Autologon-Result.json';[void][IO.Directory]::CreateDirectory((Split-Path $reportPath))
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $before=Read-SceneExcerpt 'stage_before.excerpt.txt'
 $global:SceneState=Read-SceneRegistry 'winlogon_first_scene.reg.txt';$global:SceneSecret=$before.Secret
 Assert ($global:SceneState.Count -gt 30 -and $global:SceneState['AutoAdminLogon'].Kind -eq 'String' -and $global:SceneState['AutoAdminLogon'].Value -ceq '1' -and $before.Secret) '現場資料為已啟用自動登入且存有LSA機密'
 $after=Read-SceneExcerpt 'stage_after_restore.excerpt.txt'
 if($Case -ne 'Verification'){
 $original=[ordered]@{};foreach($n in $global:SceneState.Keys){$original[$n]=$global:SceneState[$n].Kind+'|'+$global:SceneState[$n].Value}
 # Same request as on the device: the dispatcher decides first, then the module acts on the captured state.
 $fixture=New-RunModuleFixture -SourceRoot $root;$rejected=''
 try{Invoke-RunModuleFixture $fixture @{Module='Apply-AutologonSettings';Restore=$true} -Admin $true}catch{$log=[IO.File]::ReadAllText((Join-Path $fixture.Root 'case.log'));$rejected=@($log -split "`r?`n"|Where-Object {$_})[0]}
 if(-not $rejected){. $shim;Invoke-SetupAutologonRestore -ReportPath $reportPath -UserSid $sid|Out-Null}
 Assert ($global:SceneState['AutoAdminLogon'].Value -ceq '0' -and -not $global:SceneSecret) ('現場要求停用後不再自動登入也沒有儲存的密碼；AutoAdminLogon='+$global:SceneState['AutoAdminLogon'].Value+'；LSA機密='+$global:SceneSecret+'；入口='+$rejected)
 $changed=@($original.Keys|Where-Object {$_ -ne 'AutoAdminLogon' -and ($null -eq $global:SceneState[$_] -or ($global:SceneState[$_].Kind+'|'+$global:SceneState[$_].Value) -cne $original[$_])})
 Assert ($changed.Count -eq 0 -and $global:SceneState.Count -eq $original.Count) ('現場其餘Winlogon值（含AutoLogonSID與LastUsedUsername）不變：'+($changed -join ','))
 foreach($n in $after.Values.Keys){Assert ($global:SceneState[$n].Kind -ceq $after.Values[$n].Kind -and $global:SceneState[$n].Value -ceq $after.Values[$n].Value) ('重放結果與實機停用後擷取一致：'+$n)}
 }
 if($Case -ne 'Restore'){
 $captured=[IO.File]::ReadAllText((Join-Path $scene 'stage_after_restore_report.json'))
 # The only rebinding is identity: the de-identified SID becomes the SID of the account running this test.
 $bound=$captured.Replace('S-1-5-21-1000000001-1000000002-1000000003-1001',$sid)
 Assert ($bound -cne $captured) '擷取的結果檔含停用帳號身分'
 [IO.File]::WriteAllText($reportPath,$bound,(New-Object Text.UTF8Encoding($true)))
 $global:SceneState=$after.Values;$global:SceneSecret=$after.Secret
 $check=Invoke-SceneVerification
 Assert ($check.Status -eq 'Skipped') ('實機停用後的現場在總驗收標示略過；實際='+$check.Status+'；'+$check.Detail)
 $again=Read-SceneExcerpt 'stage_after_reenable.excerpt.txt'
 $global:SceneState=$again.Values;$global:SceneSecret=$again.Secret
 $check=Invoke-SceneVerification
 Assert ($check.Status -eq 'Passed') ('實機重新啟用後的現場即使留有舊停用結果仍為通過；實際='+$check.Status)
 }
}finally{
 foreach($n in $saved.Keys){[Environment]::SetEnvironmentVariable($n,$saved[$n])}
 Remove-Variable SceneState,SceneSecret -Scope Global -ErrorAction SilentlyContinue
 Microsoft.PowerShell.Management\Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'ALL PASS: Autologon captured scene replay; no host registry or LSA access'
