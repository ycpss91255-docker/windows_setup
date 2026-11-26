#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name,[string]$Expected){
 if(-not $Expected){throw '每個負例都必須指定產品預期錯誤。'}
 $failure=$null;try{& $Action|Out-Null}catch{$failure=$_}
 Assert ($null -ne $failure -and -not ($failure.Exception -is [Management.Automation.ParameterBindingException])) ($Name+'：確實進入原函式')
 Assert ($failure.Exception.Message.Contains($Expected)) ($Name+'：符合預期錯誤；預期='+$Expected+'；實際='+$failure.Exception.Message)
}
. (Join-Path $root 'modules/accounts/autologon_library.ps1')
Assert ($null -ne (Get-Command Get-SetupAutologonRestoreVerification -ErrorAction SilentlyContinue)) '自動登入停用驗收具名函式'
function Reset-Fixture {$script:values=@{AutoAdminLogon='0';DefaultUserName='fixture'};$script:kinds=@{AutoAdminLogon='String';DefaultUserName='String'};$script:secret=$false;$script:lsaError=$null}
function Get-Item {param($LiteralPath,$ErrorAction,[switch]$Force) if($LiteralPath -like 'HKLM:*'){$o=[pscustomobject]@{};$o|Add-Member ScriptMethod GetValueNames {,@($script:values.Keys)};$o|Add-Member ScriptMethod GetValue {param($name) $script:values[$name]};$o|Add-Member ScriptMethod GetValueKind {param($name) $script:kinds[$name]};return $o};Microsoft.PowerShell.Management\Get-Item @PSBoundParameters}
function New-ItemProperty {$script:writes++;throw '驗收不可寫入登錄'}
function Remove-ItemProperty {$script:writes++;throw '驗收不可移除登錄'}
function Invoke-SetupLsaSecret {param($Name,$Action) if($Action -ne 'Query'){$script:writes++;throw '驗收不可刪除LSA機密'};if($script:lsaError){throw $script:lsaError};$script:secret}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('autologon_verify_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$report=Join-Path $dir 'result.json'
function Write-Report($Values){$base=[ordered]@{Success=$true;Mode='Restore';UserSID='test-sid';Computer='test-pc';CheckedAt='2026-01-01T00:00:00'};foreach($k in $Values.Keys){$base[$k]=$Values[$k]};[IO.File]::WriteAllText($report,($base|ConvertTo-Json),(New-Object Text.UTF8Encoding($true)))}
$call=@{ReportPath=$report;UserSid='test-sid';Computer='test-pc'}
try{
 $script:writes=0;Reset-Fixture
 Reject {Get-SetupAutologonRestoreVerification @call} '沒有停用結果不可略過' '沒有自動登入停用結果'
 Write-Report @{}
 $reason=Get-SetupAutologonRestoreVerification @call
 Assert ($reason -is [string] -and $reason.Contains('-Restore') -and $reason.Contains('2026-01-01T00:00:00')) '成功停用且讀回已停用時提供略過原因'
 foreach($bad in @(@{Success=$false},@{Success='True'},@{Mode='Apply'},@{UserSID='other-sid'},@{Computer='other-pc'})){
  Write-Report $bad
  Reject {Get-SetupAutologonRestoreVerification @call} ('非本機本帳號成功停用不可略過 '+($bad|ConvertTo-Json -Compress)) '自動登入停用結果不是'
 }
 Write-Report @{}
 $script:secret=$true
 Reject {Get-SetupAutologonRestoreVerification @call} 'LSA機密仍存在不可略過' '本輪讀回'
 Reset-Fixture;$script:values.AutoAdminLogon='1'
 Reject {Get-SetupAutologonRestoreVerification @call} '自動登入值被改回不可略過' '本輪讀回'
 Reset-Fixture;$script:values.DefaultPassword='plain';$script:kinds.DefaultPassword='String'
 Reject {Get-SetupAutologonRestoreVerification @call} '明文密碼存在不可略過' '本輪讀回'
 Reset-Fixture;$script:lsaError='無法開啟LSA原則（Win32錯誤 5）；請以系統管理員執行。'
 Reject {Get-SetupAutologonRestoreVerification @call} 'LSA無法查詢如實回報' '無法開啟LSA原則'
 Assert ($script:writes -eq 0) '驗收只讀不修改登錄或LSA'
}finally{Microsoft.PowerShell.Management\Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'ALL PASS: Autologon restore verification TEMP/mock only'
