#Requires -Version 5.1
# Read-only profile classification; it does not prove an endpoint or service works.
function Get-SetupNetworkObservation {
 param([scriptblock]$ReadProfiles={Get-NetConnectionProfile -ErrorAction Stop})
 try {$profiles=@(& $ReadProfiles)} catch {return [pscustomobject]@{Status='Unknown'}}
 if($profiles.Count -eq 0){return [pscustomobject]@{Status='Unknown'}}
 $local=$false;$unknown=$false
 foreach($profile in $profiles){
  foreach($name in @('IPv4Connectivity','IPv6Connectivity')){
   if($null -eq $profile -or $null -eq $profile.PSObject.Properties[$name]){$unknown=$true;continue}
   try{$value=[string]$profile.$name}catch{$unknown=$true;continue}
   if($value -ceq 'Internet'){return [pscustomobject]@{Status='Internet'}}
   if($value -cin @('LocalNetwork','Subnet')){$local=$true}
   elseif($value -cnotin @('Disconnected','NoTraffic')){$unknown=$true}
  }
 }
 $status=if($local){'Local'}elseif($unknown){'Unknown'}else{'Offline'}
 [pscustomobject]@{Status=$status}
}
function Get-SetupNetworkPreflightMessage {
 param([Parameter(Mandatory=$true)]$Observation)
 switch -CaseSensitive ($Observation.Status){
  'Internet' {'網路：已連線，繼續。'}
  'Local' {'網路：只連到區域網路，無法確認能不能上網。'}
  'Offline' {'網路：沒有偵測到網路連線。'}
  default {'網路：無法判斷目前有沒有連線。'}
 }
 if($Observation.Status -cne 'Internet'){'影響：Windows 更新與線上下載 OpenSSH 可能失敗；其他設定可以繼續。'}
}
function Show-SetupNetworkPreflight {
 param([bool]$Interactive=$false)
 $observation=Get-SetupNetworkObservation
 foreach($line in @(Get-SetupNetworkPreflightMessage -Observation $observation)){Write-Host $line}
 if(-not $Interactive -or $observation.Status -ceq 'Internet'){return}
 while($true){
  try{$choice=Read-Host '接上網路後輸入 R 重新檢查；不接網路就按 Enter 繼續'}catch{return}
  if($null -eq $choice -or ([string]$choice).Trim() -eq ''){return}
  if(([string]$choice).Trim() -ieq 'R'){
   $observation=Get-SetupNetworkObservation
   foreach($line in @(Get-SetupNetworkPreflightMessage -Observation $observation)){Write-Host $line}
   if($observation.Status -ceq 'Internet'){return}
  }else{Write-Host '請輸入 R 重新檢查，或直接按 Enter 繼續。'}
 }
}
