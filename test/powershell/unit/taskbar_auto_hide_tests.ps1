#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'modules/taskbar/taskbar_settings_library.ps1')
Assert ($null -ne (Get-Command Invoke-SetupTaskbarAutoHide -ErrorAction SilentlyContinue)) 'Taskbar exposes original-source auto-hide apply and readonly verification'
$script:state=[uint32]2;$script:applyCalls=0;$script:writeCalls=0
function Get-SetupTaskbarPersistedAutoHide {return (($script:state -band 1) -eq 1)}
function Set-SetupTaskbarPersistedAutoHide {}
function Invoke-SetupTaskbarNativeAutoHide {param([string]$ModuleRoot,[bool]$Apply) $script:applyCalls++;if($Apply){$script:writeCalls++;if(-not $script:discard){$script:state=$script:state -bor 1}};return $script:state}
$r=Invoke-SetupTaskbarAutoHide -ModuleRoot (Join-Path $root 'modules/taskbar')
Assert ($r.AutoHide -and $r.AppBarState -eq 3 -and $script:writeCalls -eq 1) 'Apply enables auto-hide while preserving always-on-top state'
$before=$script:writeCalls;$r=Invoke-SetupTaskbarAutoHide -ModuleRoot (Join-Path $root 'modules/taskbar') -VerifyOnly
Assert ($r.AutoHide -and $script:writeCalls -eq $before) 'VerifyOnly reads the native current-user taskbar without writing'
$script:state=2;$r=Invoke-SetupTaskbarAutoHide -ModuleRoot (Join-Path $root 'modules/taskbar') -VerifyOnly
Assert (-not $r.AutoHide -and $script:writeCalls -eq $before) 'VerifyOnly reports auto-hide disabled rather than silently applying'
$script:discard=$true;$failed=$false
try{Invoke-SetupTaskbarAutoHide -ModuleRoot (Join-Path $root 'modules/taskbar')|Out-Null}catch{$failed=$true}
Assert $failed 'Apply rejects an unchanged native state after setting auto-hide'
# 持久化：ABM_SETSTATE 只改執行中狀態，重開或 Explorer 重啟後需靠 StuckRects3 保留（NUC8 #353）。
$mod=Join-Path $root 'modules/taskbar'
$script:native=[uint32]2;$script:persisted=$false;$script:persistWrites=0;$script:persistDiscard=$false
function Invoke-SetupTaskbarNativeAutoHide {param([string]$ModuleRoot,[bool]$Apply) if($Apply){$script:native=$script:native -bor 1};return $script:native}
function Get-SetupTaskbarPersistedAutoHide {return $script:persisted}
function Set-SetupTaskbarPersistedAutoHide {$script:persistWrites++;if(-not $script:persistDiscard){$script:persisted=$true}}
$r=Invoke-SetupTaskbarAutoHide -ModuleRoot $mod
Assert ($r.AutoHide -and $r.PersistedAutoHide -and $script:persistWrites -eq 1) 'Apply persists auto-hide to StuckRects3 when Explorer did not'
$script:persisted=$true;$before=$script:persistWrites;$r=Invoke-SetupTaskbarAutoHide -ModuleRoot $mod
Assert ($script:persistWrites -eq $before -and $r.PersistedAutoHide) 'Apply does not rewrite an already persisted auto-hide'
$script:native=[uint32]3;$script:persisted=$false;$before=$script:persistWrites;$r=Invoke-SetupTaskbarAutoHide -ModuleRoot $mod -VerifyOnly
Assert (-not $r.AutoHide -and -not $r.PersistedAutoHide -and $r.AppBarState -eq 3 -and $script:persistWrites -eq $before) 'VerifyOnly fails when only the running state is hidden and never writes'
$script:native=[uint32]2;$script:persisted=$true;$r=Invoke-SetupTaskbarAutoHide -ModuleRoot $mod -VerifyOnly
Assert (-not $r.AutoHide -and $r.PersistedAutoHide) 'VerifyOnly fails when only the persisted bit is set'
$script:native=[uint32]3;$script:persisted=$true;$r=Invoke-SetupTaskbarAutoHide -ModuleRoot $mod -VerifyOnly
Assert ($r.AutoHide -and $r.PersistedAutoHide) 'VerifyOnly succeeds when running and persisted states agree'
$script:native=[uint32]2;$script:persisted=$false;$script:persistDiscard=$true;$failed=$false
try{Invoke-SetupTaskbarAutoHide -ModuleRoot $mod|Out-Null}catch{$failed=$true}
Assert $failed 'Apply fails honestly when the persisted bit cannot be read back'
function Invoke-SetupTaskbarNativeAutoHide {param([string]$ModuleRoot,[bool]$Apply) throw 'fixture missing interactive taskbar'}
$failed=$false;try{Invoke-SetupTaskbarAutoHide -ModuleRoot (Join-Path $root 'modules/taskbar')|Out-Null}catch{$failed=$true}
Assert $failed 'Missing current-session taskbar remains a failure'