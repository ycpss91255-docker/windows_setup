#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name,[string]$Expected){
 $failure=$null;try{& $Action|Out-Null}catch{$failure=$_}
 Assert ($null -ne $failure -and -not ($failure.Exception -is [Management.Automation.ParameterBindingException])) ($Name+'：確實進入原函式')
 Assert ($failure.Exception.Message.Contains($Expected)) ($Name+'：符合預期錯誤；預期='+$Expected+'；實際='+$failure.Exception.Message)
}
$lib=Join-Path $root 'modules/power/power_library.ps1'
Assert (Test-Path $lib) '電源模組有無副作用具名函式來源'
. $lib
$realDrive=$env:SystemDrive
# 以暫存目錄代替系統磁碟，休眠檔用真實檔案；不讀寫實際的 hiberfil.sys。
$script:drive=Join-Path ([IO.Path]::GetTempPath()) ('power_drive_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($script:drive)
trap{$env:SystemDrive=$realDrive;[IO.Directory]::Delete($script:drive,$true);break}
$env:SystemDrive=$script:drive
$script:hiberFile=Join-Path ($env:SystemDrive+'\') 'hiberfil.sys'
function Reset-PowerFixture {
 $script:values=@{HibernateEnabledDefault=1};$script:kinds=@{HibernateEnabledDefault='DWord'}
 [IO.File]::WriteAllText($script:hiberFile,'fixture');$script:calls=@();$script:exit=0;$script:drop=$false;$script:keepFile=$false
}
function Get-Item {param($LiteralPath,$ErrorAction,[switch]$Force) if($LiteralPath -ne 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'){throw ('不應讀取其他機碼：'+$LiteralPath)};$o=[pscustomobject]@{};$o|Add-Member ScriptMethod GetValueNames {,@($script:values.Keys)};$o|Add-Member ScriptMethod GetValue {param($name) $script:values[$name]};$o|Add-Member ScriptMethod GetValueKind {param($name) if(-not $script:values.ContainsKey($name)){throw 'missing'};$script:kinds[$name]};return $o}
# Windows PowerShell 5.1 的 Test-Path／Get-Item 對系統鎖定的 hiberfil.sys 一律回報不存在，假命令照實重現。
function Test-Path {param($LiteralPath,$PathType) if($LiteralPath -ne $script:hiberFile){throw ('不應檢查其他檔案：'+$LiteralPath)};$false}
function powercfg.exe {
 $script:calls+=@($args -join ' ')
 if($script:exit -eq 0 -and -not $script:drop){$script:values.HibernateEnabled=0;$script:kinds.HibernateEnabled='DWord';if(-not $script:keepFile){[IO.File]::Delete($script:hiberFile)}}
 $global:LASTEXITCODE=$script:exit
}
Reset-PowerFixture
Assert ((Read-SetupHibernateState).HiberFilePresent -eq $true) 'Test-Path 看不到系統鎖定的休眠檔時仍須偵測到檔案存在'
$state=Disable-SetupHibernate
Assert ($script:calls.Count -eq 1 -and $script:calls[0] -ceq '/hibernate off') '只呼叫一次 powercfg /hibernate off'
Assert ($state.HibernateEnabled -eq 0 -and -not $state.HiberFilePresent) '讀回休眠停用且休眠檔已移除'
Reset-PowerFixture;$script:values.HibernateEnabled=1;$script:kinds.HibernateEnabled='DWord'
$state=Disable-SetupHibernate
Assert ($state.HibernateEnabled -eq 0) '既有 HibernateEnabled 為 1 時改為停用'
Reset-PowerFixture;$script:exit=1
Reject {Disable-SetupHibernate} 'powercfg 失敗如實回報' '停用休眠失敗'
Reset-PowerFixture;$script:drop=$true
Reject {Disable-SetupHibernate} '設定被覆寫時讀回失敗' '休眠讀回仍未停用'
Reset-PowerFixture;$script:keepFile=$true
Reject {Disable-SetupHibernate} '休眠檔仍存在時讀回失敗' '休眠讀回仍未停用'
Reset-PowerFixture;$script:drop=$true;$script:values.HibernateEnabled='0';$script:kinds.HibernateEnabled='String';[IO.File]::Delete($script:hiberFile)
Reject {Disable-SetupHibernate} '錯誤登錄型別不視為停用' '休眠讀回仍未停用'
Reset-PowerFixture;$script:drop=$true;$script:values.HibernateEnabledDefault=0;[IO.File]::Delete($script:hiberFile)
$state=Disable-SetupHibernate
Assert ($state.HibernateEnabled -eq 0) '沒有 HibernateEnabled 時採用系統預設值'
$dir=Join-Path ([IO.Path]::GetTempPath()) ('power_test_'+[guid]::NewGuid().ToString('N'))
$call=@{ReportPath=(Join-Path $dir 'nested/result.json');UserSid='test-sid';Computer='test-pc'}
try{
 Reset-PowerFixture
 Reject {Invoke-SetupHibernateResult @call -VerifyOnly -VerificationRunId run0} '休眠仍啟用時只讀驗證失敗' '休眠尚未停用'
 $r=Get-Content -LiteralPath $call.ReportPath -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($script:calls.Count -eq 0 -and $r.Success -eq $false -and $r.Mode -eq 'VerifyOnly' -and $r.VerificationRunId -eq 'run0' -and $r.Error.Contains('休眠尚未停用')) '只讀驗證不呼叫 powercfg 且如實記錄失敗'
 $r=Invoke-SetupHibernateResult @call
 Assert ($script:calls.Count -eq 1 -and $r.Success -and $r.Mode -eq 'Apply' -and $r.HibernateEnabled -eq 0 -and -not $r.HiberFilePresent) '套用模式停用休眠並回傳讀回結果'
 $r=Invoke-SetupHibernateResult @call -VerifyOnly -VerificationRunId run1
 $saved=Get-Content -LiteralPath $call.ReportPath -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($script:calls.Count -eq 1 -and $saved.Success -and $saved.VerificationRunId -eq 'run1' -and $saved.UserSID -eq 'test-sid' -and $saved.Computer -eq 'test-pc') '只讀驗證含本輪身分且不寫入設定'
 $bytes=[IO.File]::ReadAllBytes($call.ReportPath)
 Assert ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) '結果檔使用 UTF-8 BOM'
 Reset-PowerFixture;$script:exit=2
 Reject {Invoke-SetupHibernateResult @call} '套用失敗如實回報' '停用休眠失敗'
 $saved=Get-Content -LiteralPath $call.ReportPath -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($saved.Success -eq $false -and $saved.Mode -eq 'Apply' -and $saved.Error.Contains('退出碼：2')) '套用失敗仍寫入失敗結果'
}finally{if(Microsoft.PowerShell.Management\Test-Path -LiteralPath $dir -PathType Container){Microsoft.PowerShell.Management\Remove-Item -LiteralPath $dir -Recurse -Force}}
$env:SystemDrive=$realDrive;[IO.Directory]::Delete($script:drive,$true)
Write-Host 'ALL PASS: power hibernation helpers without host writes'
