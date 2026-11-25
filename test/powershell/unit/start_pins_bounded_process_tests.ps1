#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/start_menu/start_pins_policy_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 真實子程序：逾時要在上限內回來，並結束整個子程序樹（原生匯出被暫停的 Host 卡住時不得拖垮 worker）。
Assert ([bool](Get-Command Invoke-StartPinsBoundedProcess -ErrorAction SilentlyContinue)) 'bounded process runner exists'
$marker=Join-Path $env:TEMP ('bounded_'+[guid]::NewGuid().ToString('N')+'.pid')
$sw=[Diagnostics.Stopwatch]::StartNew()
$r=Invoke-StartPinsBoundedProcess -ScriptText ("[IO.File]::WriteAllText('"+$marker+"',[string]`$PID);Start-Sleep -Seconds 60") -TimeoutSeconds 3
$elapsed=$sw.Elapsed.TotalSeconds
Assert ($r.TimedOut -and $elapsed -lt 15) ('hung child returns within the limit (elapsed '+[math]::Round($elapsed,1)+'s)')
$childPid=[int][IO.File]::ReadAllText($marker);Start-Sleep -Milliseconds 500
Assert ($null -eq (Get-Process -Id $childPid -ErrorAction SilentlyContinue)) 'timed-out child process is killed'
Remove-Item $marker -ErrorAction SilentlyContinue
$r=Invoke-StartPinsBoundedProcess -ScriptText "[Console]::Out.WriteLine('HRESULT=-2147023728');exit 2" -TimeoutSeconds 20
Assert (-not $r.TimedOut -and $r.ExitCode -eq 2 -and $r.Output -like '*HRESULT=-2147023728*') 'finished child reports exit code and output'
$r=Invoke-StartPinsBoundedProcess -ScriptText "exit 0" -TimeoutSeconds 20
Assert (-not $r.TimedOut -and $r.ExitCode -eq 0) 'successful child reports exit code 0'
