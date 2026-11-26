#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Capture([scriptblock]$Action){$failure=$null;$value=$null;try{$value=& $Action}catch{$failure=$_};[pscustomobject]@{Value=$value;Failure=$failure}}
$lib=Join-Path $root 'modules/accounts/autologon_library.ps1'
Assert (Test-Path $lib) '自動登入有無副作用具名函式來源'
. $lib
$empty=Capture {Invoke-SetupLsaSecret -Name '' -Action Query}
Assert ($null -ne $empty.Failure -and $empty.Failure.Exception.Message.Contains('LSA機密名稱')) '拒絕空白機密名稱'
# A random name that never exists: querying and deleting it cannot change any real secret.
$name='WindowsSetupTest_'+[guid]::NewGuid().ToString('N')
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$test=Capture {Invoke-SetupLsaSecret -Name $name -Action Query}
$remove=Capture {Invoke-SetupLsaSecret -Name $name -Action Remove}
if($admin){
 Assert ($null -eq $test.Failure -and $test.Value -is [bool] -and -not $test.Value) '管理員查詢不存在的機密回報不存在'
 Assert ($null -eq $remove.Failure -and $remove.Value -is [bool] -and -not $remove.Value) '管理員刪除不存在的機密回報原本不存在'
}else{
 Assert ($null -ne $test.Failure -and $test.Failure.Exception.Message.Contains('無法開啟LSA原則')) '非管理員查詢如實回報無法開啟LSA'
 Assert ($null -ne $remove.Failure -and $remove.Failure.Exception.Message.Contains('無法開啟LSA原則')) '非管理員刪除如實回報無法開啟LSA'
}
Write-Host ('ALL PASS: Autologon LSA wrapper with random absent secret only; Administrator='+$admin)
