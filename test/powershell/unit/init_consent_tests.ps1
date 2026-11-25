#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/init/init_entry_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Request-SetupInitConsent -ErrorAction SilentlyContinue)) '稽核準備同意函式存在'
$script:interactive=$true;$script:answer='';$script:reads=0;$script:throws=$false
function Test-SetupInitInteractiveHost {return $script:interactive}
function Read-Host {param($Prompt);$script:reads++;$script:prompt=$Prompt;if($script:throws){throw 'cancelled'};return $script:answer}
foreach($value in @('','y','Y','yes','YES','YeS')){$script:answer=$value;Assert (Request-SetupInitConsent) '明確同意及實際空字串允許'}
Assert ($script:prompt -match 'Enter' -and $script:prompt -match 'Sysprep' -and $script:prompt -match '預設') '提示包含預設及後果'
foreach($value in @($null,' ','  ','no','n','YES ','unknown')){$script:answer=$value;Assert (-not (Request-SetupInitConsent)) '空值空白拒絕及其他輸入不允許'}
$script:interactive=$false;$script:answer='';$before=$script:reads;Assert (-not (Request-SetupInitConsent) -and $script:reads -eq $before) '非互動或重導輸入不詢問也不允許'
$script:interactive=$true;$script:throws=$true;Assert (-not (Request-SetupInitConsent)) '取消或輸入失敗不允許'
$cmd=[IO.File]::ReadAllText((Join-Path $root 'init.cmd'));Assert ($cmd -match '(?im)^powershell\.exe\s+.*-NoExit\s+-File\s+"%~dp0modules\\init\\initialize_setup\.ps1"') '真 CMD 入口保留同一互動主機'
function Invoke-InitProvisioningEntry {return $false}
function Get-SetupInitContext {return [pscustomobject]@{Sid='S-1-5-21-1-2-3-500';IsAdministrator=$true;ImageState='IMAGE_STATE_UNDEPLOYABLE';DesktopOwned=$true;Is64Bit=$true;Architecture='AMD64';ModeFacts=@{}}}
function Get-InitRoute {return 'PrepareOobe'}
function Assert-InitProvisioningAsset {return @{}}
function Get-Process {param($Name,$ErrorAction)}
function Get-ItemProperty {param($Path,$ErrorAction);return @{}}
function Get-InitAnswerCandidates {param($WindowsPath);return @()}
function Assert-InitPlainPath {param($Path)}
function Test-Path {param($LiteralPath,$PathType);return ($LiteralPath -like '*Sysprep.exe')}
function Get-LocalUser {$script:accounts++;throw 'fixture account boundary'}
function Start-Process {$script:effects++;throw 'unexpected process'}
function New-Item {$script:effects++;throw 'unexpected write'}
$script:interactive=$true;$script:throws=$false
foreach($value in @($null,' ','no','n','unknown')){
 $script:answer=$value;$script:accounts=0;$script:effects=0;$failed=$false
 try{Invoke-SetupInit -EntryPath 'fixture' -ModuleRoot (Join-Path $root 'modules/init')}catch{$failed=$true}
 Assert ($failed -and $script:accounts -eq 0 -and $script:effects -eq 0) '拒絕時不進入帳號或系統副作用'
}
$script:answer='';$script:accounts=0;$script:effects=0;$failed=$false
try{Invoke-SetupInit -EntryPath 'fixture' -ModuleRoot (Join-Path $root 'modules/init')}catch{$failed=$_.Exception.Message -ceq 'fixture account boundary'}
Assert ($failed -and $script:accounts -eq 1 -and $script:effects -eq 0) '空字串同意後才抵達假帳號邊界'
foreach($mode in @('noninteractive','cancel')){
 $script:interactive=($mode -ne 'noninteractive');$script:throws=($mode -eq 'cancel');$script:answer='';$script:accounts=0;$script:effects=0;$failed=$false
 try{Invoke-SetupInit -EntryPath 'fixture' -ModuleRoot (Join-Path $root 'modules/init')}catch{$failed=$true}
 Assert ($failed -and $script:accounts -eq 0 -and $script:effects -eq 0) '非互動或取消不進入帳號與系統副作用'
}