#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/hardware.ps1')
. (Join-Path $root 'modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 合成目標：宣告式命名INF與真正綁定的擁有者共用同一硬體ID，但供應商字串及版本線不同。
$naming=[pscustomobject]@{Id='naming';InfPath='naming.inf';HardwareIds=@('PCI\VEN_8086&DEV_A160','ACPI\INT345D');Provider='INTEL';ProviderAliases=@();DriverVersion='10.1.6.2';MinimumBuild=10240;Architecture='amd64';NamingOnly=$true}
$owner=[pscustomobject]@{Id='owner';InfPath='owner.inf';HardwareIds=@('PCI\VEN_8086&DEV_A160','PCI\VEN_8086&DEV_A161');Provider='Intel Corporation';ProviderAliases=@();DriverVersion='30.100.1914.3';MinimumBuild=10240;Architecture='amd64'}
$device=[pscustomobject]@{InstanceId='PCI\FIXTURE_A160';HardwareIds=@('PCI\VEN_8086&DEV_A160');DriverProvider='Intel Corporation';DriverVersion='30.100.1914.3';Status='OK';DriverSigned=$true}
function Plan {param($Target=$naming,$Devices=@($device),$Owners=@($owner,$naming)) @(Get-SetupDriverTargetPlan -Target $Target -Devices $Devices -Build 22621 -Architecture amd64 -OwnerTargets $Owners)}
$plain=$naming.PSObject.Copy();$plain.PSObject.Properties.Remove('NamingOnly')
Assert ((Plan $plain)[0].Status -eq 'Unverified') '未標非綁定目標時供應商或版本無法比較仍維持Unverified'
Assert ((Plan)[0].Status -eq 'Current') '同硬體ID的擁有者已綁定且版本供應商相符時宣告式目標通過'
Assert ((Plan)[0].InstanceId -eq $device.InstanceId) '宣告式目標結果仍指向實際裝置'
Assert ((Plan -Owners @())[0].Status -eq 'Unverified') '沒有其他目標可作擁有者時維持Unverified'
Assert ((Plan -Owners @($naming))[0].Status -eq 'Unverified') '宣告式目標不可以自己當擁有者'
$other=$owner.PSObject.Copy();$other.HardwareIds=@('PCI\VEN_8086&DEV_A161')
Assert ((Plan -Owners @($other,$naming))[0].Status -eq 'Unverified') '擁有者未宣告該裝置的硬體ID時不可通過'
$device.DriverProvider='Microsoft'
Assert ((Plan)[0].Status -eq 'Unverified') '裝置仍綁定Windows內建驅動時維持Unverified'
$device.DriverProvider='Unknown Vendor'
Assert ((Plan)[0].Status -eq 'Unverified') '擁有者供應商不符時不放寬比較'
$device.DriverProvider='Intel Corporation';$device.DriverVersion='30.100.1816.3'
Assert ((Plan)[0].Status -eq 'Unverified') '裝置版本低於擁有者目標時不可通過'
$device.DriverVersion='30.100.1914.3';$device.Status='Error'
Assert ((Plan)[0].Status -eq 'Unverified') '裝置狀態異常時不可通過'
$device.Status='OK';$device.DriverSigned=$false
Assert ((Plan)[0].Status -eq 'Unverified') '驅動未確認簽章時不可通過'
$device.DriverSigned=$true;$device.DriverVersion='30.100.1914.4'
Assert ((Plan)[0].Status -eq 'Current') '擁有者為較新版本時宣告式目標通過'
$device.DriverVersion='30.100.1914.3'
Assert ((Plan -Devices @())[0].Status -eq 'Absent') '裝置不存在仍列Absent'
# 安裝流程不得把宣告式目標當成可安裝驅動。
$script:installCalls=0
function Assert-SetupDriverTargetIntegrity {param($Target,$Root) $true}
function Get-SetupDriverDeviceInventory {param($Targets) @($device)}
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath,[switch]$StageOnly) $script:installCalls++;[pscustomobject]@{ExitCode=0}}
$device.DriverProvider='Microsoft'
$outcome=Invoke-SetupDriverTarget -Target $naming -Root 'unused' -Build 22621 -Architecture amd64 -LogPath 'unused.log'
Assert ($script:installCalls -eq 0) '宣告式目標不執行原生安裝'
Assert (@($outcome.Failures).Count -eq 0) '宣告式目標在安裝階段不產生失敗，留待最終核對'
Assert (@($outcome.Results|Where-Object Status -eq 'UpdateRequired').Count -eq 0) '宣告式目標不回報需要更新'
# 清單契約。
function New-Manifest {param($Flag) $target=@{Id='naming';InfPath='naming.inf';DriverVersion='10.1.6.2';Provider='INTEL';Architecture='amd64';MinimumBuild=10240;HardwareIds=@('PCI\VEN_8086&DEV_A160')};if($null -ne $Flag){$target.NamingOnly=$Flag};@{SchemaVersion=2;Packages=@(@{Id='chipset';File='chipset.zip';SHA256=('A'*64);PackageVersion='10.1.19376.8374';SourceUrl='https://www.asus.com/driver';Drivers=@($target)})}|ConvertTo-Json -Depth 10|ConvertFrom-Json}
$ok=$true;try{$null=Get-SetupDriverManifestEntries -Manifest (New-Manifest $true)}catch{$ok=$false}
Assert $ok '清單接受布林true的NamingOnly'
foreach($bad in @('yes',1,$false)){$rejected=$false;try{$null=Get-SetupDriverManifestEntries -Manifest (New-Manifest $bad)}catch{$rejected=$true};Assert $rejected ('清單拒絕非true的NamingOnly：'+$bad)}
# 真實清單與已查證的NUC8綁定證據。
$manifest=Get-Content -LiteralPath (Join-Path $root 'drivers/nuc8i7hvk_hnk/manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$entries=@(Get-SetupDriverManifestEntries -Manifest $manifest)
$all=@($entries|ForEach-Object Drivers)
$lpss=@($all|Where-Object {$_.InfPath -like '*/SunrisePoint-HSystemLPSS.inf' -and $_.InfPath -like '*Windows10-x64*'})
Assert ($lpss.Count -eq 1 -and $lpss[0].NamingOnly -eq $true) '真實清單把LPSS命名INF標為非綁定目標'
Assert (@($all|Where-Object {$_.NamingOnly -eq $true}).Count -eq 1) '真實清單只標記LPSS命名INF'
$evidence=@(
 @{Id='PCI\VEN_8086&DEV_A160\x';Hw='PCI\VEN_8086&DEV_A160'},@{Id='PCI\VEN_8086&DEV_A161\x';Hw='PCI\VEN_8086&DEV_A161'},@{Id='PCI\VEN_8086&DEV_A162\x';Hw='PCI\VEN_8086&DEV_A162'},@{Id='ACPI\INT345D\x';Hw='ACPI\INT345D'}
)|ForEach-Object {[pscustomobject]@{InstanceId=$_.Id;HardwareIds=@($_.Hw);DriverProvider='Intel Corporation';DriverVersion='30.100.1914.3';Status='OK';DriverSigned=$true}}
$plans=@(Get-SetupDriverTargetPlan -Target $lpss[0] -Devices $evidence -Build 26100 -Architecture amd64 -OwnerTargets $all)
Assert ($plans.Count -eq 4 -and @($plans|Where-Object Status -ne 'Current').Count -eq 0) '實機證據的四個LPSS裝置在Serial IO已綁定時全部通過'
$unbound=@($evidence|ForEach-Object {$c=$_.PSObject.Copy();$c.DriverProvider='Microsoft';$c.DriverVersion='30.100.1816.3';$c})
$plans=@(Get-SetupDriverTargetPlan -Target $lpss[0] -Devices $unbound -Build 26100 -Architecture amd64 -OwnerTargets $all)
Assert (@($plans|Where-Object Status -ne 'Unverified').Count -eq 0) '真實清單在Serial IO尚未綁定時維持Unverified'
