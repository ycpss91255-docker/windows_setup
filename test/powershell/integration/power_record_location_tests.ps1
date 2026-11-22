#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
$fixture=Join-Path $env:TEMP ('windows_setup_power_record_'+[guid]::NewGuid().ToString('N'))
$kit=Join-Path $fixture 'kit\modules\power';$programData=Join-Path $fixture 'ProgramData'
try{
 New-Item -ItemType Directory -Path $kit,$programData -Force|Out-Null
 # 以假的 powercfg 取代系統指令，並移除系統管理員需求，只驗證紀錄檔寫入位置。
 $source=[IO.File]::ReadAllText((Join-Path $root 'modules\power\apply_power_settings.ps1'))
 $source=$source -replace '(?m)^#Requires -RunAsAdministrator\r?\n',''
 $script=Join-Path $kit 'apply_power_settings.ps1'
 $stub="function powercfg.exe { `$global:LASTEXITCODE=0; 'fake powercfg output' }`r`n"
 [IO.File]::WriteAllText($script,($stub+$source),(New-Object Text.UTF8Encoding($true)))
 $runner=Join-Path $fixture 'run.ps1'
 [IO.File]::WriteAllText($runner,"`$env:ProgramData='$programData'; & '$script'",(New-Object Text.UTF8Encoding($true)))
 & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $runner|Out-Null
 Assert ($LASTEXITCODE -eq 0) '電源模組以假 powercfg 執行成功'
 $inKit=@(Get-ChildItem $kit -File|Where-Object Name -like 'Power-*.txt')
 Assert ($inKit.Count -eq 0) ('工具包 modules\power 不得寫入每機電源紀錄：'+($inKit.Name -join ', '))
 $record=Join-Path $programData 'NUC8-Setup'
 Assert (@(Get-ChildItem $record -Filter 'Power-Before-*.txt' -File -ErrorAction SilentlyContinue).Count -eq 1) 'Power-Before 寫到 ProgramData\NUC8-Setup'
 Assert (Test-Path (Join-Path $record 'Power-After.txt') -PathType Leaf) 'Power-After 寫到 ProgramData\NUC8-Setup'
}finally{if(Test-Path $fixture){Remove-Item $fixture -Recurse -Force}}
Write-Host "Power record location tests passed: $count"
