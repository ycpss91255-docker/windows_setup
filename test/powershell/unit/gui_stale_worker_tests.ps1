#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/gui_stage_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 卡住的 GUI worker 逾時後必須清掉本輪自己建立的 worker，並只清自己建立且已超過上限的舊 worker；全部以替身，不碰真程序與真排程。
$common=Join-Path $env:TEMP ('gui_stale_'+[guid]::NewGuid().ToString('N'))
function RoleRootOf($r,$role){Join-Path (Join-Path ([IO.Path]::GetFullPath($r)) 'windows_setup_gui') $role.ToLowerInvariant()}
function WorkerCmd($id,$role='Start',$base=$common){'"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path (Join-Path (RoleRootOf $base $role) $id) 'code')+'\core/gui_worker.ps1" -Role '+$role+' -RunId '+$id}
$script:procs=@();$script:tasks=@{};$script:killed=@();$script:stopped=@();$script:unregistered=@()
function NewProc($id,[int]$pid_,[double]$ageSec,$cmd){[pscustomobject]@{ProcessId=$pid_;Name='powershell.exe';CommandLine=$cmd;CreationDate=(Get-Date).AddSeconds(-$ageSec)}}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction);$script:procs}
function Get-ScheduledTask {param($TaskName,$ErrorAction);if($script:tasks.ContainsKey($TaskName)){[pscustomobject]@{TaskName=$TaskName;State=$script:tasks[$TaskName]}}}
function Stop-ScheduledTask {param($TaskName,$ErrorAction);$script:stopped+=$TaskName}
function Unregister-ScheduledTask {param($TaskName,$Confirm,$ErrorAction);$script:unregistered+=$TaskName;$script:tasks.Remove($TaskName)}
function Stop-SetupGuiProcessTree {param([int]$ProcessId);$script:killed+=$ProcessId}
function Reset{$script:procs=@();$script:tasks=@{};$script:killed=@();$script:stopped=@();$script:unregistered=@()}

$cur=[guid]::NewGuid().ToString('D');$old=[guid]::NewGuid().ToString('D');$young=[guid]::NewGuid().ToString('D');$other=[guid]::NewGuid().ToString('D');$notask=[guid]::NewGuid().ToString('D');$foreign=[guid]::NewGuid().ToString('D')
Assert ([bool](Get-Command Stop-SetupGuiStaleWorkers -ErrorAction SilentlyContinue)) 'stale worker reaper exists'
# 舊版卡住的 worker：同角色、他輪、超過上限、有我們建立的排程 → 清除
Reset;$script:procs=@((NewProc $old 100 900 (WorkerCmd $old)));$script:tasks["WindowsSetup-Gui-Start-$old"]='Running'
$r=@(Stop-SetupGuiStaleWorkers -CommonDataRoot $common -Role Start -CurrentRunId $cur)
Assert ($script:killed -contains 100 -and $script:stopped -contains "WindowsSetup-Gui-Start-$old" -and $script:unregistered -contains "WindowsSetup-Gui-Start-$old" -and $r.Count -eq 1) 'stale worker over the limit is stopped, its task stopped and unregistered'
# 反例：不得動到
Reset;$script:procs=@((NewProc $young 200 30 (WorkerCmd $young)));$script:tasks["WindowsSetup-Gui-Start-$young"]='Running'
Stop-SetupGuiStaleWorkers -CommonDataRoot $common -Role Start -CurrentRunId $cur|Out-Null
Assert ($script:killed.Count -eq 0 -and $script:stopped.Count -eq 0 -and $script:unregistered.Count -eq 0) 'counter: a worker younger than the limit (legitimately working) is never touched'
Reset;$script:procs=@((NewProc $cur 201 900 (WorkerCmd $cur)));$script:tasks["WindowsSetup-Gui-Start-$cur"]='Running'
Stop-SetupGuiStaleWorkers -CommonDataRoot $common -Role Start -CurrentRunId $cur|Out-Null
Assert ($script:killed.Count -eq 0) 'counter: the current run is never reaped by the stale sweep'
Reset;$script:procs=@((NewProc $other 202 900 (WorkerCmd $other 'Icons')));$script:tasks["WindowsSetup-Gui-Icons-$other"]='Running'
Stop-SetupGuiStaleWorkers -CommonDataRoot $common -Role Start -CurrentRunId $cur|Out-Null
Assert ($script:killed.Count -eq 0) 'counter: a stale worker of another role is not touched'
Reset;$script:procs=@((NewProc $notask 203 900 (WorkerCmd $notask)))
Stop-SetupGuiStaleWorkers -CommonDataRoot $common -Role Start -CurrentRunId $cur|Out-Null
Assert ($script:killed.Count -eq 0) 'counter: a process without our scheduled task is not ours and is not touched'
Reset;$script:procs=@((NewProc $foreign 204 900 (WorkerCmd $foreign 'Start' (Join-Path $env:TEMP 'someone_else_root'))));$script:tasks["WindowsSetup-Gui-Start-$foreign"]='Running'
Stop-SetupGuiStaleWorkers -CommonDataRoot $common -Role Start -CurrentRunId $cur|Out-Null
Assert ($script:killed.Count -eq 0) 'counter: a worker outside the protected data root is not touched'
Reset;$script:procs=@((NewProc $old 205 900 ('"powershell.exe" -NoProfile -File C:\tools\other.ps1 -RunId '+$old)));$script:tasks["WindowsSetup-Gui-Start-$old"]='Running'
Stop-SetupGuiStaleWorkers -CommonDataRoot $common -Role Start -CurrentRunId $cur|Out-Null
Assert ($script:killed.Count -eq 0) 'counter: an unrelated powershell command line that merely mentions a run id is not touched'
Reset;$script:procs=@((NewProc $old 206 900 (WorkerCmd $old)));$script:tasks["WindowsSetup-Gui-Start-$old"]='Ready'
$r=@(Stop-SetupGuiStaleWorkers -CommonDataRoot $common -Role Start -CurrentRunId $cur)
Assert ($script:killed.Count -eq 0 -and $script:unregistered.Count -eq 0) 'counter: a matching old process whose task is not Running is left for the owner to handle'

# 鎖：卡住的 worker 持有角色鎖 → 後續 worker 被擋；清掉持鎖者後可以取得
$paths=Get-SetupGuiRunPaths -CommonDataRoot $common -Role Start -RunId $old
New-Item -ItemType Directory -Path $paths.RoleRoot -Force|Out-Null
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory)}
$held=[IO.File]::Open((Join-Path $paths.RoleRoot 'execution.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$blocked=$false;try{Open-SetupGuiExecutionLock -Paths $paths|Out-Null}catch{$blocked=($_.Exception.Message -like '*已有執行程序*')}
Assert $blocked 'a hung worker holding the role lock blocks the next worker (the reported symptom)'
function Stop-SetupGuiProcessTree {param([int]$ProcessId);$script:killed+=$ProcessId;$held.Dispose()}
Reset;$script:procs=@((NewProc $old 300 900 (WorkerCmd $old)));$script:tasks["WindowsSetup-Gui-Start-$old"]='Running'
Stop-SetupGuiStaleWorkers -CommonDataRoot $common -Role Start -CurrentRunId $cur|Out-Null
$lease=$null;try{$lease=Open-SetupGuiExecutionLock -Paths $paths}catch{}
Assert ($null -ne $lease) 'after the stale worker is reaped the role lock can be taken again'
if($lease){$lease.Dispose()}

# 本輪等待逾時：呼叫端必須結束自己建立的 worker 與排程，再丟出原本的逾時錯誤
$script:clock=Get-Date;$script:ownPid=777
function Get-Date {param($Format,[switch]$AsUTC);if($PSBoundParameters.ContainsKey('Format')){return [datetime]::Now.ToString($Format)};$script:clock=$script:clock.AddSeconds(5);$script:clock}
function Start-Sleep {param($Seconds)}
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory)}
function New-ScheduledTaskAction {param($Execute,$Argument)[pscustomobject]@{}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel)[pscustomobject]@{}}
function Register-ScheduledTask {param($TaskName,$Action,$Principal,$ErrorAction)$script:tasks[$TaskName]='Running'}
function Start-ScheduledTask {param($TaskName,$ErrorAction)}
Reset
$runId=[guid]::NewGuid().ToString('D')
$stage=[pscustomobject]@{Context=[pscustomobject]@{Role='Start';RunId=$runId;UserSID='S-1-5-21-1-2-3-1001'};CodeRoot=(Join-Path (Join-Path (RoleRootOf $common 'Start') $runId) 'code');DataRoot=(Join-Path (Join-Path (RoleRootOf $common 'Start') $runId) 'data')}
New-Item -ItemType Directory -Path $stage.DataRoot -Force|Out-Null
$scope=[pscustomobject]@{PowerShell='powershell.exe';CommonDataRoot=$common;SessionId=0}
$script:procs=@((NewProc $runId $script:ownPid 70 (WorkerCmd $runId)),(NewProc $young 888 20 (WorkerCmd $young)))
$script:tasks["WindowsSetup-Gui-Start-$young"]='Running'
$message='';try{Invoke-SetupGuiScheduledWorker -Stage $stage -Scope $scope}catch{$message=$_.Exception.Message}
Assert ($message -like '*尚未取得*') 'own timeout still reports the original no-result error'
Assert ($script:killed -contains $script:ownPid -and $script:stopped -contains "WindowsSetup-Gui-Start-$runId" -and $script:unregistered -contains "WindowsSetup-Gui-Start-$runId") 'own hung worker, its task and registration are cleaned after the timeout'
Assert ($script:killed -notcontains 888 -and $script:stopped -notcontains "WindowsSetup-Gui-Start-$young") 'a different legitimate worker running at the same time is not touched by the timeout cleanup'
Remove-Item $common -Recurse -Force -ErrorAction SilentlyContinue
