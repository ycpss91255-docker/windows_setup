#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
# 現場重放（重灌後、沒有驅動包的 NUC8）：fixture 是現場原樣擷取的 JSON（去識別），屬性型別與空值照實保留。
# DriverInfPath 的 Empty／無 Data 形狀來自同一台機器同一狀態的原生 Get-PnpDeviceProperty 唯讀擷取。
$fixtureRoot=Join-Path $root 'test/fixtures/nuc_scene/driver_code28_reinstall'
function Read-Fixture([string]$Name){ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $fixtureRoot $Name),[Text.Encoding]::UTF8))}
$problemDevices=@(Read-Fixture 'problem_devices.json'|ForEach-Object {$_})
$script:pnpDevices=@(Read-Fixture 'pnp_present.json'|ForEach-Object {$_})
$script:cimDrivers=@(Read-Fixture 'cim_signed_driver.json'|ForEach-Object {$_})
$shape=Read-Fixture 'live_native_shape.json'
$live=Read-Fixture 'live_plans.json'
$script:typedProperties=@{}
foreach($device in $problemDevices){
 foreach($p in @($device.Props)){
  $o=[ordered]@{InstanceId=$device.InstanceId;KeyName=$p.K;Type=$p.T}
  if($p.PSObject.Properties['D']){
   $o['Data']=switch($p.T){'UInt32'{[uint32]$p.D} 'StringList'{[string[]]@($p.D)} default{$p.D}}
  }
  $script:typedProperties[$device.InstanceId+'|'+$p.K]=[pscustomobject]$o
 }
}
# 基準擷取只列出有值的屬性；沒有值的屬性（Empty）要照同一台機器的原生唯讀擷取補回「型別 Empty、沒有 Data 成員」的真實形狀。
foreach($d in @($shape.Devices)){
 foreach($name in @($d.QueriedProperties.PSObject.Properties.Name)){
  $q=$d.QueriedProperties.$name;$key=$d.InstanceId+'|DEVPKEY_Device_'+$name
  if($script:typedProperties.ContainsKey($key)){continue}
  if($q.HasDataMember){throw ('現場有資料的屬性必須來自基準擷取 '+$key)}
  $script:typedProperties[$key]=[pscustomobject][ordered]@{InstanceId=$d.InstanceId;KeyName='DEVPKEY_Device_'+$name;Type=$q.Type}
 }
 $script:typedProperties[$d.InstanceId+'|DEVPKEY_Device_DriverInfPath']=[pscustomobject][ordered]@{InstanceId=$d.InstanceId;KeyName='DEVPKEY_Device_DriverInfPath';Type=$d.DriverInfPath.Type}
}
function Get-PnpDevice {param([switch]$PresentOnly,$ErrorAction) $script:pnpDevices}
function Get-CimInstance {param($ClassName,$ErrorAction) if($ClassName -ne 'Win32_PnPSignedDriver'){throw 'unexpected class'};$script:cimDrivers}
function Get-PnpDeviceProperty {
 param($InstanceId,$KeyName,$ErrorAction)
 $key=$InstanceId+'|'+$KeyName
 if(-not $script:typedProperties.ContainsKey($key)){throw ('現場沒有擷取此屬性 '+$key)}
 $script:typedProperties[$key]
}
$manifest=Get-Content -LiteralPath (Join-Path $root 'drivers/nuc8i7hvk_hnk/manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$hardwareIds=@('PCI\VEN_8086&DEV_1911','PCI\VEN_8086&DEV_A127','PCI\VEN_8086&DEV_A131','ACPI\INT3515')
$targets=@($manifest.Packages|ForEach-Object Drivers|Where-Object {@($_.HardwareIds|Where-Object {$_ -in $hardwareIds}).Count})
Assert ($problemDevices.Count -eq 6 -and $script:pnpDevices.Count -eq 6 -and $script:cimDrivers.Count -eq 6) '現場擷取包含六個 Code 28 裝置的屬性、PnP 與已簽驅動資料'
Assert (@($script:pnpDevices|Where-Object {$_.Status -eq 'Error' -and [int]$_.Problem -eq 28}).Count -eq 6) '六個裝置皆為 Error 與 Problem Code 28'
Assert (@($shape.Devices|Where-Object {$_.DriverInfPath.Type -eq 'Empty' -and -not $_.DriverInfPath.HasDataMember}).Count -eq 6) '現場 DriverInfPath 屬性皆為 Empty 且沒有 Data 成員'
$liveMainReasons=@($live.Main|ForEach-Object Reason)
Assert (@($liveMainReasons|Where-Object {$_ -like '*目標驅動狀態屬性讀取失敗*'}).Count -ge 4) '現場未修版的症狀是目標驅動狀態屬性讀取失敗'
$build=[int]([version]$live.Build).Build
$devices=@(Get-SetupDriverDeviceInventory -Targets $targets)
$perTarget=@(foreach($t in $targets){$p=Get-SetupDriverTargetPlan -Target $t -Devices $devices -Build $build -Architecture amd64;,@($p)})
$plans=@($perTarget|ForEach-Object {$_})
$planReasons=@($plans|ForEach-Object {[string]$_.Reason})
Assert (@($planReasons|Where-Object {$_ -like '*目標驅動狀態屬性讀取失敗*'}).Count -eq 0) '沒有驅動的 Code 28 裝置不再誤判為屬性讀取失敗'
$actual=@(foreach($p in $perTarget){'{0}|{1}'-f ([string]$p.Status),([string]$p.Reason)})
$expected=@(foreach($p in $live.Fix374){'{0}|{1}'-f $p.Status,$p.Reason})
# 複合目標在現場還比對到其他健康的 A127 同族裝置；基準擷取沒有這些裝置的屬性，因此只逐一比對單一硬體 ID 的目標。
$single=@(0..($expected.Count-1)|Where-Object {$live.Fix374[$_].Status -notmatch ' '})
Assert ($single.Count -eq 4 -and (($single|ForEach-Object {$actual[$_]}) -join "`n") -ceq (($single|ForEach-Object {$expected[$_]}) -join "`n")) '單一硬體 ID 目標的計畫狀態與原因和現場修正版唯讀結果一致'
Assert (@($plans|Where-Object {([string]$_.Status) -like '*UpdateRequired*'}).Count -ge 4) '四個目標硬體皆有要求安裝已核相符驅動的計畫'
