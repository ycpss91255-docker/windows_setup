#Requires -Version 5.1
# 現場重放（#391）：用 NUC 實際擷取的使用者語言登錄資料與 SSH 端略過輸出，重放圖示 Verify／Load。
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$sceneRoot=Join-Path $root 'test/powershell/fixtures/nuc_scene_391'
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$fixtureSid='S-1-5-21-1000-2000-3000-1001'
$synthetic='HKCU:\Software\NUC8SetupSceneReplay_'+[guid]::NewGuid().ToString('N')
$work=Join-Path $env:TEMP ('icons_scene_replay_'+[guid]::NewGuid().ToString('N'))
function Import-SceneRegistry([string]$Path,[string]$Base,[hashtable]$Override=@{}) {
 $key=$null
 foreach($line in [IO.File]::ReadAllLines($Path,[Text.Encoding]::UTF8)){
  if(-not $line.Trim()){continue}
  if($line -match '^HKEY_USERS\\(.+)$'){$key=$Base+'\'+$Matches[1];[void](New-Item -Path $key -Force);continue}
  if($line -match '^\s{4}(.+?)\s{4}(REG_[A-Z_]+)\s{4}(.*)$'){
   $name=$Matches[1];$type=$Matches[2];$data=$Matches[3]
   if($key.EndsWith('\MuiCached') -and $Override.ContainsKey($name)){$data=$Override[$name]}
   switch($type){
    'REG_SZ'{New-ItemProperty -Path $key -Name $name -PropertyType String -Value $data -Force|Out-Null}
    'REG_DWORD'{New-ItemProperty -Path $key -Name $name -PropertyType DWord -Value ([int][BitConverter]::ToInt32([BitConverter]::GetBytes([Convert]::ToUInt32($data.Substring(2),16)),0)) -Force|Out-Null}
    'REG_BINARY'{New-ItemProperty -Path $key -Name $name -PropertyType Binary -Value ([byte[]]@(for($i=0;$i -lt $data.Length;$i+=2){[Convert]::ToByte($data.Substring($i,2),16)})) -Force|Out-Null}
    'REG_MULTI_SZ'{New-ItemProperty -Path $key -Name $name -PropertyType MultiString -Value ([string[]]($data -split '\\0')) -Force|Out-Null}
    default{throw ('unsupported fixture type '+$type)}
   }
  }else{throw ('unparsed fixture line: '+$line)}
 }
}
function Invoke-SceneEntry([string]$Mode,[string]$Base) {
 $caseDir=Join-Path $work ([guid]::NewGuid().ToString('N'))
 $package=Join-Path $caseDir 'package';$core=Join-Path $package 'core';$desktop=Join-Path $package 'modules/desktop'
 [void][IO.Directory]::CreateDirectory($core);[void][IO.Directory]::CreateDirectory($desktop)
 Copy-Item -LiteralPath (Join-Path $root 'modules/desktop/desktop_icon_layout.ps1') -Destination $desktop
 Copy-Item -LiteralPath (Join-Path $root 'core/entry_os_boundary.ps1') -Destination $core
 [IO.File]::WriteAllText((Join-Path $core 'gui_stage_library.ps1'),'function Invoke-SetupGuiPublicDispatch { param($PackageRoot,$Role,[switch]$Worker,[switch]$VerifyOnly,$IconMode,$VerificationRunId) [IO.File]::WriteAllText($env:SCENE_PROCEED_MARKER,"dispatch:"+$IconMode) }',[Text.UTF8Encoding]::new($true))
 $wrapper=Join-Path $caseDir 'wrapper.ps1'
 [IO.File]::WriteAllText($wrapper,@'
param([string]$Entry,[string]$Mode,[string]$Base,[string]$FixtureSid)
$ErrorActionPreference='Stop'
# SSH 端 Get-UICulture 實際值未擷取；以非 zh-TW 代表，並記錄是否被讀取。
function global:Get-UICulture {[IO.File]::WriteAllText($env:SCENE_CALLER_MARKER,'called');[pscustomobject]@{Name='en-US'}}
# 把目前身分的 HKEY_USERS 讀取導向去識別的現場登錄資料（合成根）。
function global:Get-ItemProperty {[CmdletBinding()]param([string]$LiteralPath) $mapped=$LiteralPath -replace '^Registry::HKEY_USERS\\[^\\]+',($Base+'\'+$FixtureSid);Microsoft.PowerShell.Management\Get-ItemProperty -LiteralPath $mapped}
# 提權由測試替身截獲，不啟動真實 process；走到提權代表語言判斷已通過。
function global:Start-Process {[IO.File]::WriteAllText($env:SCENE_PROCEED_MARKER,'elevation')}
& $Entry -Mode $Mode
'@,[Text.UTF8Encoding]::new($true))
 $env:SCENE_PROCEED_MARKER=Join-Path $caseDir 'proceed.marker';$env:SCENE_CALLER_MARKER=Join-Path $caseDir 'caller.marker'
 $prior=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{$out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -Entry (Join-Path $desktop 'desktop_icon_layout.ps1') -Mode $Mode -Base $Base -FixtureSid $fixtureSid 2>&1|Out-String;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
 [pscustomobject]@{Output=$out;ExitCode=$code;Proceeded=(Test-Path $env:SCENE_PROCEED_MARKER);CallerCultureRead=(Test-Path $env:SCENE_CALLER_MARKER)}
}
try{
 [void][IO.Directory]::CreateDirectory($work)
 $recorded=[IO.File]::ReadAllText((Join-Path $sceneRoot 'icons_verify_stdout.txt'),[Text.Encoding]::UTF8)
 $skipLine='[略過] 目前桌面排列範本僅適用繁體中文，未套用座標。'
 Assert ($recorded.StartsWith($skipLine) -and $recorded -match 'Skipped\s+desktop_icon_layout\.ps1') '現場記錄確實是 SSH 端 Verify 被略過'
 $scene=Join-Path $synthetic 'scene'
 Import-SceneRegistry (Join-Path $sceneRoot 'target_user_desktop_key.reg.txt') $scene
 $desktopKey=$scene+'\'+$fixtureSid+'\Control Panel\Desktop'
 $values=Get-ItemProperty -LiteralPath $desktopKey
 Assert ($null -eq $values.PSObject.Properties['PreferredUILanguages'] -and [string]$values.PreferredUILanguagesPending -ceq 'zh-TW') '現場資料保留：使用者語言只有 Pending／Previous，沒有 PreferredUILanguages'
 foreach($mode in @('Verify','Load')){
  $run=Invoke-SceneEntry $mode $scene
  Write-Host ('replay '+$mode+' exit='+$run.ExitCode+' caller-culture-read='+$run.CallerCultureRead+' proceeded='+$run.Proceeded);Write-Host $run.Output
  Assert ($run.Output -notmatch '略過' -and $run.Output -notmatch 'Skipped' -and $run.Proceeded) ('現場語言為 zh-TW 時 SSH 端 '+$mode+' 不再被略過並進入後續流程')
  Assert (-not $run.CallerCultureRead) ('現場重放不讀呼叫端語言：'+$mode)
 }
 # 對照：同一條路徑改成非 zh-TW 目標，輸出必須仍是現場記錄中的略過輸出形式（確認重放環境能重現略過）。
 $english=Join-Path $synthetic 'english'
 Import-SceneRegistry (Join-Path $sceneRoot 'target_user_desktop_key.reg.txt') $english @{MachinePreferredUILanguages='en-US'}
 $run=Invoke-SceneEntry 'Verify' $english
 Assert ($run.Output.Contains($skipLine) -and $run.Output -match 'Skipped\s+desktop_icon_layout\.ps1' -and -not $run.Proceeded) '目標非 zh-TW 時仍如實略過，輸出形式與現場記錄一致'
}finally{
 if(Test-Path -LiteralPath $synthetic){Remove-Item -LiteralPath $synthetic -Recurse -Force}
 if($work.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase) -and (Test-Path $work)){Remove-Item -LiteralPath $work -Recurse -Force}
 Remove-Item Env:SCENE_PROCEED_MARKER,Env:SCENE_CALLER_MARKER -ErrorAction SilentlyContinue
}
