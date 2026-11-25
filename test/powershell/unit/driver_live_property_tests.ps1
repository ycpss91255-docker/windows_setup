#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 只替身原生 Get-PnpDeviceProperty，直接測 Get-SetupDriverLiveDriverProperty 本體
$script:mode='ok';$script:keys=@()
function Get-PnpDeviceProperty {
 param([string]$InstanceId,[string]$KeyName,$ErrorAction)
 $script:keys+=$KeyName
 switch($script:mode){
  'ok'{return [pscustomobject]@{KeyName=$KeyName;Data=$(if($KeyName -eq 'DEVPKEY_Device_DriverVersion'){'2.0.0.0'}else{'Vendor'})}}
  'emptyVersion'{return [pscustomobject]@{KeyName=$KeyName;Data=$(if($KeyName -eq 'DEVPKEY_Device_DriverVersion'){''}else{'Vendor'})}}
  'emptyProvider'{return [pscustomobject]@{KeyName=$KeyName;Data=$(if($KeyName -eq 'DEVPKEY_Device_DriverVersion'){'2.0.0.0'}else{$null})}}
  'noData'{return $null}
  'providerFails'{if($KeyName -eq 'DEVPKEY_Device_DriverProvider'){throw '讀取失敗'};return [pscustomobject]@{KeyName=$KeyName;Data='2.0.0.0'}}
  'missingDevice'{throw '找不到裝置'}
 }
}
$script:mode='ok'
$live=Get-SetupDriverLiveDriverProperty -InstanceId 'PCI\FIXTURE\1'
Assert ($live.DriverVersion -eq '2.0.0.0' -and $live.DriverProvider -eq 'Vendor') '讀到即時版本與提供者'
Assert ('DEVPKEY_Device_DriverVersion' -in $script:keys -and 'DEVPKEY_Device_DriverProvider' -in $script:keys) '須讀取 DriverVersion 與 DriverProvider 屬性'
foreach($mode in @('emptyVersion','emptyProvider','noData','providerFails','missingDevice')){
 $script:mode=$mode
 Assert ($null -eq (Get-SetupDriverLiveDriverProperty -InstanceId 'PCI\FIXTURE\1')) ('屬性空值或讀取失敗回傳 $null：'+$mode)
}
Write-Output 'driver live property test passed'
