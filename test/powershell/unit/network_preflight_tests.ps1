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
foreach($status in @('Offline','Local','Unknown','Internet')){$lines=@(Get-SetupNetworkPreflightMessage -Observation ([pscustomobject]@{Status=$status}));$text=$lines -join ' ';Assert ($text -match 'SSH' -and $text -match 'Windows Update' -and $text -match '來源') ('提示如實提及能力 '+$status);if($status -ne 'Internet'){Assert ($text -match '重試' -and $text -match '乙太網路' -and $text -match 'Wi-Fi') '無網路或未知顯示安全重試'}else{Assert ($text -match '不保證') '網際網路分類不保證來源可用'}}
$script:count=0;$reader={ $script:count++;if($script:count -eq 1){return @((P 'Disconnected' 'NoTraffic'))};return @((P 'Internet' 'NoTraffic')) };Assert ((Get-SetupNetworkObservation -ReadProfiles $reader).Status -eq 'Offline' -and (Get-SetupNetworkObservation -ReadProfiles $reader).Status -eq 'Internet') '重新讀取不沿用舊狀態'
$r=Get-SetupNetworkObservation -ReadProfiles {return @((P 'LocalNetwork' 'Other'))};Assert ($r.Status -ceq 'Local') '已知區域網路不因另一狀態未知而遺失'
$lines=@(Get-SetupNetworkPreflightMessage -Observation $r);Assert (($lines -join ' ') -match '網際網路未確認') '部分未知時不冒稱網際網路可用'
Set-StrictMode -Version Latest
try{$r=Get-SetupNetworkObservation -ReadProfiles {return @([pscustomobject]@{IPv4Connectivity='LocalNetwork'})};Assert ($r.Status -ceq 'Local') '嚴格模式缺欄位仍維持唯讀提示'}finally{Set-StrictMode -Off}
foreach($status in @('Offline','Local','Unknown','Internet')){
 $text=@(Get-SetupNetworkPreflightMessage -Observation ([pscustomobject]@{Status=$status})) -join ' '
 Assert ($text -match 'DNS' -and $text -match '代理' -and $text -match '0x8024402C' -and $text -match '不保證') ('各狀態提供安全來源疑難指引 '+$status)
}

$internetText=@(Get-SetupNetworkPreflightMessage -Observation ([pscustomobject]@{Status='Internet'})) -join ' '
Assert ($internetText -match 'modules\\ssh\\apply_ssh_settings\.cmd' -and $internetText -match 'modules\\updates\\install_windows_updates\.cmd') '網際網路分類仍提供各單一模組重試入口'
