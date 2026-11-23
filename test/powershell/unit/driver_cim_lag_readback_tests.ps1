#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 重放 2026-11-23 NUC 現場：安裝後 DEVPKEY 立即正確，CIM 列到 t+120 才出現；移除後 CIM 留幽靈列。資料見 fixtures/nuc_driver_cim_lag_20261123/README.md
$fx=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../fixtures/nuc_driver_cim_lag_20261123/cim_lag_timeseries.json') -Raw -Encoding UTF8|ConvertFrom-Json
$id=[string]$fx.InstanceId
$script:clock=0;$script:mode='install';$script:signer=[string]$fx.SignerName;$script:sleeps=@();$script:enumCalls=0
function Get-Sample {
 if($script:mode -eq 'ghost'){return $fx.afterRemoveGhost}
 $rows=@($fx.afterInstall|Where-Object {$_.atSeconds -le $script:clock})
 if($script:mode -eq 'neverCim'){$s=$rows[-1];return [pscustomobject]@{cim=[pscustomobject]@{DriverVersion=$null;DriverProviderName=$null;IsSigned=$null};devpkey=$s.devpkey;status=$s.status}}
 return $rows[-1]
}
function Assert-SetupDriverTargetIntegrity {param($Target,$Root) return $true}
function Get-SetupDriverTargetPlan {param($Target,$Devices,$Build,$Architecture) return @([pscustomobject]@{InstanceId=$id;InfPath='fixture.inf';Status='UpdateRequired';CurrentVersion='';TargetVersion=[string]$fx.TargetVersion;TargetProvider=[string]$fx.TargetProvider;ProviderAliases=@()})}
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath) $script:clock=0;return [pscustomobject]@{ExitCode=0}}
function Invoke-SetupDriverPnpRescan {[pscustomobject]@{ExitCode=0}}
function Start-Sleep {param([int]$Seconds) $script:sleeps+=$Seconds;$script:clock+=$Seconds}
function Get-CimInstance {param($ClassName,$ErrorAction)
 $c=(Get-Sample).cim
 [pscustomobject]@{DeviceID=$id;DriverVersion=$c.DriverVersion;DriverProviderName=$c.DriverProviderName;IsSigned=$c.IsSigned;InfName='';Signer=''}
}
function Get-PnpDevice {param([switch]$PresentOnly,$ErrorAction) [pscustomobject]@{InstanceId=$id;FriendlyName='fixture';Class='System';Status=(Get-Sample).status}}
function Get-PnpDeviceProperty {param([string]$InstanceId,[string]$KeyName,$ErrorAction)
 $p=(Get-Sample).devpkey
 switch($KeyName){
  'DEVPKEY_Device_DriverVersion'{return [pscustomobject]@{Data=$p.DriverVersion}}
  'DEVPKEY_Device_DriverProvider'{return [pscustomobject]@{Data=$p.DriverProvider}}
  'DEVPKEY_Device_DriverInfPath'{return [pscustomobject]@{Data=$p.DriverInfPath}}
  default{return [pscustomobject]@{Data=@('PCI\VEN_8086&DEV_A131')}}
 }
}
function Get-SetupDriverEnumDriversXmlText {
 $script:enumCalls++
 if(-not $script:signer){return '<PnpUtil></PnpUtil>'}
 return ('<?xml version="1.0" encoding="utf-8"?><PnpUtil><Driver DriverName="'+$fx.PublishedName+'"><OriginalName>x.inf</OriginalName><SignerName>'+$script:signer+'</SignerName></Driver></PnpUtil>')
}
$target=[pscustomobject]@{InfPath='fixture.inf';HardwareIds=@('PCI\VEN_8086&DEV_A131')}
function Invoke-Scene {param([string]$Mode,[string]$Signer)
 $script:mode=$Mode;$script:signer=$Signer;$script:clock=0;$script:sleeps=@();$script:enumCalls=0;$script:SetupDriverReadbackWaited=0
 Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'
}
function Total {($script:sleeps|Measure-Object -Sum).Sum}

# 現場：CIM 列空、簽署者由 pnputil 查得 → 立即核實，不必等 CIM
$r=Invoke-Scene -Mode install -Signer ([string]$fx.SignerName)
Assert ($r.Results[0].Status -eq 'Updated' -and $r.Failures.Count -eq 0) 'CIM 列尚空但 DEVPKEY 與 pnputil 簽署者已確認時應核實為 Updated'
Assert ($script:sleeps.Count -eq 0) '簽署者已由 pnputil 確認時不必等待 CIM 列'

# 查不到簽署者：有界輪詢到 CIM 列出現（t+120）後以 CIM 的 IsSigned 為準
$r=Invoke-Scene -Mode install -Signer ''
Assert ($r.Results[0].Status -eq 'Updated' -and $r.Failures.Count -eq 0) '簽署者查不到時輪詢至 CIM 列出現後應核實為 Updated'
Assert ((Total) -ge 120 -and (Total) -le 150) '輪詢總等待須涵蓋 CIM 延遲且不超過 150 秒'

# 反例：CIM 列一直不出現且查不到簽署者 → Unverified，等待不超過上限
$r=Invoke-Scene -Mode neverCim -Signer ''
Assert ($r.Results[0].Status -eq 'Unverified' -and $r.Failures.Count -gt 0) 'CIM 列一直不出現且簽署者未確認須維持 Unverified 並列入失敗'
Assert ((Total) -le 150) '列一直不出現時總等待不得超過 150 秒'

# 反例：簽署者不符既有規則 → 不得因版本相符而成功
$r=Invoke-Scene -Mode neverCim -Signer 'Contoso Test Publisher'
Assert ($r.Results[0].Status -eq 'Unverified' -and $r.Failures.Count -gt 0) '簽署者不符時不得核實為 Updated'

# 反例：移除後的幽靈列（IsSigned=false、DEVPKEY 無驅動）不得被當成成功
$r=Invoke-Scene -Mode ghost -Signer ([string]$fx.SignerName)
Assert ($r.Results[0].Status -ne 'Updated' -and $r.Results[0].Status -ne 'Current' -and $r.Failures.Count -gt 0) '幽靈列不得被當成成功'

# 共用等待額度：第一個目標用完額度後，第二個目標不再重複等待
$script:SetupDriverReadbackWaited=0;$script:mode='neverCim';$script:signer='';$script:sleeps=@();$script:clock=0
$null=Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'
$first=Total;$script:sleeps=@()
$null=Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log'
Assert ($first -eq 150 -and $script:sleeps.Count -eq 0) '各目標共用一次等待額度，第二個目標不再等待'
Write-Output 'driver cim lag readback test passed'
