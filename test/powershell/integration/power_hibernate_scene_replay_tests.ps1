#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$fx=Join-Path $root 'test\fixtures\nuc_scene\power_hibernate'
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
function Read-Fx([string]$Name){[IO.File]::ReadAllText((Join-Path $fx $Name),[Text.Encoding]::UTF8)}
# 現場資料完整性：實機 powercfg /a 在套用前列出休眠與快速啟動可用，套用後兩者不可用。
$aBefore=Read-Fx 'powercfg_a_before.txt';$aAfter=Read-Fx 'powercfg_a_after.txt'
$availableBefore=$aBefore.Substring(0,$aBefore.IndexOf('此系統缺乏'))
Assert ($availableBefore.Contains('休眠') -and $availableBefore.Contains('快速啟動')) '現場套用前：powercfg /a 列出休眠與快速啟動可用'
$unavailableAfter=$aAfter.Substring($aAfter.IndexOf('此系統缺乏'))
Assert ($unavailableAfter.Contains('尚未啟用休眠') -and $unavailableAfter.Contains('快速啟動')) '現場套用後：powercfg /a 列出休眠與快速啟動不可用'
# 現場登錄值（Get-ItemProperty 輸出；空白表示該值不存在，未擷取值型別與值名稱清單）。
$registry=@{};foreach($line in (Read-Fx 'power_registry_before.txt') -split "`r?`n"){if($line -match '^(HibernateEnabled|HibernateEnabledDefault|HiberFileSizePercent)\s*:\s*(\d*)\s*$' -and $Matches[2] -ne ''){$registry[$Matches[1]]=[int]$Matches[2]}}
Assert ($registry.Count -eq 2 -and $registry.HibernateEnabledDefault -eq 1 -and -not $registry.ContainsKey('HibernateEnabled')) '現場套用前只有 HibernateEnabledDefault=1，沒有 HibernateEnabled'
# 擷取用的 Test-Path 在 Windows PowerShell 5.1 看不到系統鎖定的檔案，Test-Path=False 不能證明休眠檔不存在，因此不拿來斷言。
$work=Join-Path $env:TEMP ('windows_setup_power_scene_'+[guid]::NewGuid().ToString('N'))
try{
 $kit=Join-Path $work 'kit\modules\power';$programData=Join-Path $work 'ProgramData';$drive=Join-Path $work 'drive'
 New-Item -ItemType Directory -Path $kit,$programData,$drive -Force|Out-Null
 # 只移除系統管理員需求；其餘模組檔案原樣複製。
 Get-ChildItem (Join-Path $root 'modules\power') -File|ForEach-Object{
  $text=[IO.File]::ReadAllText($_.FullName);$text=$text -replace '(?m)^#Requires -RunAsAdministrator\r?\n',''
  [IO.File]::WriteAllText((Join-Path $kit $_.Name),$text,(New-Object Text.UTF8Encoding($true)))}
 $stateFile=Join-Path $work 'state.json'
 $runner=Join-Path $work 'run.ps1'
 $body=@"
`$env:ProgramData='$programData';`$env:SystemDrive='$drive'
`$global:fx='$fx'
`$global:values=@{};`$global:kinds=@{};`$global:calls=@()
`$global:values.HibernateEnabledDefault=$($registry.HibernateEnabledDefault);`$global:values.HiberFileSizePercent=$($registry.HiberFileSizePercent)
function ReadFx([string]`$n){[IO.File]::ReadAllLines((Join-Path `$global:fx `$n),[Text.Encoding]::UTF8)}
function Get-Item {param(`$LiteralPath,`$ErrorAction,[switch]`$Force) if(`$LiteralPath -ne 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'){return Microsoft.PowerShell.Management\Get-Item @PSBoundParameters};`$o=[pscustomobject]@{};`$o|Add-Member ScriptMethod GetValueNames {,@(`$global:values.Keys)};`$o|Add-Member ScriptMethod GetValue {param(`$name) `$global:values[`$name]};`$o|Add-Member ScriptMethod GetValueKind {param(`$name) `$global:kinds[`$name]};return `$o}
function powercfg.exe {
 `$global:calls+=@(`$args -join ' ');`$global:LASTEXITCODE=0
 if(`$args[0] -eq '/query'){
  if(`$args.Count -eq 3){ReadFx 'scene_sub_sleep_query.txt'}
  else{`$after=ReadFx 'scene_standby_hibernate_idle_query.txt';`$mark=[array]::IndexOf(`$after,(`$after|Where-Object {`$_ -like '*HIBERNATEIDLE*'}|Select-Object -First 1));`$split=`$mark-5;if(`$args[3] -eq 'STANDBYIDLE'){`$after[0..(`$split-1)]}else{`$after[`$split..(`$after.Count-1)]}}
  return}
 if(`$args[0] -eq '/hibernate' -and `$args[1] -eq 'off'){`$global:values.HibernateEnabled=0;`$global:kinds.HibernateEnabled='DWord'}
}
try{& '$kit\apply_power_settings.ps1'|Out-Null}finally{[IO.File]::WriteAllText('$stateFile',(@{Calls=@(`$global:calls);HibernateEnabled=`$global:values.HibernateEnabled;HibernateEnabledDefault=`$global:values.HibernateEnabledDefault}|ConvertTo-Json),(New-Object Text.UTF8Encoding(`$false)))}
"@
 [IO.File]::WriteAllText($runner,$body,(New-Object Text.UTF8Encoding($true)))
 $output=& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $runner 2>&1|Out-String
 $exit=$LASTEXITCODE;Assert ($exit -eq 0) ('第 03 模組在現場登錄狀態下執行成功；退出碼='+$exit+($(if($exit -ne 0){'；輸出：'+$output.Trim()}else{''})))
 $state=Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($state.HibernateEnabled -eq 0) ('套用後休眠必須停用（現場症狀：休眠仍啟用）；HibernateEnabled='+$state.HibernateEnabled+'；HibernateEnabledDefault='+$state.HibernateEnabledDefault)
 Assert (@($state.Calls|Where-Object {$_ -ceq '/hibernate off'}).Count -eq 1) ('模組呼叫一次 powercfg /hibernate off；實際呼叫：'+(@($state.Calls) -join ' | '))
}finally{if(Test-Path $work){Remove-Item $work -Recurse -Force}}
Write-Host "Power hibernate scene replay tests passed: $count"
