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
Assert ($null -ne (Get-Command Invoke-SetupAutologonRestore -ErrorAction SilentlyContinue)) '自動登入停用具名函式'
function Reset-Fixture {
 $script:values=@{AutoAdminLogon='1';DefaultUserName='fixture';DefaultDomainName='FIXTURE-PC';DefaultPassword='plain-fixture-secret'}
 $script:kinds=@{AutoAdminLogon='String';DefaultUserName='String';DefaultDomainName='String';DefaultPassword='String'}
 $script:secret=$true;$script:writes=@();$script:lsaCalls=@();$script:drop=$false;$script:lsaKeep=$false;$script:lsaError=$null
}
function Get-Item {param($LiteralPath,$ErrorAction,[switch]$Force) if($LiteralPath -like 'HKLM:*'){if($LiteralPath -ne 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'){throw '禁止讀取其他登錄機碼'};$o=[pscustomobject]@{};$o|Add-Member ScriptMethod GetValueNames {,@($script:values.Keys)};$o|Add-Member ScriptMethod GetValue {param($name) $script:values[$name]};$o|Add-Member ScriptMethod GetValueKind {param($name) if(-not $script:values.ContainsKey($name)){throw 'missing'};$script:kinds[$name]};return $o};Microsoft.PowerShell.Management\Get-Item @PSBoundParameters}
function New-ItemProperty {param($LiteralPath,$Name,$Value,$PropertyType,[switch]$Force,$ErrorAction) if($Name -ne 'AutoAdminLogon'){throw '禁止修改其他Winlogon值'};$script:writes+=@($Name+'='+$Value);if(-not $script:drop){$script:values[$Name]=$Value;$script:kinds[$Name]=$PropertyType}}
function Remove-ItemProperty {param($LiteralPath,$Name,$ErrorAction) if($Name -ne 'DefaultPassword'){throw '禁止移除其他Winlogon值'};$script:writes+=@('remove '+$Name);$script:values.Remove($Name);$script:kinds.Remove($Name)}
function Invoke-SetupLsaSecret {param($Name,$Action) if($Name -cne 'DefaultPassword'){throw '禁止操作其他LSA機密'};$script:lsaCalls+=@($Action);if($script:lsaError){throw $script:lsaError};if($Action -eq 'Query'){return $script:secret};$had=$script:secret;if(-not $script:lsaKeep){$script:secret=$false};return $had}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('autologon_test_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$call=@{ReportPath=(Join-Path $dir 'result.json');UserSid='test-sid';Computer='test-pc'}
try{
 Reset-Fixture
 $result=Invoke-SetupAutologonRestore @call
 Assert ($script:values.AutoAdminLogon -ceq '0' -and $script:kinds.AutoAdminLogon -eq 'String') 'AutoAdminLogon改為字串0'
 Assert (-not $script:values.ContainsKey('DefaultPassword')) '移除明文DefaultPassword'
 Assert (-not $script:secret -and ($script:lsaCalls -contains 'Remove')) '清除LSA DefaultPassword機密'
 Assert ($script:values.DefaultUserName -ceq 'fixture' -and $script:values.DefaultDomainName -ceq 'FIXTURE-PC') '保留DefaultUserName與DefaultDomainName'
 $text=[IO.File]::ReadAllText($call.ReportPath);$report=$text|ConvertFrom-Json
 Assert ($report.Success -eq $true -and $report.Mode -ceq 'Restore' -and $report.UserSID -ceq 'test-sid' -and $report.Computer -ceq 'test-pc' -and $result.Success) '結果記錄成功、模式、身分與電腦'
 Assert ($report.AutoAdminLogon -ceq '0' -and $report.PlainPasswordPresent -eq $false -and $report.LsaSecretPresent -eq $false) '結果記錄讀回狀態'
 Assert (-not $text.Contains('plain-fixture-secret')) '結果不含密碼內容'
 $writeCount=$script:writes.Count;$script:lsaCalls=@()
 Invoke-SetupAutologonRestore @call|Out-Null
 Assert (($script:lsaCalls -notcontains 'Remove') -and $script:writes.Count -eq $writeCount+1 -and ((Get-Content $call.ReportPath -Raw|ConvertFrom-Json).Success)) '已停用時重跑成功且不重複刪除'
 Reset-Fixture;$script:drop=$true
 Reject {Invoke-SetupAutologonRestore @call} '寫入被覆蓋讀回必失敗' '自動登入停用讀回'
 $report=Get-Content $call.ReportPath -Raw|ConvertFrom-Json
 Assert ($report.Success -eq $false -and $report.AutoAdminLogon -ceq '1' -and $report.Error.Contains('自動登入停用讀回')) '失敗結果如實記錄'
 Reset-Fixture;$script:lsaKeep=$true
 Reject {Invoke-SetupAutologonRestore @call} 'LSA機密仍存在讀回必失敗' '自動登入停用讀回'
 Assert ((Get-Content $call.ReportPath -Raw|ConvertFrom-Json).LsaSecretPresent -eq $true) '失敗結果記錄LSA機密仍存在'
 Reset-Fixture;$script:lsaError='無法開啟LSA原則（Win32錯誤 5）；請以系統管理員執行。'
 Reject {Invoke-SetupAutologonRestore @call} 'LSA無法開啟如實回報' '無法開啟LSA原則'
 $report=Get-Content $call.ReportPath -Raw|ConvertFrom-Json
 Assert ($report.Success -eq $false -and $report.Error.Contains('無法開啟LSA原則')) 'LSA錯誤寫入失敗結果'
 Reset-Fixture;$script:values.Remove('DefaultPassword');$script:kinds.Remove('DefaultPassword')
 Invoke-SetupAutologonRestore @call|Out-Null
 Assert (-not ($script:writes -contains 'remove DefaultPassword') -and -not $script:secret) '沒有明文密碼時只清LSA機密'
 $target=Join-Path $dir 'target';[void][IO.Directory]::CreateDirectory($target);$link=Join-Path $dir 'link';$null=New-Item -ItemType Junction -Path $link -Target $target
 Reset-Fixture
 Reject {Invoke-SetupAutologonRestore -ReportPath (Join-Path $link 'result.json') -UserSid test-sid} '結果路徑拒絕重新解析點' '重新解析點'
 Assert ($script:writes.Count -eq 0 -and $script:lsaCalls.Count -eq 0) '拒絕路徑時不修改登錄或LSA'
}finally{Microsoft.PowerShell.Management\Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'ALL PASS: Autologon restore TEMP/mock only'
