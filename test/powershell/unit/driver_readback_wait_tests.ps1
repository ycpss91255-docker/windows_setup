#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$value,[string]$name){if(-not $value){throw $name}}
function Assert-SetupDriverTargetIntegrity {param($Target,$Root) return $true}
$script:inventoryReads=0;$script:scans=0;$script:sleeps=@();$script:bindAfter=1
function Get-SetupDriverDeviceInventory {param($Targets) $script:inventoryReads++;return [pscustomobject]@{InstanceId='PCI\FIXTURE\1';Bound=($script:inventoryReads -gt $script:bindAfter)}}
function Get-SetupDriverTargetPlan {param($Target,$Devices,$Build,$Architecture) return @([pscustomobject]@{InstanceId='PCI\FIXTURE\1';Status='UpdateRequired'},[pscustomobject]@{InstanceId='PCI\FIXTURE\2';Status='Current'})}
$script:exitCode=0
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath) return [pscustomobject]@{ExitCode=$script:exitCode}}
function Invoke-SetupDriverPnpRescan {$script:scans++;[pscustomobject]@{ExitCode=0}}
function Start-Sleep {param([int]$Seconds) $script:sleeps+=$Seconds}
function Get-SetupDriverReadback {param($Plan,$Devices) $bound=@($Devices|Where-Object Bound).Count -gt 0;return [pscustomobject]@{InstanceId=$Plan.InstanceId;Status=$(if($bound){'Updated'}else{'Unverified'});Reason=$(if($bound){'fixture bound'}else{'fixture unbound'})}}
$target=[pscustomobject]@{InfPath='fixture.inf'}
function Invoke-Fixture {Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'}
function Reset-Fixture {param([int]$BindAfter,[int]$ExitCode=0) $script:inventoryReads=0;$script:scans=0;$script:sleeps=@();$script:bindAfter=$BindAfter;$script:exitCode=$ExitCode}

# 立即綁定：不掃描、不等待
Reset-Fixture -BindAfter 1
$r=Invoke-Fixture
Assert ($r.Results[0].Status -eq 'Updated' -and $r.Failures.Count -eq 0) '立即綁定應為 Updated'
Assert ($script:scans -eq 0 -and $script:sleeps.Count -eq 0) '立即綁定不得掃描或等待'

# 延遲綁定：先掃描，再輪詢到綁定為止
Reset-Fixture -BindAfter 3
$r=Invoke-Fixture
Assert ($r.Results[0].Status -eq 'Updated' -and $r.Results[1].Status -eq 'Current') '延遲綁定在上限內應核實為 Updated'
Assert ($r.Failures.Count -eq 0) '延遲綁定在上限內不得列入失敗'
Assert ($script:scans -eq 1) '延遲綁定須先重新掃描一次'
Assert ($script:sleeps.Count -eq 2 -and (@($script:sleeps|Where-Object {$_ -ne 5}).Count -eq 0)) '輪詢間隔須為 5 秒'

# 始終未綁定：總等待不超過 30 秒，維持 Unverified 並列入失敗
Reset-Fixture -BindAfter 999
$r=Invoke-Fixture
Assert ($r.Results[0].Status -eq 'Unverified') '始終未綁定不得標為成功'
Assert ($r.Failures.Count -gt 0) '始終未綁定須列入失敗'
Assert (($script:sleeps|Measure-Object -Sum).Sum -le 30 -and $script:sleeps.Count -ge 1) '總等待須有 30 秒上限'
Assert ($r.Results[0].Reason -match '30') '失敗原因須註明已等待秒數'
Assert ($script:scans -eq 1) '始終未綁定只重新掃描一次'

# 原生安裝失敗：不掃描、不等待
Reset-Fixture -BindAfter 999 -ExitCode 5
$r=Invoke-Fixture
Assert ($script:scans -eq 0 -and $script:sleeps.Count -eq 0) '原生安裝失敗不得掃描或等待'
Assert ($r.Failures.Count -gt 0) '原生安裝失敗須保留失敗'
Write-Output 'driver readback wait test passed'
