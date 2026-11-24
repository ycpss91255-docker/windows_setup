#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/start_menu/start_pins_policy_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 匯出回 0x80070490（Host 不存在）或逾時（Host 被暫停）時，先以系統啟用介面喚醒再有界重試；全部以替身，不啟動真程序。
$script:exportQueue=@();$script:exportCalls=0;$script:wakeCalls=0;$script:wakeThrows=$false;$script:sleeps=0;$script:hostPresent=$false;$script:pins=0
function Invoke-StartPinsNativeExport {param($ExportPath,$TimeoutSeconds)
 $script:exportCalls++;$next=$script:exportQueue[0];$script:exportQueue=@($script:exportQueue|Select-Object -Skip 1)
 if($next -eq 'Ok'){[IO.File]::WriteAllText($ExportPath,$(if($script:pins -eq 0){'{"pinnedList":[]}'}else{'{"pinnedList":[{"desktopAppId":"X"}]}'}));return [pscustomobject]@{Status='Ok';HResult=0;Error=$null}}
 if($next -eq 'NotFound'){return [pscustomobject]@{Status='Failed';HResult=-2147023728;Error=(New-Object Runtime.InteropServices.COMException('synthetic',-2147023728))}}
 if($next -eq 'TimedOut'){return [pscustomobject]@{Status='TimedOut';HResult=$null;Error=$null}}
 return [pscustomobject]@{Status='Failed';HResult=-2147024891;Error=(New-Object UnauthorizedAccessException 'synthetic denied')}
}
function Invoke-StartPinsHostActivation {$script:wakeCalls++;if($script:wakeThrows){throw 'synthetic activation denied'};[pscustomobject]@{ProcessId=1}}
function Start-Sleep {param($Seconds)$script:sleeps++}
function Get-Process {param($Id,$ErrorAction);if($Id){return [pscustomobject]@{SessionId=4}};if($script:hostPresent){[pscustomobject]@{ProcessName='StartMenuExperienceHost';SessionId=4}}}
$policy=[pscustomobject]@{Status='PendingSignIn';PolicyInstalled=$true}
$out=Join-Path $env:TEMP ('start_wake_'+[guid]::NewGuid().ToString('N')+'.json')
function Reset([string[]]$Queue,[bool]$HostPresent=$false){$script:exportQueue=$Queue;$script:exportCalls=0;$script:wakeCalls=0;$script:wakeThrows=$false;$script:sleeps=0;$script:hostPresent=$HostPresent;$script:pins=0}
function Run($p=$policy){try{Get-StartPinsExportState $out $p}catch{[pscustomobject]@{Threw=$true;Message=$_.Exception.Message}}}

Reset @('Ok');$r=Run
Assert ($r.Success -and $r.Status -eq 'Confirmed' -and $script:wakeCalls -eq 0) 'healthy export never wakes the host'
Reset @('NotFound','Ok');$r=Run
Assert ($script:wakeCalls -eq 1 -and $r.Success -and $r.Status -eq 'Confirmed' -and $r.PinCount -eq 0) 'absent host is woken once and the retried empty export confirms'
Reset @('TimedOut','Ok');$r=Run
Assert ($script:wakeCalls -eq 1 -and $r.Success -and $r.Status -eq 'Confirmed') 'suspended host (export timeout) is woken once and the retried export confirms'
Reset @('NotFound','Ok');$script:pins=2;$r=Run
Assert (-not $r.Success -and $r.Status -eq 'PendingSignIn' -and $r.PinCount -eq 1) 'woken host that still reports pins is never success'
Reset @('NotFound','NotFound','NotFound','NotFound');$r=Run
Assert ($script:wakeCalls -eq 1 -and $script:exportCalls -eq 4 -and $script:sleeps -eq 2 -and -not $r.Success -and $r.Status -eq 'PendingSignIn' -and $r.ExportStatus -eq 'Unavailable' -and $r.NativeHResult -eq '0x80070490' -and $r.Reason -like '*已嘗試喚醒*') 'retry is bounded to three attempts and stays pending with an honest reason'
Reset @('TimedOut','TimedOut');$r=Run
Assert ($script:exportCalls -eq 2 -and -not $r.Success -and $r.Status -eq 'PendingSignIn' -and $r.ExportStatus -eq 'TimedOut' -and $null -eq $r.NativeHResult -and $r.Reason -like '*逾時*') 'timeout that persists after waking is reported as TimedOut, not success'
Reset @('NotFound');$script:wakeThrows=$true;$r=Run
Assert (-not $r.Success -and $r.Status -eq 'PendingSignIn' -and $script:exportCalls -eq 1 -and $r.Reason -like '*synthetic activation denied*') 'activation error text is recorded in Reason'
Reset @('TimedOut');$script:wakeThrows=$true;$r=Run
Assert ($r.ExportStatus -eq 'TimedOut' -and $r.Reason -like '*synthetic activation denied*') 'activation error keeps the TimedOut classification'
Reset @('NotFound','Other');$r=Run
Assert (-not $r.Success -and $r.Status -eq 'PendingSignIn' -and $r.Reason -like '*HRESULT*') 'unexpected retry failure is pending with its HRESULT, never success'
Reset @('NotFound') $true;$r=Run
Assert ($r.Threw -and $script:wakeCalls -eq 0) 'not-found with a live host is not hidden and does not wake'
Reset @('Other');$r=Run
Assert ($r.Threw -and $script:wakeCalls -eq 0) 'other native errors still fail loudly'
Reset @('TimedOut');$r=Run ([pscustomobject]@{Status='LegacyPendingApply';PolicyInstalled=$false})
Assert ($r.Threw -and $script:wakeCalls -eq 0) 'timeout without an installed policy is not reported as waiting for sign-in'
