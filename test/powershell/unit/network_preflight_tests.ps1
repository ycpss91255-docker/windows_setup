#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$library=Join-Path $root 'core/network_preflight_library.ps1'
if(Test-Path $library){. $library}
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Get-SetupNetworkObservation -ErrorAction SilentlyContinue)) '網路唯讀觀察介面存在'
function P($v4,$v6){[pscustomobject]@{IPv4Connectivity=$v4;IPv6Connectivity=$v6}}
foreach($case in @(@{p=@((P 'Internet' 'Disconnected'));s='Internet'},@{p=@((P 'LocalNetwork' 'Disconnected'));s='Local'},@{p=@((P 'Subnet' 'NoTraffic'));s='Local'},@{p=@((P 'Disconnected' 'NoTraffic'));s='Offline'},@{p=@();s='Unknown'},@{p=@((P 'Other' 'Disconnected'));s='Unknown'},@{p=@((P 'Disconnected' 'NoTraffic'),(P 'Internet' 'NoTraffic'));s='Internet'})){$r=Get-SetupNetworkObservation -ReadProfiles {return $case.p};Assert ($r.Status -ceq $case.s) ('連線分類 '+$case.s)}
$r=Get-SetupNetworkObservation -ReadProfiles {throw 'fixture'};Assert ($r.Status -ceq 'Unknown') '讀取失敗為未知'
foreach($status in @('Offline','Local','Unknown','Internet')){$text=@(Get-SetupNetworkPreflightMessage -Observation ([pscustomobject]@{Status=$status})) -join ' ';Assert ($text -notmatch '0x8024402C' -and $text -notmatch 'DNS' -and $text -notmatch 'apply_ssh_settings' -and $text -notmatch 'install_windows_updates') ('提示不再夾帶疑難排解與單獨重試指令 '+$status)}
$script:count=0;$reader={ $script:count++;if($script:count -eq 1){return @((P 'Disconnected' 'NoTraffic'))};return @((P 'Internet' 'NoTraffic')) };Assert ((Get-SetupNetworkObservation -ReadProfiles $reader).Status -eq 'Offline' -and (Get-SetupNetworkObservation -ReadProfiles $reader).Status -eq 'Internet') '重新讀取不沿用舊狀態'
$r=Get-SetupNetworkObservation -ReadProfiles {return @((P 'LocalNetwork' 'Other'))};Assert ($r.Status -ceq 'Local') '已知區域網路不因另一狀態未知而遺失'
$lines=@(Get-SetupNetworkPreflightMessage -Observation $r);Assert (($lines -join ' ') -match '區域網路' -and ($lines -join ' ') -notmatch '已連線') '部分未知時不冒稱網際網路可用'
Set-StrictMode -Version Latest
try{$r=Get-SetupNetworkObservation -ReadProfiles {return @([pscustomobject]@{IPv4Connectivity='LocalNetwork'})};Assert ($r.Status -ceq 'Local') '嚴格模式缺欄位仍維持唯讀提示'}finally{Set-StrictMode -Off}
