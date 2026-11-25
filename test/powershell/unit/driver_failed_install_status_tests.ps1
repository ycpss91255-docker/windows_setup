#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$value,[string]$name){Write-Host ('@@ASSERT@@'+(@{Name=$name;Passed=$value}|ConvertTo-Json -Compress));if(-not $value){throw $name}}
function Assert-SetupDriverTargetIntegrity {param($Target,$Root) return $true}
function Get-SetupDriverDeviceInventory {param($Targets) return [pscustomobject]@{InstanceId='PCI\FIXTURE\1'}}
function Get-SetupDriverTargetPlan {param($Target,$Devices,$Build,$Architecture) return @([pscustomobject]@{InstanceId='PCI\FIXTURE\1';Status='UpdateRequired'},[pscustomobject]@{InstanceId='PCI\FIXTURE\2';Status='Current'})}
$script:exitCode=5;$script:sleeps=0;$script:rescans=0
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath) return [pscustomobject]@{ExitCode=$script:exitCode}}
function Start-Sleep {param([int]$Seconds) $script:sleeps+=$Seconds}
function Invoke-SetupDriverPnpRescan {$script:rescans++;[pscustomobject]@{ExitCode=0}}
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
# 原生安裝失敗時不掃描、不等待讀回額度，並在原因寫出退出碼（與安裝後讀回等待共存）
$script:SetupDriverReadbackWaited=0;$script:sleeps=0;$script:rescans=0;$script:exitCode=5;$script:readbackStatus='Unverified'
$r=Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'
Assert ($script:sleeps -eq 0 -and $script:rescans -eq 0 -and $script:SetupDriverReadbackWaited -eq 0) 'native 安裝失敗時不掃描也不等待讀回額度'
Assert ([string]$r.Results[0].Reason -match '退出碼 5' -and $r.Installed -eq $false) 'native 安裝失敗時原因寫出退出碼且不標示已安裝'
# 安裝其實已生效（讀回 Updated）但退出碼非成功：仍標 InstallFailed，原因保留讀回資訊，避免讓人以為沒裝上
$script:SetupDriverReadbackWaited=0;$script:exitCode=1;$script:readbackStatus='Updated'
$r=Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'
Assert ($r.Results[0].Status -eq 'InstallFailed' -and [string]$r.Results[0].Reason -match '退出碼 1' -and [string]$r.Results[0].Reason -match '讀回：Updated' -and [string]$r.Results[0].Reason -match 'fixture readback' -and $r.Failures.Count -gt 0) '退出碼非成功但讀回已符合時標 InstallFailed 並保留讀回狀態與原因'
$script:readbackStatus='Unverified'
# 安裝成功但讀回仍未核實：才掃描並在共用額度內等待，不得標為 InstallFailed
$script:SetupDriverReadbackWaited=0;$script:sleeps=0;$script:rescans=0;$script:exitCode=0;$script:readbackStatus='Unverified'
$r=Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'
Assert ($script:rescans -ge 1 -and $script:sleeps -gt 0 -and $script:sleeps -le 150 -and $r.Results[0].Status -eq 'Unverified' -and $r.Installed -eq $true) '安裝成功但讀回未核實時掃描並在額度內等待，維持 Unverified'
Write-Output 'failed install status test passed'
