#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$value,[string]$name){if(-not $value){throw $name}}
function Assert-SetupDriverTargetIntegrity {param($Target,$Root) return $true}
function Get-SetupDriverDeviceInventory {param($Targets) return [pscustomobject]@{InstanceId='PCI\FIXTURE\1'}}
function Get-SetupDriverTargetPlan {param($Target,$Devices,$Build,$Architecture) return @([pscustomobject]@{InstanceId='PCI\FIXTURE\1';Status='UpdateRequired'},[pscustomobject]@{InstanceId='PCI\FIXTURE\2';Status='Current'})}
$script:exitCode=5
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath) return [pscustomobject]@{ExitCode=$script:exitCode}}
function Get-SetupDriverReadback {param($Plan,$Devices) return [pscustomobject]@{InstanceId=$Plan.InstanceId;Status='Updated';Reason='fixture readback'}}
$target=[pscustomobject]@{InfPath='fixture.inf'}
$r=Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'
Assert ($r.Failures.Count -gt 0) 'native 非成功退出須保留失敗'
Assert ($r.Results.Count -eq 2 -and $r.Results[0].Status -eq 'InstallFailed' -and $r.Results[1].Status -eq 'Current') 'native 安裝失敗不可將讀回的結果標為 Updated'
foreach($code in @(0,259,3010)){
 $script:exitCode=$code
 $r=Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'
 Assert ($r.Results[0].Status -eq 'Updated' -and $r.Failures.Count -eq 0) ('成功或需重啟退出碼保留正常讀回 '+$code)
}
Write-Output 'failed install status test passed'
