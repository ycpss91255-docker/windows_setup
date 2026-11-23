#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$value,[string]$name){Write-Host ('@@ASSERT@@'+(@{Name=$name;Passed=$value}|ConvertTo-Json -Compress));if(-not $value){throw $name}}
function Assert-SetupDriverTargetIntegrity {param($Target,$Root) return $true}
function Get-SetupDriverDeviceInventory {param($Targets) return [pscustomobject]@{InstanceId='PCI\FIXTURE\1'}}
function Get-SetupDriverTargetPlan {param($Target,$Devices,$Build,$Architecture) return @([pscustomobject]@{InstanceId='PCI\FIXTURE\1';Status='UpdateRequired'},[pscustomobject]@{InstanceId='PCI\FIXTURE\2';Status='Current'})}
$script:exitCode=5
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath) return [pscustomobject]@{ExitCode=$script:exitCode}}
$script:readbackStatus='Updated'
function Get-SetupDriverReadback {param($Plan,$Devices) return [pscustomobject]@{InstanceId=$Plan.InstanceId;Status=$script:readbackStatus;Reason='fixture readback'}}
$target=[pscustomobject]@{InfPath='fixture.inf'}
$r=Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'
Assert ($r.Failures.Count -gt 0) 'native 非成功退出須保留失敗'
Assert ($r.Results.Count -eq 2 -and $r.Results[0].Status -eq 'InstallFailed' -and $r.Results[1].Status -eq 'Current') 'native 安裝失敗不可將讀回的結果標為 Updated'
foreach($code in @(0,259,3010)){
 $script:exitCode=$code
 $r=Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'
 Assert ($r.Results[0].Status -eq 'Updated' -and $r.Failures.Count -eq 0) ('成功或需重啟退出碼保留正常讀回 '+$code)
 Assert ($r.RebootRequired -eq ($code -eq 3010)) ('僅需重啟退出碼標示重啟 '+$code)
}
$script:readbackStatus='Unverified';$script:exitCode=0
$r=Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'
Assert ($r.Results[0].Status -eq 'Unverified' -and $r.Failures.Count -gt 0) 'native 成功但讀回未核實時保留失敗'
$script:exitCode=5
$r=Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'
Assert ($r.Results[0].Status -eq 'InstallFailed' -and $r.Failures.Count -gt 0) 'native 失敗且讀回未知時仍明確標示安裝失敗'
Write-Output 'failed install status test passed'
