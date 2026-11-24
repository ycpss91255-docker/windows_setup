#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 重放 2026-11-25 NUC 重灌：父驅動剛裝完，子元件在計畫階段 CIM 無列／無簽章，被誤判 Unverified 而沒有等待。資料見 fixtures/nuc_driver_child_settle_20261125/readme.md
$fx=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../fixtures/nuc_driver_child_settle_20261125/child_settle_fixture.json') -Raw -Encoding UTF8|ConvertFrom-Json
$script:clock=0;$script:cfg=$null;$script:child=$null;$script:installed=$false;$script:sleeps=@();$script:installs=0;$script:enumCalls=0;$script:rescans=0
function Test-Appeared([string]$Key){$at=$script:cfg[$Key];return ($null -ne $at -and $script:clock -ge $at)}
function Assert-SetupDriverTargetIntegrity {param($Target,$Root) return $true}
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath,[switch]$StageOnly) $script:installs++;$script:installed=$true;return [pscustomobject]@{ExitCode=0}}
function Invoke-SetupDriverPnpRescan {$script:rescans++;[pscustomobject]@{ExitCode=0}}
function Start-Sleep {param([int]$Seconds) $script:sleeps+=$Seconds;$script:clock+=$Seconds}
function Get-CimInstance {param($ClassName,$ErrorAction) return @()}
function Get-PnpDevice {param([switch]$PresentOnly,$ErrorAction)
 if($script:installed -or (Test-Appeared 'enumAt')){[pscustomobject]@{InstanceId=[string]$script:child.InstanceId;FriendlyName='fixture';Class='SoftwareComponent';Status='OK'}}
}
function Get-PnpDeviceProperty {param([string]$InstanceId,[string]$KeyName,$ErrorAction)
 $bound=($script:installed -or (Test-Appeared 'liveAt'))
 $version=if($script:installed){[string]$script:child.TargetVersion}elseif($bound){[string]$script:cfg.LiveVersion}else{$null}
 switch($KeyName){
  'DEVPKEY_Device_DriverVersion'{return [pscustomobject]@{Data=$version}}
  'DEVPKEY_Device_DriverProvider'{return [pscustomobject]@{Data=$(if($script:installed){[string]$script:child.Provider}elseif($bound -and $script:cfg.LiveProvider){[string]$script:cfg.LiveProvider}elseif($bound){[string]$script:child.Provider}else{$null})}}
  'DEVPKEY_Device_DriverInfPath'{return [pscustomobject]@{Data=$(if($script:installed){[string]$script:child.PublishedName}elseif($bound -and $script:cfg.LiveInf){[string]$script:cfg.LiveInf}elseif($bound){[string]$script:child.PublishedName}else{$null})}}
  default{return [pscustomobject]@{Data=@($script:child.HardwareIds)}}
 }
}
function Get-SetupDriverEnumDriversXmlText {
 $script:enumCalls++
 $signer=if($script:installed){[string]$fx.SignerName}else{[string]$script:cfg.Signer}
 if(-not $signer){return '<PnpUtil></PnpUtil>'}
 return ('<?xml version="1.0" encoding="utf-8"?><PnpUtil><Driver DriverName="'+$script:child.PublishedName+'"><OriginalName>x.inf</OriginalName><SignerName>'+$signer+'</SignerName></Driver></PnpUtil>')
}
function Invoke-Child {param($Child,[hashtable]$Config,[switch]$Settle,[switch]$KeepBudget)
 $script:child=$Child;$script:cfg=$Config;$script:clock=0;$script:installed=$false;$script:sleeps=@();$script:installs=0;$script:enumCalls=0;$script:rescans=0
 if(-not $KeepBudget){$script:SetupDriverReadbackWaited=0}
 $target=[pscustomobject]@{InfPath=[string]$Child.InfPath;HardwareIds=@($Child.HardwareIds);DriverVersion=[string]$Child.TargetVersion;Provider=[string]$Child.Provider;ProviderAliases=@();MinimumBuild=1;Architecture='amd64'}
 if($Settle){Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log' -RequiredPresent -SettleAfterInstall}
 else{Invoke-SetupDriverTarget -Target $target -Root 'C:\fixture' -Build 26200 -Architecture amd64 -LogPath 'C:\fixture\synthetic.log' -RequiredPresent}
}
function Total {$m=($script:sleeps|Measure-Object -Sum).Sum;if($null -eq $m){0}else{[int]$m}}
$good=[string]$fx.SignerName

# 現場：父驅動剛裝完，子元件的 CIM 列尚未出現，但 DEVPKEY 與 pnputil 簽署者已正確 → 5 個都應核實，不必等待
foreach($c in @($fx.Children)){
 $r=Invoke-Child -Child $c -Config @{liveAt=0;enumAt=0;LiveVersion=[string]$c.TargetVersion;Signer=$good} -Settle
 Assert (@($r.Results|Where-Object Status -eq 'Current').Count -eq 1 -and $r.Failures.Count -eq 0) ($c.Id+'：CIM 列尚空但 DEVPKEY 與 pnputil 簽署者已確認時應核實為 Current')
 Assert ((Total) -eq 0 -and $script:installs -eq 0) ($c.Id+'：已確認時不等待也不重裝')
}

# 延後出現：DEVPKEY 驅動資訊 20 秒後才出現 → 等待後核實，未超過共用額度
$c=@($fx.Children)[0]
$r=Invoke-Child -Child $c -Config @{liveAt=20;enumAt=0;LiveVersion=[string]$c.TargetVersion;Signer=$good} -Settle
Assert (@($r.Results|Where-Object Status -eq 'Current').Count -eq 1 -and $r.Failures.Count -eq 0) '驅動資訊延後出現時等待後應核實'
Assert ((Total) -ge 20 -and (Total) -le 150 -and $script:rescans -ge 1) '延後出現的等待在額度內且先重新掃描'

# 子元件延後枚舉（amdocl 現場：必需子元件尚未枚舉）
$c=@($fx.Children|Where-Object Id -eq 'amdocl')[0]
$r=Invoke-Child -Child $c -Config @{enumAt=25;liveAt=25;LiveVersion=[string]$c.TargetVersion;Signer=$good} -Settle
Assert (@($r.Results|Where-Object Status -eq 'Current').Count -eq 1 -and $r.Failures.Count -eq 0) '必需子元件延後枚舉時等待後應核實'

# 一直不出現：如實 Unverified，寫明已等待秒數，總等待不超過 150
$r=Invoke-Child -Child $c -Config @{Signer=$good} -Settle
Assert (@($r.Results|Where-Object Status -eq 'Unverified').Count -eq 1 -and $r.Failures.Count -gt 0) '一直不枚舉須維持 Unverified 並列入失敗'
Assert ((Total) -eq 150 -and [string]$r.Results[0].Reason -match '已等待 150 秒') '一直不出現時等待 150 秒且 Reason 寫明秒數'
$c=@($fx.Children)[0]
$r=Invoke-Child -Child $c -Config @{enumAt=0;Signer=$good} -Settle
Assert (@($r.Results|Where-Object Status -eq 'Unverified').Count -eq 1 -and (Total) -eq 150 -and [string]$r.Results[0].Reason -match '已等待 150 秒') '驅動資訊一直空白須維持 Unverified 並寫明已等待 150 秒'

# 出現但簽章不對：不放寬，立即 Unverified，不必等待
$r=Invoke-Child -Child $c -Config @{liveAt=0;enumAt=0;LiveVersion=[string]$c.TargetVersion;Signer='Contoso Test Publisher'} -Settle
Assert (@($r.Results|Where-Object Status -eq 'Unverified').Count -eq 1 -and $r.Failures.Count -gt 0 -and (Total) -eq 0) '簽署者不符須維持 Unverified 且不白等'

# 查不到簽署者（pnputil 無該列）：不得核實
$r=Invoke-Child -Child $c -Config @{liveAt=0;enumAt=0;LiveVersion=[string]$c.TargetVersion;Signer=''} -Settle
Assert (@($r.Results|Where-Object Status -eq 'Unverified').Count -eq 1 -and (Total) -le 150) '查不到簽署者不得核實'

# 需要安裝：綁定的是較舊版本 → 重新計畫為 UpdateRequired，走既有安裝路徑並讀回
$r=Invoke-Child -Child $c -Config @{liveAt=0;enumAt=0;LiveVersion=[string]$c.OlderVersion;Signer=$good} -Settle
Assert ($script:installs -eq 1 -and @($r.Results|Where-Object Status -eq 'Updated').Count -eq 1 -and $r.Failures.Count -eq 0) '綁定較舊版本時重新計畫後應走既有安裝路徑並讀回 Updated'

# 額度用盡：前面目標已用完 150 秒 → 不再等待，如實 Unverified 並說明
$script:SetupDriverReadbackWaited=150
$r=Invoke-Child -Child $c -Config @{liveAt=20;enumAt=0;LiveVersion=[string]$c.TargetVersion;Signer=$good} -Settle -KeepBudget
Assert (@($r.Results|Where-Object Status -eq 'Unverified').Count -eq 1 -and (Total) -eq 0 -and [string]$r.Results[0].Reason -match '額度已用盡') '共用額度用盡時不再等待並說明'

# 現場（2026-11-25 MEWMIProv）：子元件綁到 Windows 內建 c_swcomponent.inf（Microsoft、10.0.26100.1），pnputil 的 /enum-drivers 不列內建驅動，查不到簽署者
$c=@($fx.Children|Where-Object Id -eq 'mei_wmi')[0]
$r=Invoke-Child -Child $c -Config @{liveAt=0;enumAt=0;LiveVersion='10.0.26100.1';LiveProvider='Microsoft';LiveInf='c_swcomponent.inf';Signer=''} -Settle
Assert ($script:installs -eq 1 -and @($r.Results|Where-Object Status -eq 'Updated').Count -eq 1 -and $r.Failures.Count -eq 0) '子元件綁在內建驅動時應視為原廠目標取代通用驅動，走既有安裝路徑並以 pnputil 簽署者讀回 Updated'
Assert ((Total) -eq 0) '內建驅動不需要等待 150 秒'
# 內建 INF 的豁免只限 Microsoft 供應商：其他供應商的非 oem INF 仍須有簽署者，否則 Unverified
$r=Invoke-Child -Child $c -Config @{liveAt=0;enumAt=0;LiveVersion='1.0.0.0';LiveProvider='Contoso';LiveInf='contoso.inf';Signer=''} -Settle
Assert (@($r.Results|Where-Object Status -eq 'Unverified').Count -eq 1 -and $script:installs -eq 0) '非 Microsoft 供應商且查不到簽署者時不得視為已簽署'
# 內建驅動的豁免不影響 oem 套件：Microsoft 供應商但 oem INF，簽署者不符仍 Unverified
$r=Invoke-Child -Child $c -Config @{liveAt=0;enumAt=0;LiveVersion='10.0.26100.1';LiveProvider='Microsoft';LiveInf='oem77.inf';Signer='Contoso Test Publisher'} -Settle
Assert (@($r.Results|Where-Object Status -eq 'Unverified').Count -eq 1 -and $script:installs -eq 0) 'oem INF 簽署者不符時不因供應商為 Microsoft 而放行'

# 非「剛安裝父驅動」情境（VerifyOnly、未安裝任何驅動）：不改用即時屬性、不等待、不放寬
$r=Invoke-Child -Child $c -Config @{liveAt=0;enumAt=0;LiveVersion=[string]$c.TargetVersion;Signer=$good}
Assert (@($r.Results|Where-Object Status -eq 'Unverified').Count -eq 1 -and (Total) -eq 0 -and $script:enumCalls -eq 0 -and $script:rescans -eq 0) '未安裝父驅動時維持原判定、不等待、不查簽署者'

# 套件層：同一套件內有目標實際安裝後，後續目標才帶 -SettleAfterInstall
$script:calls=@()
function Get-FileHash {param($LiteralPath,$Algorithm,$ErrorAction) [pscustomobject]@{Hash='H'}}
function Test-SetupDriverScopeAbsent {param($Entry,$Devices,$Build) $false}
function New-SetupDriverExtractionRoot {'C:\stage'}
function Remove-SetupDriverExtractionRoot {param($Path) $true}
function Expand-DriverArchive {param($Archive,$Destination)}
function Assert-SetupDriverPayloadFiles {param($Entry,$Root)}
function Get-SetupDriverDeviceInventory {param($Targets) @()}
function Get-SetupDriverTargetPlan {param($Target,$Devices,$Build,$Architecture) @([pscustomobject]@{Status='Current';InfPath=$Target.InfPath})}
function Invoke-SetupDriverTarget {param($Target,$Root,$Build,$Architecture,$LogPath,[switch]$RequiredPresent,[switch]$SettleAfterInstall)
 $script:calls+=[pscustomobject]@{Inf=$Target.InfPath;Settle=[bool]$SettleAfterInstall}
 [pscustomobject]@{Results=@([pscustomobject]@{Status='Current'});RebootRequired=$false;Failures=@();Installed=[bool]$Target.WillInstall}
}
$parent=[pscustomobject]@{Id='p';InfPath='p.inf';WillInstall=$true;MinimumBuild=1;Architecture='amd64'}
$kid=[pscustomobject]@{Id='k';InfPath='k.inf';ParentTarget='p';WillInstall=$false;MinimumBuild=1;Architecture='amd64'}
$sib=[pscustomobject]@{Id='s';InfPath='s.inf';WillInstall=$false;MinimumBuild=1;Architecture='amd64'}
$null=Invoke-SetupOfficialDriverPackage -Entry ([pscustomobject]@{Id='pkg';SHA256='H';ScopeTarget=$null;Drivers=@($parent,$kid,$sib);Extensions=@()}) -Archive 'a.zip' -Build 26200 -LogPath 'l.log'
Assert (@($script:calls|Where-Object {$_.Inf -eq 'p.inf'})[0].Settle -eq $false) '套件內第一個目標（父驅動）本身不帶即時確認旗標'
Assert (@($script:calls|Where-Object {$_.Inf -eq 'k.inf'})[0].Settle -eq $true -and @($script:calls|Where-Object {$_.Inf -eq 's.inf'})[0].Settle -eq $true) '父驅動實際安裝後，子元件與同套件其他目標帶即時確認旗標'
$script:calls=@()
$parent.WillInstall=$false
$null=Invoke-SetupOfficialDriverPackage -Entry ([pscustomobject]@{Id='pkg';SHA256='H';ScopeTarget=$null;Drivers=@($parent,$kid,$sib);Extensions=@()}) -Archive 'a.zip' -Build 26200 -LogPath 'l.log'
Assert (@($script:calls|Where-Object Settle).Count -eq 0) '本套件沒有實際安裝任何驅動時不帶即時確認旗標'
Write-Output 'driver child settle test passed'
