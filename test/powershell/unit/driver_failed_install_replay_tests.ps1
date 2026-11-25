#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 重放 2026-11-25 NUC 注入實測：真實裝置 MEWMIProv（已綁 oem 目標版本、簽署者為 WHCP）與真實讀回流程，僅注入「計畫為 UpdateRequired」與「原生安裝退出碼 1」。這是人為注入的失敗，不是現場失敗紀錄；資料見 fixtures/nuc_driver_child_settle_20261125/readme.md
$fx=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../fixtures/nuc_driver_child_settle_20261125/child_settle_fixture.json') -Raw -Encoding UTF8|ConvertFrom-Json
$script:nativeExit=1;$script:clock=0;$script:cfg=$null;$script:child=$null;$script:installed=$false;$script:sleeps=@();$script:installs=0;$script:enumCalls=0;$script:rescans=0
function Test-Appeared([string]$Key){$at=$script:cfg[$Key];return ($null -ne $at -and $script:clock -ge $at)}
function Assert-SetupDriverTargetIntegrity {param($Target,$Root) return $true}
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath,[switch]$StageOnly) $script:installs++;$script:installed=$true;return [pscustomobject]@{ExitCode=$script:nativeExit}}
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
$c=@($fx.Children|Where-Object Id -eq 'mei_wmi')[0]
# 計畫強制為 UpdateRequired（與 NUC 注入相同）；裝置實際已綁定目標版本、簽署者正確
$script:origPlan=${function:Get-SetupDriverTargetPlan}
function Get-SetupDriverTargetPlan {param($Target,$Devices,$Build,$Architecture) $p=@(& $script:origPlan -Target $Target -Devices $Devices -Build $Build -Architecture $Architecture);foreach($x in $p){if($x.Status -eq 'Current'){$x.Status='UpdateRequired'}};$p}
$cfg=@{liveAt=0;enumAt=0;LiveVersion=[string]$c.TargetVersion;LiveProvider=[string]$c.Provider;LiveInf=[string]$c.PublishedName;Signer=$good}
$script:nativeExit=1
$r=Invoke-Child -Child $c -Config $cfg -Settle
Assert ($script:installs -eq 1 -and $r.Failures.Count -eq 1) '計畫為 UpdateRequired 並實際呼叫原生安裝，退出碼 1 時失敗清單保留 1 筆'
Assert (@($r.Results|Where-Object Status -eq 'Updated').Count -eq 0) '原生安裝失敗時單項結果不可顯示 Updated，即使讀回已符合目標'
Assert (@($r.Results|Where-Object Status -eq 'InstallFailed').Count -eq 1 -and [string]$r.Results[0].Reason -match '退出碼 1' -and [string]$r.Results[0].Reason -match '讀回：Updated') '標示 InstallFailed，原因含退出碼與讀回狀態'
$script:nativeExit=0
$r=Invoke-Child -Child $c -Config $cfg -Settle
Assert (@($r.Results|Where-Object Status -eq 'Updated').Count -eq 1 -and $r.Failures.Count -eq 0) '原生安裝成功時維持 Updated'