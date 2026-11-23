#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/start_menu/start_pins_policy_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 現場重放：fixture 取自 NUC8 實機（來源、去識別與缺漏見 fixtures/nuc_start_host/README.md）。狀態機只依紀錄行為。
$lines=[IO.File]::ReadAllLines((Join-Path $root 'test/powershell/fixtures/nuc_start_host/product_path_rehearsal.out'),[Text.Encoding]::UTF8)
function Pick([string]$Pattern,[int]$Index=0){@($lines|Where-Object {$_ -match $Pattern})[$Index]}
$absentExport=Pick '^export\(before activation\): FAIL (0x[0-9a-f]+)' 0
$suspendedThreads=Pick '^threads=.*Suspended=\d+'
$suspendedExport=Pick '^export\(before activation\): TIMEOUT' 0
$activateRows=@($lines|Where-Object {$_ -match '^activate: hr=0x00000000 pid=(\d+)'})
$okRows=@($lines|Where-Object {$_ -match '^\s+export try 1: OK .*pins=(\d+)'})
Assert ($absentExport -match '0x80070490' -and $suspendedThreads -match 'Suspended=25' -and $suspendedExport -and $activateRows.Count -eq 2 -and $okRows.Count -eq 2) 'fixture carries the recorded absent / suspended / activated / exported rows'
$pinsAfter=[int]([regex]::Match($okRows[0],'pins=(\d+)').Groups[1].Value)
$hr=[BitConverter]::ToInt32([BitConverter]::GetBytes([Convert]::ToUInt32('80070490',16)),0)
$script:state='Absent';$script:activations=0
$global:StartPinsExportInProcess=$true
function Export-StartLayout {param($Path,$ErrorAction)
 # 同一份紀錄狀態。Suspended 在現場是「卡住」；替身以拋例外代表，讓沒有有界匯出的版本也能以同一狀態重放而不卡住測試。
 if($script:state -eq 'Absent'){throw (New-Object Runtime.InteropServices.COMException('replayed',$hr))}
 if($script:state -eq 'Suspended'){throw 'replayed: native export hangs on a suspended host'}
 [IO.File]::WriteAllText($Path,$(if($pinsAfter -eq 0){'{"pinnedList":[]}'}else{'{"pinnedList":[{"desktopAppId":"X"}]}'}))
}
function Invoke-StartPinsNativeExport {param($ExportPath,$TimeoutSeconds)
 switch($script:state){
  'Absent'{return [pscustomobject]@{Status='Failed';HResult=$hr;Error=(New-Object Runtime.InteropServices.COMException('replayed',$hr))}}
  'Suspended'{return [pscustomobject]@{Status='TimedOut';HResult=$null;Error=$null}}
  default{[IO.File]::WriteAllText($ExportPath,$(if($pinsAfter -eq 0){'{"pinnedList":[]}'}else{'{"pinnedList":[{"desktopAppId":"X"}]}'}));return [pscustomobject]@{Status='Ok';HResult=0;Error=$null}}
 }
}
function Invoke-StartPinsHostActivation {$script:activations++;$script:state='Running';[pscustomobject]@{ProcessId=1}}
function Start-Sleep {param($Seconds)}
function Get-Process {param($Id,$ErrorAction);if($Id){return [pscustomobject]@{SessionId=1}};if($script:state -ne 'Absent'){[pscustomobject]@{ProcessName='StartMenuExperienceHost';SessionId=1}}}
$policy=[pscustomobject]@{Status='PendingSignIn';PolicyInstalled=$true}
$out=Join-Path $env:TEMP ('start_replay_'+[guid]::NewGuid().ToString('N')+'.json')
# 情境 A（現場）：Host 不存在，匯出 0x80070490，啟用後匯出成功且釘選為 0。
$script:state='Absent';$r=Get-StartPinsExportState $out $policy
Assert ($script:activations -eq 1 -and $r.Success -and $r.Status -eq 'Confirmed' -and $r.PinCount -eq $pinsAfter) 'replay A: absent host -> activation -> empty native export confirms (recorded outcome)'
# 情境 B（現場）：Host 被暫停，匯出逾時，啟用後匯出成功。
$script:state='Suspended';$script:activations=0;$r=Get-StartPinsExportState $out $policy
Assert ($script:activations -eq 1 -and $r.Success -and $r.Status -eq 'Confirmed') 'replay B: suspended host (export timeout) -> activation -> empty native export confirms (recorded outcome)'
# 底線：啟用沒有效果時（紀錄之外的假設情境）仍如實回報待登入，不得判成功。
function Invoke-StartPinsHostActivation {$script:activations++;[pscustomobject]@{ProcessId=1}}
$script:state='Absent';$script:activations=0;$r=Get-StartPinsExportState $out $policy
Assert (-not $r.Success -and $r.Status -eq 'PendingSignIn' -and $r.NativeHResult -eq '0x80070490') 'activation without effect keeps the recorded PendingSignIn symptom'
