#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/ssh/mdns_publisher_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 重放 2026-11-25 NUC 實測的未修原生失敗：外層為 PowerShell 包裝例外，內層為原生訊息。資料見 fixtures/nuc_mdns_failure_20261125/readme.md
$fx=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../fixtures/nuc_mdns_failure_20261125/failure_fixture.json') -Raw -Encoding UTF8|ConvertFrom-Json
function Write-SetupMdnsPublisherState {param($Path,$Context,$Facts,$State) $script:captured=[pscustomobject]@{Status=$State.Status;Ready=$State.Ready;Error=$State.Error}}
$facts=[pscustomobject]@{ComputerName='FIXTURE';Addresses=@([pscustomobject]@{InterfaceIndex=1;IPAddress='192.0.2.9'});PolicyAllowed=$true;DnsClientRunning=$true;SshdRunning=$true;DnsClientProcessId=1}
foreach($case in @(@{Name='英文外層';Outer=[string]$fx.WrappedEnglish},@{Name='中文外層';Outer=[string]$fx.WrappedChinese})){
 $script:failure=[Management.Automation.MethodInvocationException]::new($case.Outer,[InvalidOperationException]::new([string]$fx.NativeMessage))
 function New-SetupMdnsNativeRegistration {param($CodeRoot,$Row) throw $script:failure}
 $state=[pscustomobject]@{Leases=@();Fingerprint='';Plans=@();Ready=$false;Status='Starting';Error=''};$script:captured=$null;$threw=$false;$exposed=''
 try{Invoke-SetupMdnsPublisherCycle -State $state -Context @{} -Facts $facts -CodeRoot 'fixture' -StatusPath 'fixture'}catch{$threw=$true;$exposed=$_.Exception.Message}
 Assert ($threw -and $script:captured.Status -ceq 'Failed' -and -not $script:captured.Ready) ($case.Name+'：註冊失敗時仍如實失敗')
 Assert ($script:captured.Error -ceq [string]$fx.ExpectedSafeError) ($case.Name+'：狀態只保留固定的去識別原生階段，不保留外層包裝文字')
 Assert ($exposed -match [regex]::Escape([string]$fx.ExpectedSafeError) -and $exposed -notmatch 'Exception calling|引數呼叫') ($case.Name+'：對外錯誤訊息不含外層包裝文字')
}
