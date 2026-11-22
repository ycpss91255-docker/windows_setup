#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/ssh/mdns_publisher_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# Count only nested if/loop/switch controls within this function, excluding try and scriptblock scopes.
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'modules/ssh/mdns_publisher_library.ps1'),[ref]$tokens,[ref]$errors)
$fn=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-SetupMdnsPublisherFacts'},$true))
Assert ($errors.Count -eq 0 -and $fn.Count -eq 1) 'mDNS facts function parses uniquely'
$controls=@('IfStatementAst','ForEachStatementAst','ForStatementAst','WhileStatementAst','DoWhileStatementAst','DoUntilStatementAst','SwitchStatementAst')
$max=0
foreach($node in $fn[0].FindAll({param($n) $n.GetType().Name -in $controls},$true)){
 $depth=1
 $parent=$node.Parent
 while($parent -and $parent -ne $fn[0]){
  if($parent -is [Management.Automation.Language.ScriptBlockExpressionAst] -or $parent -is [Management.Automation.Language.FunctionDefinitionAst]){
   $depth=0
   break
  }
  if($parent.GetType().Name -in $controls){$depth++}
  $parent=$parent.Parent
 }
 if($depth -gt $max){$max=$depth}
}
Assert ($max -le 3) 'mDNS facts control nesting stays within three levels'
$script:g=$null;$script:l=$null;$script:kind='DWord';$script:readFailure=$false;$script:serviceMissing=$false;$script:missingKey='';$script:policyCalls=@()
function Test-Path {
 param($LiteralPath,$ErrorAction)
 $which=if($LiteralPath -like '*Policies*'){'group'}else{'local'}
 $script:policyCalls+=@('test:'+ $which)
 if($script:readFailure){throw 'fixture denied policy read'}
 return ($which -cne $script:missingKey)
}
function Get-Item {
 param($LiteralPath,$ErrorAction)
 $which=if($LiteralPath -like '*Policies*'){'group'}else{'local'}
 $script:policyCalls+=@('get:'+ $which)
 $value=if($which -eq 'group'){$script:g}else{$script:l}
 $key=[pscustomobject]@{Value=$value;Kind=$script:kind;Which=$which}
 $key|Add-Member ScriptMethod GetValueNames {
  $script:policyCalls+=@('names:'+ $this.Which)
  if($null -ne $this.Value){'EnableMDNS'}
 }
 $key|Add-Member ScriptMethod GetValue {
  param($name)
  $script:policyCalls+=@('value:'+ $this.Which)
  $this.Value
 }
 $key|Add-Member ScriptMethod GetValueKind {
  param($name)
  $script:policyCalls+=@('kind:'+ $this.Which)
  $this.Kind
 }
 return $key
}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) if($script:serviceMissing){return $null};[pscustomobject]@{State='Running';ProcessId=42}}
function Get-NetIPInterface {param($ConnectionState,$ErrorAction) [pscustomobject]@{InterfaceIndex=7;AddressFamily='IPv4'}}
function Get-NetIPAddress {param($ErrorAction) @([pscustomobject]@{InterfaceIndex=7;AddressFamily='IPv4';IPAddress='192.0.2.9';AddressState='Preferred'},[pscustomobject]@{InterfaceIndex=8;AddressFamily='IPv4';IPAddress='192.0.2.10';AddressState='Preferred'},[pscustomobject]@{InterfaceIndex=7;AddressFamily='IPv4';IPAddress='192.0.2.11';AddressState='Tentative'})}
$f=Get-SetupMdnsPublisherFacts
Assert ($f.ComputerName -ceq [Environment]::MachineName -and $f.Addresses.Count -eq 1 -and $f.Addresses[0].IPAddress -ceq '192.0.2.9' -and $f.DnsClientRunning -and $f.SshdRunning) '真facts僅取目前機名/已連介面Preferred地址，不取斷線或Tentative'
$script:l=0;$f=Get-SetupMdnsPublisherFacts;Assert (-not $f.PolicyAllowed) '本機明確停用mDNS時保留原則拒絕公告'
$script:g=1;$f=Get-SetupMdnsPublisherFacts;Assert $f.PolicyAllowed '管理EnableMDNS1優先，未寫任何政策'
$script:g=0;$f=Get-SetupMdnsPublisherFacts;Assert (-not $f.PolicyAllowed) '管理0沿用local0，不覆蓋本機禁用'
$script:l=1;$f=Get-SetupMdnsPublisherFacts;Assert $f.PolicyAllowed '管理0沿用local1'
$script:g=1;$script:l=0;$script:missingKey='group';$script:policyCalls=@();$f=Get-SetupMdnsPublisherFacts
Assert (-not $f.PolicyAllowed -and ($script:policyCalls -join ',') -ceq 'test:group,test:local,get:local,names:local,value:local,kind:local') 'missing group key skips only that key and preserves local read order'
$script:missingKey='local';$script:g=1;$script:l=0;$script:policyCalls=@();$f=Get-SetupMdnsPublisherFacts
Assert ($f.PolicyAllowed -and ($script:policyCalls -join ',') -ceq 'test:group,get:group,names:group,value:group,kind:group,test:local') 'missing local key preserves group result and skips local read'
$script:missingKey='';$script:g=$null;$script:l=0;$script:policyCalls=@();$f=Get-SetupMdnsPublisherFacts
Assert (-not $f.PolicyAllowed -and ($script:policyCalls -join ',') -ceq 'test:group,get:group,names:group,test:local,get:local,names:local,value:local,kind:local') 'missing group value skips its value reads and preserves local read order'
$script:g=1;$script:l=$null;$script:policyCalls=@();$f=Get-SetupMdnsPublisherFacts
Assert ($f.PolicyAllowed -and ($script:policyCalls -join ',') -ceq 'test:group,get:group,names:group,value:group,kind:group,test:local,get:local,names:local') 'present group and missing local value preserve order and precedence'
foreach($case in 'kind','unknown','denied','missing_service'){
 $script:g=$null;$script:l=1;$script:kind='DWord';$script:readFailure=$false;$script:serviceMissing=$false
 switch($case){kind{$script:kind='String'} unknown{$script:l=7} denied{$script:readFailure=$true} missing_service{$script:serviceMissing=$true}}
 $failed=$false;try{Get-SetupMdnsPublisherFacts|Out-Null}catch{$failed=$true};Assert $failed ('未知或讀失敗不能以預設允許公告 '+$case)
}