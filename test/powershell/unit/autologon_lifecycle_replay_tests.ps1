#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$scene=Join-Path $root 'test/powershell/fixtures/nuc_scene_autologon'
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/hardware.ps1')
function Read-SceneExcerpt([string]$Name){
 $values=[ordered]@{};$secret=$null
 foreach($line in [IO.File]::ReadAllLines((Join-Path $scene $Name))){
  if($line -match '^(\w+)\tExists=True\tKind=(\w+)\tValue=(.*)$'){$values[$Matches[1]]=[pscustomobject]@{Kind=$Matches[2];Value=$Matches[3]}}
  elseif($line -match '^LsaSecretPresent=(True|False)$'){$secret=[bool]::Parse($Matches[1])}
 }
 if($null -eq $secret){throw 'fixture lacks the captured LSA existence'}
 [pscustomobject]@{Values=$values;Secret=$secret}
}
function Set-Scene($Capture){$global:LifecycleState=[ordered]@{};foreach($n in $Capture.Values.Keys){$global:LifecycleState[$n]=$Capture.Values[$n]};$global:LifecycleSecret=$Capture.Secret}
function Get-Item {param($LiteralPath,$ErrorAction,[switch]$Force) if($LiteralPath -like 'HKLM:*'){$o=[pscustomobject]@{};$o|Add-Member ScriptMethod GetValueNames {,@($global:LifecycleState.Keys)};$o|Add-Member ScriptMethod GetValue {param($n) $global:LifecycleState[$n].Value};$o|Add-Member ScriptMethod GetValueKind {param($n) $global:LifecycleState[$n].Kind};return $o};Microsoft.PowerShell.Management\Get-Item @PSBoundParameters}
function Get-ItemProperty {param($Path,$LiteralPath,$ErrorAction) $o=[ordered]@{};foreach($n in $global:LifecycleState.Keys){$o[$n]=$global:LifecycleState[$n].Value};[pscustomobject]$o}
function New-ItemProperty {param($LiteralPath,$Name,$Value,$PropertyType,[switch]$Force,$ErrorAction) $global:LifecycleState[$Name]=[pscustomobject]@{Kind=$PropertyType;Value=$Value}}
function Remove-ItemProperty {param($LiteralPath,$Name,$ErrorAction) $global:LifecycleState.Remove($Name)}
function Get-LocalUser {param($Name,$ErrorAction) [pscustomobject]@{Name=$Name}}
function Get-AuthenticodeSignature {param($FilePath) [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='O=Microsoft Corporation'}}}
# Autologon itself is replaced by the state the device reached after the user re-enabled it.
function Start-Process {param($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru) Set-Scene $again;[pscustomobject]@{ExitCode=0}}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('autologon_lifecycle_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
# The shipped entry refuses non-administrators; run its own text without that single line.
$entry=Join-Path $dir 'apply_autologon_settings.ps1'
$text=[IO.File]::ReadAllText((Join-Path $root 'modules/accounts/apply_autologon_settings.ps1'))
$elevation='#Requires -RunAs'+'Administrator'
Assert (([regex]::Matches($text,[regex]::Escape($elevation))).Count -eq 1) '套用入口仍要求系統管理員'
[IO.File]::WriteAllText($entry,$text.Replace($elevation,''),(New-Object Text.UTF8Encoding($true)))
# LSA is the only replaced library boundary; it answers with an existence flag and never holds any content.
$shim=Join-Path $dir 'autologon_library.ps1'
$shimText=@'
. '@LIBRARY@'
function Invoke-SetupLsaSecret {param($Name,$Action) $had=$global:LifecycleSecret;if($Action -eq 'Remove'){$global:LifecycleSecret=$false};$had}
'@
[IO.File]::WriteAllText($shim,$shimText.Replace('@LIBRARY@',(Join-Path $root 'modules/accounts/autologon_library.ps1').Replace("'","''")),(New-Object Text.UTF8Encoding($true)))
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
 $again=Read-SceneExcerpt 'stage_after_reenable.excerpt.txt'
 Set-Scene (Read-SceneExcerpt 'stage_before.excerpt.txt')
 & $entry -Restore|Out-Null
 $check=Invoke-SceneVerification
 Assert ($check.Status -eq 'Skipped') ('以 -Restore 停用後總驗收標示略過；實際='+$check.Status)
 & $entry -UserName $env:USERNAME -AutoLogonPassword 'fixture-lifecycle-secret'|Out-Null
 $check=Invoke-SceneVerification
 Assert ($check.Status -eq 'Passed') ('重新啟用後總驗收通過；實際='+$check.Status)
 $report=[IO.File]::ReadAllText((Join-Path $dir 'NUC8-Setup\Autologon-Result.json'))
 Assert (-not $report.Contains('fixture-lifecycle-secret')) '結果檔不含密碼'
 # Same end state as a restore, but reached by another tool after the last apply.
 Set-Scene (Read-SceneExcerpt 'stage_after_restore.excerpt.txt')
 $check=Invoke-SceneVerification
 Assert ($check.Status -eq 'Failed') ('重新啟用後若由其他工具停用，舊的停用結果不可讓總驗收略過；實際='+$check.Status)
 & $entry -Restore|Out-Null
 $check=Invoke-SceneVerification
 Assert ($check.Status -eq 'Skipped') ('再次以 -Restore 停用後恢復略過；實際='+$check.Status)
}finally{
 foreach($n in $saved.Keys){[Environment]::SetEnvironmentVariable($n,$saved[$n])}
 Remove-Variable LifecycleState,LifecycleSecret -Scope Global -ErrorAction SilentlyContinue
 Microsoft.PowerShell.Management\Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'ALL PASS: Autologon restore, re-enable and later disable replay; no host registry or LSA access'
