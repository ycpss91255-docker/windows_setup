#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Microsoft.PowerShell.Utility\Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 重放現場順序：第 4 階段 mDNS 以去識別的 callback-schema 失敗，重開後由 -AfterRestart 重試同一模組。
# SSH 入口、連線資訊程式庫與 AfterRestart 使用真實程式；系統指令、mDNS、hosts 安裝與總驗收為替身，不改動本機。
. (Join-Path $root 'core/after_restart_library.ps1')
$scene=Get-Content -LiteralPath (Join-Path $root 'test/powershell/fixtures/nuc_mdns_failure_20261125/failure_fixture.json') -Raw -Encoding UTF8|ConvertFrom-Json
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('ssh_mdns_hosts_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$utf8=[Text.UTF8Encoding]::new($true)
function Write-Fixture([string]$Name,[string]$Text){[IO.File]::WriteAllText((Join-Path $fixture $Name),$Text,$utf8)}
$entry=[IO.File]::ReadAllText((Join-Path $root 'modules/ssh/apply_ssh_settings.ps1'))
$entryCopy=[regex]::Replace($entry,'(?m)^#Requires -RunAsAdministrator\r?\n','')
Assert ($entryCopy -cne $entry -and $entryCopy -cnotmatch 'RunAsAdministrator') '只移除入口副本的管理員宣告'
Write-Fixture 'apply_ssh_settings.ps1' $entryCopy
Copy-Item -LiteralPath (Join-Path $root 'modules/ssh/connection_info_library.ps1'),(Join-Path $root 'core/configuration_library.ps1') -Destination $fixture
Write-Fixture 'mdns_library.ps1' 'function Get-SetupMdnsStatus {param($ComputerName) throw "fixture mDNS observation"}'
Write-Fixture 'ssh_firewall.ps1' 'function Get-SetupSSHFirewallStatus {[pscustomobject]@{Passed=$true;Detail="fixture"}}'
foreach($name in @('initialize_ssh_client.ps1','apply_lan_ping_settings.ps1','install_windows_updates.ps1','apply_debloat.ps1','apply_copilot_settings.ps1','remove_setup_residue.ps1','desktop_icon_layout.ps1')){Write-Fixture $name 'param($Mode)'}
Write-Fixture 'apply_mdns_settings.ps1' @'
param([switch]$VerifyOnly)
if(-not $VerifyOnly){$global:sshSceneFixture.Mdns++}
throw ('mDNS原生公告尚未確認：Failed '+$global:sshSceneFixture.SafeError)
'@
Write-Fixture 'apply_hosts_sync.ps1' @'
param([switch]$VerifyOnly)
if($VerifyOnly){if(-not $global:sshSceneFixture.HostsInstalled){throw 'CustomHostsSync 尚未安裝。'};return}
$global:sshSceneFixture.Hosts++
if($global:sshSceneFixture.HostsFail){throw 'fixture hosts failure'}
$global:sshSceneFixture.HostsInstalled=$true
'@
# 兩個檢查項目的名稱與 VerifyOnly 呼叫方式沿用總驗收；其他項目不在本案範圍。
Write-Fixture 'verify_only.ps1' @'
param($VerificationRunId)
$checks=@()
foreach($item in @(@{Name='mDNS 持續公告';File='apply_mdns_settings.ps1'},@{Name='依網路自動匯入框架';File='apply_hosts_sync.ps1'})){
 try{& (Join-Path $PSScriptRoot $item.File) -VerifyOnly|Out-Null;$checks+=@{Name=$item.Name;Passed=$true;Status='Passed';Detail=''}}catch{$checks+=@{Name=$item.Name;Passed=$false;Status='Failed';Detail=$_.Exception.Message}}
}
@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Passed=(@($checks|Where-Object {-not $_.Passed}).Count -eq 0);Checks=$checks}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $PSScriptRoot 'Verification-Result.json') -Encoding UTF8
'@
function Resolve-NucPath {param($Name) Join-Path $fixture $Name}
function Resolve-NucModuleName {param($Name) $Name}
function Get-SetupModuleDecision {param($Module,$Hardware) [pscustomobject]@{Applicable=$true;Status='Applicable';Reason='fixture'}}
function Get-ItemProperty {param($Path,$ErrorAction) [pscustomobject]@{StartLayoutFile=''}}
function Get-WindowsCapability {param([switch]$Online,$Name) [pscustomobject]@{State='Installed'}}
function Add-WindowsCapability {param([switch]$Online,$Name) throw 'unsafe capability install'}
function Set-Service {param($Name,$StartupType)}
function Start-Service {param($Name)}
function Get-Service {param($Name) [pscustomobject]@{Status='Running'}}
function Get-NetFirewallRule {param($Name,$ErrorAction) [pscustomobject]@{Name=$Name}}
function Set-NetFirewallRule {param($Name,$Protocol,$LocalPort,$Enabled,$Direction,$Action,$Profile,$RemoteAddress)}
function New-NetFirewallRule {throw 'unsafe firewall rule creation'}
function Get-NetIPAddress {param($AddressFamily,$ErrorAction) [pscustomobject]@{IPAddress='192.0.2.42';AddressState='Preferred'}}
function Write-Host {param($Object,$ForegroundColor) if($global:sshSceneFixture){$global:sshSceneFixture.Lines.Add([string]$Object)}}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
try{
 foreach($mode in @('mdns','both')){
  $global:sshSceneFixture=@{SafeError=[string]$scene.ExpectedSafeError;Mdns=0;Hosts=0;HostsInstalled=$false;HostsFail=($mode -eq 'both');Lines=[Collections.Generic.List[string]]::new()}
  Remove-Item -LiteralPath (Join-Path $fixture 'Verification-Result.json'),(Join-Path $fixture 'Acceptance-Result.json') -Force -ErrorAction SilentlyContinue
  # 首次執行：沿用 configuration_library 的階段紀錄方式（只留 Exception.Message）。
  $stage='';try{& (Resolve-NucPath 'apply_ssh_settings.ps1')}catch{$stage=$_.Exception.Message}
  $firstHosts=$global:sshSceneFixture.Hosts
  @{Computer=$env:COMPUTERNAME;UserSID=$sid;FailedModules=@('apply_ssh_settings.ps1');StageErrors=@($stage);Success=$false;PendingModules=@()}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $fixture 'Setup-Result.json') -Encoding UTF8
  $caught='';try{Invoke-SetupAfterRestart -Hardware ([pscustomobject]@{}) -DriverPackagePath '' -SkippedModules @()}catch{$caught=$_.Exception.Message}
  $saved=Get-Content -LiteralPath (Join-Path $fixture 'Setup-Result.json') -Raw|ConvertFrom-Json
  $acceptance=Get-Content -LiteralPath (Join-Path $fixture 'Acceptance-Result.json') -Raw|ConvertFrom-Json
  $errors=@($acceptance.Errors) -join ' ';$failedNames=@($acceptance.FailedChecks|ForEach-Object {$_.Name})
  Assert ($global:sshSceneFixture.Mdns -eq 2 -and $stage.Contains('callback-schema') -and $errors.Contains('callback-schema') -and $caught) ($mode+'：首次與 AfterRestart 都如實回報 mDNS callback-schema 失敗')
  Assert ($firstHosts -eq 1) ($mode+'：首次執行 mDNS 失敗時仍執行 hosts 同步')
  Assert ($global:sshSceneFixture.Hosts -eq 2) ($mode+'：AfterRestart 重試 mDNS 仍失敗時仍執行 hosts 同步')
  Assert ($saved.FailedModules -contains 'apply_ssh_settings.ps1' -and -not $saved.Success -and -not $acceptance.Success -and $failedNames -contains 'mDNS 持續公告') ($mode+'：SSH 模組仍列為失敗可續跑，驗收仍因 mDNS 未通過')
  Assert (@($global:sshSceneFixture.Lines|Where-Object {$_ -like 'IPv4：192.0.2.42*'}).Count -eq 2 -and @($global:sshSceneFixture.Lines|Where-Object {$_ -like 'SSH 登入帳號*'}).Count -eq 0) ($mode+'：mDNS 失敗時只提供直接 IPv4 指引')
  if($mode -eq 'mdns'){
   Assert ($failedNames -notcontains '依網路自動匯入框架') 'mDNS 失敗不再連帶使 hosts 自動匯入框架驗收未通過'
   Assert (-not $errors.Contains('hosts') -and -not $stage.Contains('依網路自動匯入框架')) '只有 mDNS 失敗時錯誤不提 hosts 同步'
  }else{
   Assert ($stage.Contains('fixture hosts failure') -and $errors.Contains('fixture hosts failure') -and $failedNames -contains '依網路自動匯入框架') 'hosts 同步自己失敗時與 mDNS 錯誤同時保留在階段與驗收紀錄'
  }
 }
}finally{if($fixture.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $fixture -Recurse -Force};Remove-Variable sshSceneFixture -Scope Global -ErrorAction SilentlyContinue}
