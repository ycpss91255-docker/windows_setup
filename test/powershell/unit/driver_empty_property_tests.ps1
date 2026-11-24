#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$manifest=Get-Content -LiteralPath (Join-Path $root 'drivers/nuc8i7hvk_hnk/manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$script:ids=@('PCI\VEN_8086&DEV_1911','PCI\VEN_8086&DEV_A127','PCI\VEN_8086&DEV_A131','ACPI\INT3515')
$targets=@($manifest.Packages|ForEach-Object Drivers|Where-Object {@($_.HardwareIds|Where-Object {$_ -in $script:ids}).Count})
# Real Get-PnpDeviceProperty returns an object of Type 'Empty' WITHOUT a Data member when a device has no value.
$script:emptyKeys=@('DEVPKEY_Device_DriverInfPath');$script:brokenKey=''
function Get-PnpDevice {param([switch]$PresentOnly,$ErrorAction) foreach($id in $script:ids){[pscustomobject]@{InstanceId=($id+'\fixture');Status='Error';FriendlyName='Code28 fixture';Class='System'}}}
function Get-CimInstance {param($ClassName,$ErrorAction) @()}
function Get-PnpDeviceProperty {
 param($InstanceId,$KeyName,$ErrorAction)
 if($KeyName -eq $script:brokenKey){return [pscustomobject]@{InstanceId=$InstanceId;KeyName=$KeyName;Type='String'}}
 if($KeyName -in $script:emptyKeys){return [pscustomobject]@{InstanceId=$InstanceId;KeyName=$KeyName;Type='Empty'}}
 $data=switch($KeyName){
  'DEVPKEY_Device_HardwareIds' {@($InstanceId.Substring(0,$InstanceId.LastIndexOf('\')))}
  'DEVPKEY_Device_CompatibleIds' {@()}
  'DEVPKEY_Device_ProblemCode' {28}
  default{throw ('unexpected native property '+$KeyName)}
 }
 [pscustomobject]@{InstanceId=$InstanceId;KeyName=$KeyName;Type='UInt32';Data=$data}
}
function Plans {$devices=@(Get-SetupDriverDeviceInventory -Targets $targets);foreach($t in $targets){Get-SetupDriverTargetPlan -Target $t -Devices $devices -Build 26200 -Architecture amd64}}
$plans=@(Plans)
Assert ($plans.Count -eq 5 -and @($plans|Where-Object Status -eq 'UpdateRequired').Count -eq 5) '真實Code28裝置的DriverInfPath為Empty型別且無Data成員時視為沒有驅動並進入安裝計畫'
$script:emptyKeys=@();$script:brokenKey='DEVPKEY_Device_ProblemCode'
Assert (@(@(Plans)|Where-Object Status -eq 'UpdateRequired').Count -eq 0) 'ProblemCode缺少Data成員仍是讀取失敗而不安裝'
$script:brokenKey='DEVPKEY_Device_DriverInfPath'
Assert (@(@(Plans)|Where-Object Status -eq 'Unverified').Count -eq 5) 'DriverInfPath型別不是Empty且缺Data成員時仍是讀取失敗'
