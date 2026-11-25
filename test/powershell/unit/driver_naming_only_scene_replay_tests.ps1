#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/hardware.ps1')
. (Join-Path $root 'modules/drivers/driver_installation_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 現場重放：裝置資料取自實際NUC的唯讀快照（見 fixtures/nuc_scene_lpss/readme.md），驅動包清單為NUC上實際使用的已發行清單。
$fixtures=Join-Path $root 'test/powershell/fixtures/nuc_scene_lpss'
function Read-FormatListBlocks([string]$File,[string]$First){
 $text=(Get-Content -LiteralPath (Join-Path $fixtures $File) -Raw -Encoding UTF8) -replace "`r`n","`n"
 foreach($raw in ($text -split "`n{2,}")){
  if([string]::IsNullOrWhiteSpace($raw)){continue}
  $row=[ordered]@{};$key=$null
  foreach($line in ($raw -split "`n")){
   if($line -match '^(\S+)\s*:\s?(.*)$'){$key=$Matches[1];$row[$key]=$Matches[2]}
   elseif($key -and $line -match '^\s+(\S.*)$'){$row[$key]+=$Matches[1]}
  }
  if($row.Contains($First)){[pscustomobject]$row}
 }
}
$present=@(Read-FormatListBlocks 'pnp_present.txt' 'InstanceId')
$signed=@(Read-FormatListBlocks 'win32_pnpsigneddriver.txt' 'DeviceID')
$props=@(Read-FormatListBlocks 'pnp_properties.txt' 'KeyName')
Assert ($present.Count -eq 5 -and $signed.Count -eq 5 -and $props.Count -eq 20) '現場快照取得五個Serial IO相關裝置的原始紀錄'
function Get-CimInstance {
 param($ClassName,$ErrorAction)
 if($ClassName -eq 'Win32_OperatingSystem'){return [pscustomobject]@{BuildNumber='26200'}}
 if($ClassName -ne 'Win32_PnPSignedDriver'){throw ('unexpected class '+$ClassName)}
 foreach($row in $signed){
  $isSigned=$null;if($row.IsSigned -ne ''){$isSigned=[System.Convert]::ToBoolean($row.IsSigned)}
  [pscustomobject]@{DeviceID=$row.DeviceID;InfName=$row.InfName;DriverProviderName=$row.DriverProviderName;DriverVersion=$row.DriverVersion;IsSigned=$isSigned;Signer=$row.Signer}
 }
}
function Get-PnpDevice {
 param([switch]$PresentOnly,$ErrorAction)
 foreach($row in $present){[pscustomobject]@{InstanceId=$row.InstanceId;FriendlyName=$row.FriendlyName;Class=$row.Class;Status=$row.Status}}
}
function Get-PnpDeviceProperty {
 param($InstanceId,$KeyName,$ErrorAction)
 $row=@($props|Where-Object {$_.InstanceId -eq $InstanceId -and $_.KeyName -eq $KeyName})
 if($row.Count -ne 1){throw ('快照沒有這個屬性：'+$KeyName)}
 $data=$row[0].Data
 if($row[0].Type -eq 'StringList'){$data=@(($data.Trim('{','}') -split ',\s*')|ForEach-Object {$_ -replace '\.\.\.$',''}|Where-Object {$_})}
 elseif($row[0].Type -eq 'UInt32'){$data=[uint32]$data}
 [pscustomobject]@{Data=$data}
}
# 驅動包清單：NUC上實際使用的是已發行驅動包 nuc8/manifest.json；它與目前repo清單只差 NamingOnly 這一行，由發行資產的雜湊證明。
$repoManifest=Join-Path $root 'drivers/nuc8i7hvk_hnk/manifest.json'
$bytes=[IO.File]::ReadAllBytes($repoManifest)
$text=[Text.Encoding]::UTF8.GetString($bytes)
$stripped=[regex]::Replace($text,'(?m)^[ \t]*"NamingOnly":\s*true,\r?\n','')
Assert ($stripped.Length -lt $text.Length) 'repo清單含宣告式標記而驅動包清單沒有'
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('naming_scene_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tmp)
try{
 $packageManifest=Join-Path $tmp 'manifest.json'
 [IO.File]::WriteAllBytes($packageManifest,[Text.UTF8Encoding]::new($false).GetBytes($stripped))
 $releases=Get-Content -LiteralPath (Join-Path $root 'script/release/driver_release_assets.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $pinned=@($releases.Releases|ForEach-Object {$_.Assets}|Where-Object {$_.ProfileId -eq 'nuc8i7hvk_hnk'}|ForEach-Object ManifestSHA256|Select-Object -Unique)
 $actual=(Get-FileHash -LiteralPath $packageManifest -Algorithm SHA256).Hash
 Assert ($pinned.Count -ge 1 -and $actual -in $pinned) '去除宣告式標記後的清單與已發行驅動包清單的SHA256逐位元相符'
 $archives=@{}
 foreach($entry in @(Get-SetupDriverManifestEntries -Manifest (Get-Content -LiteralPath $packageManifest -Raw -Encoding UTF8|ConvertFrom-Json))){$archives[$entry.File]=$entry.SHA256}
 function Get-FileHash {param($LiteralPath,$Algorithm,$ErrorAction) $name=(([IO.Path]::GetFullPath($LiteralPath)).Substring([IO.Path]::GetFullPath($tmp).Length+1)) -replace '\\','/';[pscustomobject]@{Hash=$archives[$name]}}
 function Get-SetupDriverExtensionInventory {[xml]'<pnputil />'}
 $result=Invoke-SetupDriverVerification -DriverRoot $tmp 6>$null
 $lpss=@($result.Targets|Where-Object {$_.InfPath -like '*SunrisePoint-HSystemLPSS.inf'})
 foreach($row in $lpss){Write-Host ('LPSS列 '+($row.InstanceId -replace '\\3&.*$','')+' '+$row.Status+' '+$row.Reason)}
 $bound=@($lpss|Where-Object {$_.InstanceId -match 'DEV_A160|DEV_A161|DEV_A162|INT345D'})
 $unbound=@($lpss|Where-Object {$_.InstanceId -match 'DEV_A127'})
 Assert ($bound.Count -eq 4) '現場有A160、A161、A162與INT345D四個已由Serial IO綁定的裝置'
 Assert (@($bound|Where-Object Status -ne 'Current').Count -eq 0) '現場四個Serial IO裝置在LPSS命名INF下必須判為Current'
 Assert ($unbound.Count -eq 1 -and $unbound[0].Status -eq 'Unverified') '現場A127沒有任何驅動，LPSS命名INF對它仍如實是Unverified'
 $serial=@($result.Targets|Where-Object {$_.InfPath -like '*iaLPSS2_I2C_SKL.inf'})
 Assert ($serial.Count -eq 3 -and @($serial|Where-Object Status -ne 'Current').Count -eq 0) '現場擁有者iaLPSS2_I2C_SKL.inf對三個I2C裝置維持Current'
}finally{Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
