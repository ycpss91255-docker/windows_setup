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
  'Internet' {'網路狀態：Windows 偵測到網際網路；不保證 Windows Update 或 OpenSSH 來源可用，也不保證 SSH 區域網路連線。'}
  'Local' {'網路狀態：Windows 偵測到區域網路，但網際網路未確認；SSH 可用性仍需確認，Windows Update 與未快取 OpenSSH 可能無法取得來源。'}
  'Offline' {'網路狀態：Windows 未偵測到連線；SSH 區域網路、Windows Update 與未快取 OpenSSH 來源可能無法使用。'}
  default {'網路狀態：未知；無法確認 SSH 區域網路、Windows Update 或未快取 OpenSSH 來源。'}
 }
 '網路分類不保證來源名稱可解析或服務可用；若 Windows Update 出現 0x8024402C，請核對 DNS 與代理設定、確認組織網路要求，修正後重試。不要自行停用安全設定。'
 if($Observation.Status -cne 'Internet'){
  '請確認 Wi-Fi 或乙太網路連線；需要時連線後重試。已快取元件與本機驅動仍依既有檢查處理；本提示不變更階段結果。'
  '若 SSH 或 Windows Update 階段失敗，連線後可分別執行 modules\ssh\apply_ssh_settings.cmd 或 modules\updates\install_windows_updates.cmd 重試該模組。'
 }
}
function Show-SetupNetworkPreflight {
 param([bool]$Interactive=$false)
 $observation=Get-SetupNetworkObservation
 foreach($line in @(Get-SetupNetworkPreflightMessage -Observation $observation)){Write-Host $line}
 if($Interactive){
  try{$choice=Read-Host '輸入 R 唯讀重檢網路一次；Enter 繼續（離線或本機包可繼續）'}catch{$choice=''}
  if($choice -ieq 'R'){
   $observation=Get-SetupNetworkObservation
   foreach($line in @(Get-SetupNetworkPreflightMessage -Observation $observation)){Write-Host $line}
  }
 }
}
