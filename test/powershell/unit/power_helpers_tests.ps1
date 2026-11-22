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
$script:hiberFile=Join-Path ($env:SystemDrive+'\') 'hiberfil.sys'
function Reset-PowerFixture {
 $script:values=@{HibernateEnabledDefault=1};$script:kinds=@{HibernateEnabledDefault='DWord'}
 $script:filePresent=$true;$script:calls=@();$script:exit=0;$script:drop=$false;$script:keepFile=$false
}
function Get-Item {param($LiteralPath,$ErrorAction,[switch]$Force) if($LiteralPath -ne 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'){throw ('不應讀取其他機碼：'+$LiteralPath)};$o=[pscustomobject]@{};$o|Add-Member ScriptMethod GetValueNames {,@($script:values.Keys)};$o|Add-Member ScriptMethod GetValue {param($name) $script:values[$name]};$o|Add-Member ScriptMethod GetValueKind {param($name) if(-not $script:values.ContainsKey($name)){throw 'missing'};$script:kinds[$name]};return $o}
function Test-Path {param($LiteralPath,$PathType) if($LiteralPath -ne $script:hiberFile){throw ('不應檢查其他檔案：'+$LiteralPath)};$script:filePresent}
function powercfg.exe {
 $script:calls+=@($args -join ' ')
 if($script:exit -eq 0 -and -not $script:drop){$script:values.HibernateEnabled=0;$script:kinds.HibernateEnabled='DWord';if(-not $script:keepFile){$script:filePresent=$false}}
 $global:LASTEXITCODE=$script:exit
}
Reset-PowerFixture
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
Reset-PowerFixture;$script:drop=$true;$script:values.HibernateEnabled='0';$script:kinds.HibernateEnabled='String';$script:filePresent=$false
Reject {Disable-SetupHibernate} '錯誤登錄型別不視為停用' '休眠讀回仍未停用'
Reset-PowerFixture;$script:drop=$true;$script:values.HibernateEnabledDefault=0;$script:filePresent=$false
$state=Disable-SetupHibernate
Assert ($state.HibernateEnabled -eq 0) '沒有 HibernateEnabled 時採用系統預設值'
Write-Host 'ALL PASS: power hibernation helpers without host writes'
