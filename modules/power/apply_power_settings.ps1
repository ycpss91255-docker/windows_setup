#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'power_library.ps1')
$before=Join-Path $PSScriptRoot ('Power-Before-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.txt')
& powercfg.exe /query SCHEME_CURRENT SUB_SLEEP | Out-File $before -Encoding utf8
Write-Host '設定插電時永不自動睡眠；保留原本螢幕關閉時間。' -ForegroundColor Cyan
& powercfg.exe /change standby-timeout-ac 0
if($LASTEXITCODE -ne 0){throw '設定插電睡眠時間失敗。'}
& powercfg.exe /change hibernate-timeout-ac 0
if($LASTEXITCODE -ne 0){throw '設定插電休眠時間失敗。'}
Write-Host '停用休眠並移除休眠檔；快速啟動依賴休眠，會一併停用。' -ForegroundColor Cyan
$hibernate=Disable-SetupHibernate
$after=Join-Path $PSScriptRoot 'Power-After.txt'
& powercfg.exe /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Out-File $after -Encoding utf8
& powercfg.exe /query SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE | Out-File $after -Append -Encoding utf8
Get-Content $after|Out-Host
Write-Host ('休眠已停用：'+$hibernate.Source+'='+$hibernate.HibernateEnabled+'；'+$hibernate.HiberFile+' 已移除。') -ForegroundColor Green
Write-Host '插電時自動睡眠與休眠已設為永不；手動睡眠、關機及重新開機仍可正常使用。' -ForegroundColor Green