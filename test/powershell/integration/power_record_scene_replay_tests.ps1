#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$fx=Join-Path $root 'test\fixtures\nuc_scene\power_records'
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
function Get-Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
# 現場資料完整性：固件是第一現場工具包 modules\power 內舊版模組寫下的兩個檔案原樣複製。
Assert ((Get-Hash (Join-Path $fx 'scene_sub_sleep_query.txt')) -ceq '17DA6FE6602012967C544A6CDD5E39EADD00A02FEB697EEBB7E686ECB3D3AEF3') '固件 Power-Before 與第一現場原檔 SHA256 相同'
Assert ((Get-Hash (Join-Path $fx 'scene_standby_hibernate_idle_query.txt')) -ceq '16526F8DDA5966738F2D848AF2E8D62B72CEFE9EC8193DE3918735DC9A1BFF6D') '固件 Power-After 與第一現場原檔 SHA256 相同'
$work=Join-Path $env:TEMP ('windows_setup_power_records_scene_'+[guid]::NewGuid().ToString('N'))
try{
 $kit=Join-Path $work 'kit\modules\power';$programData=Join-Path $work 'ProgramData';$drive=Join-Path $work 'drive'
 New-Item -ItemType Directory -Path $kit,$programData,$drive -Force|Out-Null
 # 只移除系統管理員需求；其餘模組檔案原樣複製。
 Get-ChildItem (Join-Path $root 'modules\power') -File|ForEach-Object{
  $text=[IO.File]::ReadAllText($_.FullName);$text=$text -replace '(?m)^#Requires -RunAsAdministrator\r?\n',''
  [IO.File]::WriteAllText((Join-Path $kit $_.Name),$text,(New-Object Text.UTF8Encoding($true)))}
 $runner=Join-Path $work 'run.ps1'
 $body=@"
`$env:ProgramData='$programData';`$env:SystemDrive='$drive'
`$global:fx='$fx'
`$global:values=@{HibernateEnabledDefault=1};`$global:kinds=@{HibernateEnabledDefault='DWord'}
function ReadFx([string]`$n){[IO.File]::ReadAllLines((Join-Path `$global:fx `$n),[Text.Encoding]::UTF8)}
function Get-Item {param(`$LiteralPath,`$ErrorAction,[switch]`$Force) if(`$LiteralPath -ne 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'){return Microsoft.PowerShell.Management\Get-Item @PSBoundParameters};`$o=[pscustomobject]@{};`$o|Add-Member ScriptMethod GetValueNames {,@(`$global:values.Keys)};`$o|Add-Member ScriptMethod GetValue {param(`$name) `$global:values[`$name]};`$o|Add-Member ScriptMethod GetValueKind {param(`$name) `$global:kinds[`$name]};return `$o}
function powercfg.exe {
 `$global:LASTEXITCODE=0
 if(`$args[0] -eq '/hibernate' -and `$args[1] -eq 'off'){`$global:values.HibernateEnabled=0;`$global:kinds.HibernateEnabled='DWord';return}
 if(`$args[0] -ne '/query'){return}
 if(`$args.Count -eq 3){ReadFx 'scene_sub_sleep_query.txt';return}
 `$after=ReadFx 'scene_standby_hibernate_idle_query.txt';`$mark=[array]::IndexOf(`$after,(`$after|Where-Object {`$_ -like '*HIBERNATEIDLE*'}|Select-Object -First 1));`$split=`$mark-5
 if(`$args[3] -eq 'STANDBYIDLE'){`$after[0..(`$split-1)]}else{`$after[`$split..(`$after.Count-1)]}
}
& '$kit\apply_power_settings.ps1'|Out-Null
"@
 [IO.File]::WriteAllText($runner,$body,(New-Object Text.UTF8Encoding($true)))
 $output=& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $runner 2>&1|Out-String
 $exit=$LASTEXITCODE
 Assert ($exit -eq 0) ('第 03 模組以現場 powercfg 輸出執行成功；退出碼='+$exit+$(if($exit -ne 0){'；輸出：'+$output.Trim()}else{''}))
 $inKit=@(Get-ChildItem $kit -File|Where-Object Name -like 'Power-*.txt')
 Assert ($inKit.Count -eq 0) ('工具包 modules\power 不得留下每機電源紀錄（現場症狀：第一現場工具包內有 Power-Before／Power-After）：'+($inKit.Name -join ', '))
 $record=Join-Path $programData 'NUC8-Setup'
 $before=@(Get-ChildItem $record -Filter 'Power-Before-*.txt' -File -ErrorAction SilentlyContinue)
 Assert ($before.Count -eq 1) 'Power-Before 寫到 ProgramData\NUC8-Setup'
 Assert ((Get-Hash $before[0].FullName) -ceq (Get-Hash (Join-Path $fx 'scene_sub_sleep_query.txt'))) 'ProgramData 的 Power-Before 與現場原檔位元組相同'
 Assert (Test-Path (Join-Path $record 'Power-After.txt') -PathType Leaf) 'Power-After 寫到 ProgramData\NUC8-Setup'
 Assert ((Get-Hash (Join-Path $record 'Power-After.txt')) -ceq (Get-Hash (Join-Path $fx 'scene_standby_hibernate_idle_query.txt'))) 'ProgramData 的 Power-After 與現場原檔位元組相同'
}finally{if(Test-Path $work){Remove-Item $work -Recurse -Force}}
Write-Host "Power record scene replay tests passed: $count"
