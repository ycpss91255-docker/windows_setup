#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
$fixture=Join-Path $env:TEMP ('windows_setup_power_record_'+[guid]::NewGuid().ToString('N'))
$kit=Join-Path $fixture 'kit\modules\power';$programData=Join-Path $fixture 'ProgramData';$drive=Join-Path $fixture 'drive'
try{
 New-Item -ItemType Directory -Path $kit,$programData,$drive -Force|Out-Null
 # 只移除系統管理員需求；其餘模組檔案原樣複製（含休眠函式庫）。
 Get-ChildItem (Join-Path $root 'modules\power') -File|ForEach-Object{
  $text=[IO.File]::ReadAllText($_.FullName);$text=$text -replace '(?m)^#Requires -RunAsAdministrator\r?\n',''
  [IO.File]::WriteAllText((Join-Path $kit $_.Name),$text,(New-Object Text.UTF8Encoding($true)))}
 # 以假的 powercfg 與假的電源登錄機碼取代系統狀態，SystemDrive 指向暫存目錄；只驗證紀錄檔寫入位置。
 $runner=Join-Path $fixture 'run.ps1'
 $body=@"
`$env:ProgramData='$programData';`$env:SystemDrive='$drive'
`$global:values=@{HibernateEnabledDefault=1};`$global:kinds=@{HibernateEnabledDefault='DWord'}
function Get-Item {param(`$LiteralPath,`$ErrorAction,[switch]`$Force) if(`$LiteralPath -ne 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'){return Microsoft.PowerShell.Management\Get-Item @PSBoundParameters};`$o=[pscustomobject]@{};`$o|Add-Member ScriptMethod GetValueNames {,@(`$global:values.Keys)};`$o|Add-Member ScriptMethod GetValue {param(`$name) `$global:values[`$name]};`$o|Add-Member ScriptMethod GetValueKind {param(`$name) `$global:kinds[`$name]};return `$o}
function powercfg.exe {
 `$global:LASTEXITCODE=0
 if(`$args[0] -eq '/hibernate' -and `$args[1] -eq 'off'){`$global:values.HibernateEnabled=0;`$global:kinds.HibernateEnabled='DWord';return}
 'fake powercfg output'
}
& '$kit\apply_power_settings.ps1'|Out-Null
"@
 [IO.File]::WriteAllText($runner,$body,(New-Object Text.UTF8Encoding($true)))
 $output=& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $runner 2>&1|Out-String
 $exit=$LASTEXITCODE
 Assert ($exit -eq 0) ('電源模組以假 powercfg 執行成功；退出碼='+$exit+$(if($exit -ne 0){'；輸出：'+$output.Trim()}else{''}))
 $inKit=@(Get-ChildItem $kit -File|Where-Object Name -like 'Power-*.txt')
 Assert ($inKit.Count -eq 0) ('工具包 modules\power 不得寫入每機電源紀錄：'+($inKit.Name -join ', '))
 $record=Join-Path $programData 'NUC8-Setup'
 Assert (@(Get-ChildItem $record -Filter 'Power-Before-*.txt' -File -ErrorAction SilentlyContinue).Count -eq 1) 'Power-Before 寫到 ProgramData\NUC8-Setup'
 Assert (Test-Path (Join-Path $record 'Power-After.txt') -PathType Leaf) 'Power-After 寫到 ProgramData\NUC8-Setup'
}finally{if(Test-Path $fixture){Remove-Item $fixture -Recurse -Force}}
Write-Host "Power record location tests passed: $count"
