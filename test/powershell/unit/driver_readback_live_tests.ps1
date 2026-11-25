#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Assert-SetupDriverTargetIntegrity {param($Target,$Root) return $true}
# 模擬同一程序內 Win32_PnPSignedDriver 一直回傳安裝前的舊版本
function Get-SetupDriverDeviceInventory {param($Targets) return [pscustomobject]@{InstanceId='PCI\FIXTURE\1';Status='OK';DriverVersion='1.0.0.0';DriverProvider='Vendor';DriverSigned=$true}}
function Get-SetupDriverTargetPlan {param($Target,$Devices,$Build,$Architecture) return @([pscustomobject]@{InstanceId='PCI\FIXTURE\1';InfPath='fixture.inf';Status='UpdateRequired';CurrentVersion='1.0.0.0';TargetVersion='2.0.0.0';TargetProvider='Vendor';ProviderAliases=@()})}
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath) return [pscustomobject]@{ExitCode=0}}
$script:scans=0;$script:sleeps=@()
function Invoke-SetupDriverPnpRescan {$script:scans++;[pscustomobject]@{ExitCode=0}}
function Start-Sleep {param([int]$Seconds) $script:sleeps+=$Seconds}
$script:live=$null
function Get-SetupDriverLiveDriverProperty {param([string]$InstanceId) return $script:live}
$target=[pscustomobject]@{InfPath='fixture.inf'}
function Invoke-Fixture {$script:scans=0;$script:sleeps=@();Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'}

$script:live=[pscustomobject]@{DriverVersion='2.0.0.0';DriverProvider='Vendor'}
$r=Invoke-Fixture
Assert ($r.Results[0].Status -eq 'Updated') 'WMI 讀到舊值但即時屬性為目標版本時應核實為 Updated'
Assert ($r.Failures.Count -eq 0 -and $script:sleeps.Count -eq 0) '即時屬性已核實時不得等待或列入失敗'

$script:live=[pscustomobject]@{DriverVersion='1.0.0.0';DriverProvider='Vendor'}
$r=Invoke-Fixture
Assert ($r.Results[0].Status -eq 'Unverified' -and $r.Failures.Count -gt 0) '即時屬性仍為舊版本時不得標為成功'

$script:live=$null
$r=Invoke-Fixture
Assert ($r.Results[0].Status -eq 'Unverified' -and $r.Failures.Count -gt 0) '即時屬性不可讀時不得標為成功'
Write-Output 'driver readback live test passed'
