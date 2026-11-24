#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
# 現場重放：fixture 是 NUC8 現場擷取的 Format-List 原文（去識別），只做文字解析，不手改型別與欄位。
$fixtureRoot=Join-Path $root 'test/fixtures/nuc_scene/driver_code28'
function Read-Records([string]$Name){
 $text=[IO.File]::ReadAllText((Join-Path $fixtureRoot $Name),[Text.Encoding]::UTF8)
 foreach($chunk in ($text -split '(?:\r?\n){2,}')){
  if(-not $chunk.Trim()){continue}
  $record=[ordered]@{};$last=''
  foreach($line in ($chunk -split '\r?\n')){
   if($line -match '^(\S+)\s*:\s?(.*)$'){$last=$Matches[1];$record[$last]=$Matches[2].TrimEnd()}
   elseif($last -and $line -match '^\s+(\S.*)$'){$record[$last]+=$Matches[1].TrimEnd()}
  }
  $record
 }
}
function ConvertTo-List([string]$Text){
 $inner=$Text.Trim().TrimStart('{').TrimEnd('}')
 @($inner -split ',\s*'|ForEach-Object {$_.Trim()}|Where-Object {$_ -and $_ -ne '...'})
}
# Get-PnpDeviceProperty 的真實輸出：Type 為 Empty 時 Format-List 沒有 Data 行，因此物件沒有 Data 成員。
$script:properties=@{}
foreach($r in Read-Records 'pnp_properties.excerpt.txt'){
 $o=[ordered]@{InstanceId=$r['InstanceId'];KeyName=$r['KeyName'];Type=$r['Type']}
 if($r.Contains('Data')){
  $o['Data']=switch($r['Type']){'StringList'{ConvertTo-List $r['Data']} 'UInt32'{[uint32]$r['Data']} default{$r['Data']}}
 }
 $script:properties[$r['InstanceId']+'|'+$r['KeyName']]=[pscustomobject]$o
}
$script:pnpDevices=@(foreach($r in Read-Records 'pnp_present.excerpt.txt'){
 [pscustomobject]@{InstanceId=$r['InstanceId'];Status=$r['Status'];FriendlyName=$(if($r['FriendlyName']){$r['FriendlyName']}else{$null});Class=$(if($r['Class']){$r['Class']}else{$null})}
})
$script:cimDrivers=@(foreach($r in Read-Records 'win32_pnpsigneddriver.excerpt.txt'){
 $o=[ordered]@{}
 foreach($key in 'DeviceID','DriverProviderName','DriverVersion','InfName','IsSigned','Signer'){$o[$key]=$(if($r[$key]){$r[$key]}else{$null})}
 [pscustomobject]$o
})
$parsedField=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $fixtureRoot 'driver_result.targets.excerpt.json'),[Text.Encoding]::UTF8))
$field=@($parsedField|ForEach-Object {$_})
function Get-PnpDevice {param([switch]$PresentOnly,$ErrorAction) $script:pnpDevices}
function Get-CimInstance {param($ClassName,$ErrorAction) if($ClassName -ne 'Win32_PnPSignedDriver'){throw 'unexpected class'};$script:cimDrivers}
function Get-PnpDeviceProperty {
 param($InstanceId,$KeyName,$ErrorAction)
 $key=$InstanceId+'|'+$KeyName
 if(-not $script:properties.ContainsKey($key)){throw ('現場沒有擷取此屬性 '+$key)}
 $script:properties[$key]
}
$manifest=Get-Content -LiteralPath (Join-Path $root 'drivers/nuc8i7hvk_hnk/manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$hardwareIds=@('PCI\VEN_8086&DEV_1911','PCI\VEN_8086&DEV_A127','PCI\VEN_8086&DEV_A131','ACPI\INT3515')
$targets=@($manifest.Packages|ForEach-Object Drivers|Where-Object {@($_.HardwareIds|Where-Object {$_ -in $hardwareIds}).Count})
Assert ($script:pnpDevices.Count -eq 4 -and $script:cimDrivers.Count -eq 4 -and $field.Count -ge 4) '現場擷取包含四個 Code 28 裝置的 PnP、已簽驅動與歷史結果'
$empty=@($script:properties.Values|Where-Object {$_.KeyName -eq 'DEVPKEY_Device_DriverInfPath'})
Assert ($empty.Count -eq 4 -and @($empty|Where-Object {$_.Type -eq 'Empty' -and -not $_.PSObject.Properties['Data']}).Count -eq 4) '現場 DriverInfPath 屬性為 Empty 且沒有 Data 成員'
$devices=@(Get-SetupDriverDeviceInventory -Targets $targets)
$plans=@(foreach($t in $targets){Get-SetupDriverTargetPlan -Target $t -Devices $devices -Build 26200 -Architecture amd64})
$fieldReasons=@($field|ForEach-Object Reason|Select-Object -Unique)
Assert ($fieldReasons.Count -ge 1 -and $fieldReasons -contains '目標驅動狀態屬性讀取失敗') '現場 driver_result.json 的症狀是目標驅動狀態屬性讀取失敗'
Assert (@($plans|Where-Object {$_.Reason -in $fieldReasons}).Count -eq 0) '重放現場資料不得再產生現場的屬性讀取失敗症狀'
Assert ($plans.Count -eq 5 -and @($plans|Where-Object Status -eq 'UpdateRequired').Count -eq 5) '現場四個無驅動 Code 28 裝置的五個目標都進入安裝計畫'
