#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/ssh/mdns_publisher_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$cases=@(
 @{Inner=[InvalidOperationException]::new('Native registration callback schema differs or has no instance.');Expected='callback-schema'},
 @{Inner=[InvalidOperationException]::new('Native registration callback failed: 123');Expected='callback-status=123'},
 @{Inner=[TimeoutException]::new('Native mDNS registration callback timed out.');Expected='registration-timeout'},
 @{Inner=[InvalidOperationException]::new('Native request did not return DNS_REQUEST_PENDING: 1722');Expected='request-status=1722'},
 @{Inner=[Exception]::new('Native callback read failed: PRIVATE C:\secret');Expected='callback-read-failed'},
 @{Inner=[Exception]::new('PRIVATE C:\Users\secret 192.0.2.1');Expected='unknown'}
)
foreach($case in $cases){
 $script:failure=[Management.Automation.MethodInvocationException]::new('outer PRIVATE',$case.Inner)
 function New-SetupMdnsNativeRegistration {param($CodeRoot,$Row) throw $script:failure}
 function Write-SetupMdnsPublisherState {param($Path,$Context,$Facts,$State) $script:captured=[pscustomobject]@{Status=$State.Status;Ready=$State.Ready;Error=$State.Error}}
 $facts=[pscustomobject]@{ComputerName='FIXTURE';Addresses=@([pscustomobject]@{InterfaceIndex=1;IPAddress='192.0.2.9'});PolicyAllowed=$true;DnsClientRunning=$true;SshdRunning=$true;DnsClientProcessId=1}
 $state=[pscustomobject]@{Leases=@();Fingerprint='';Plans=@();Ready=$false;Status='Starting';Error=''};$script:captured=$null;$threw=$false;$exposed=''
 try{Invoke-SetupMdnsPublisherCycle -State $state -Context @{} -Facts $facts -CodeRoot 'fixture' -StatusPath 'fixture'}catch{$threw=$true;$exposed=$_.Exception.Message}
 Assert ($threw -and -not $script:captured.Ready -and $script:captured.Status -ceq 'Failed' -and $script:captured.Error -match [regex]::Escape($case.Expected) -and $script:captured.Error -notmatch 'PRIVATE|secret|192\.0\.2\.1' -and $exposed -notmatch 'PRIVATE|secret|192\.0\.2\.1') ('sanitized inner '+$case.Expected)
}

. (Join-Path $PSScriptRoot '../../../modules/ssh/connection_info_library.ps1')
$script:lines=@();$script:hostCalls=0;$failed=$false
try{Invoke-SetupSshMdnsAndInfo -Mdns {throw 'fixture mDNS failure'} -Hosts {$script:hostCalls++} -Info {@('IPv4：192.0.2.1；ssh fixture','PRIVATE host error')} -Write {param($line) $script:lines+=@($line)}}catch{$failed=$true}
Assert ($failed -and $script:hostCalls -eq 0 -and ($script:lines -join ' ') -match 'IPv4' -and ($script:lines -join ' ') -match 'ssh' -and ($script:lines -join ' ') -notmatch 'PRIVATE') 'SSH failure retains IPv4 guidance and failure'
$script:lines=@();$script:hostCalls=0
Invoke-SetupSshMdnsAndInfo -Mdns {} -Hosts {$script:hostCalls++} -Info {@('fixture-info')} -Write {param($line) $script:lines+=@($line)}
Assert ($script:hostCalls -eq 1 -and $script:lines[0] -ceq 'fixture-info') 'SSH successful path retains hosts and guidance'

$script:workerRun=[guid]::NewGuid().ToString('D');$script:workerRoot='C:\fixture'
function Get-SetupMdnsPaths {param($RunId) [pscustomobject]@{CodeRoot=$script:workerRoot;Status='fixture'}}
function Read-SetupMdnsContext {param($RunId) [pscustomobject]@{RunId=$RunId}}
function Read-SetupMdnsCurrent {[pscustomobject]@{RunId=$script:workerRun}}
$script:workerFacts=$facts
function Get-SetupMdnsPublisherFacts {return $script:workerFacts}
$script:failure=[Management.Automation.MethodInvocationException]::new('outer PRIVATE',[InvalidOperationException]::new('Native registration callback failed: 123'))
$script:captured=$null;$failed=$false
try{Invoke-SetupMdnsPublisherWorker -RunId $script:workerRun -CodeRoot $script:workerRoot}catch{$failed=$true}
Assert ($failed -and $script:captured.Status -ceq 'Failed' -and $script:captured.Error -ceq 'callback-status=123') 'worker preserves sanitized cycle diagnostic'
