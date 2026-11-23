#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'start_pins_asset_library.ps1')
function Get-StartPinsRoute {
 param([int]$Build,[int]$Revision,[string]$AdmxText)
 if($Build -lt 26100 -or ($Build -eq 26100 -and $Revision -lt 4770) -or [string]::IsNullOrWhiteSpace($AdmxText)){return 'LegacyPackage'}
 $xml=ConvertTo-StartPinsXml $AdmxText
 $policy=@($xml.SelectNodes('//*[local-name()="policy" and @name="ConfigureStartPins" and @key="Software\Policies\Microsoft\Windows\Explorer" and @valueName="ConfigureStartPins"]'))
 if($policy.Count -eq 1 -and $policy[0].SelectSingleNode('.//*[local-name()="text" and @valueName="ConfigureStartPinsJSON"]')){return 'Gpo'}
 return 'LegacyPackage'
}
function Invoke-StartPinsLegacyPolicy {
 param([string]$AssetRoot,[switch]$ApplyPolicy,[switch]$NonInteractive,[scriptblock]$Confirm)
 $manifest=Assert-StartPinsAsset $AssetRoot
 $installed=@(Get-ProvisioningPackage -AllInstalledPackages -ErrorAction Stop|Where-Object {$_.PackageID -eq $manifest.PackageId -and $_.IsInstalled})
 if($installed.Count -gt 1 -or ($installed.Count -eq 1 -and ($installed[0].PackageName -cne $manifest.PackageName -or $installed[0].Version -ne $manifest.PackageVersion))){throw '既有 Start 政策包身分不符，未重新套用。'}
 if($installed.Count -eq 1){return [pscustomobject]@{Success=$false;Status='PendingSignIn';PolicyInstalled=$true}}
 if(-not $ApplyPolicy -or $NonInteractive -or $null -eq $Confirm){return [pscustomobject]@{Success=$false;Status='LegacyPendingApply';PolicyInstalled=$false}}
 if((& $Confirm) -cne 'YES'){return [pscustomobject]@{Success=$false;Status='LegacyPendingApply';PolicyInstalled=$false}}
 Install-ProvisioningPackage -PackagePath (Join-Path $AssetRoot 'empty_start.ppkg') -QuietInstall -ErrorAction Stop|Out-Null
 $installed=@(Get-ProvisioningPackage -AllInstalledPackages -ErrorAction Stop|Where-Object {$_.PackageID -eq $manifest.PackageId -and $_.IsInstalled -and $_.PackageName -ceq $manifest.PackageName -and $_.Version -eq $manifest.PackageVersion})
 if($installed.Count -ne 1){throw 'Start 政策套用後原生讀回不符，不能視為完成。'}
 return [pscustomobject]@{Success=$false;Status='PendingSignIn';PolicyInstalled=$true}
}
function Invoke-StartPinsBoundedProcess {
 # 子程序執行並設硬上限；逾時時結束整個子程序樹，不留懸置的原生呼叫。
 param([Parameter(Mandatory=$true)][string]$ScriptText,[int]$TimeoutSeconds=20)
 $file=Join-Path ([IO.Path]::GetTempPath()) ('startpins_'+[guid]::NewGuid().ToString('N')+'.ps1')
 try{
  [IO.File]::WriteAllText($file,$ScriptText,(New-Object Text.UTF8Encoding($true)))
  $psi=New-Object Diagnostics.ProcessStartInfo (Join-Path $PSHOME 'powershell.exe')
  $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$file+'"'
  $psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.CreateNoWindow=$true
  $proc=[Diagnostics.Process]::Start($psi)
  if($proc.WaitForExit($TimeoutSeconds*1000)){return [pscustomobject]@{TimedOut=$false;ExitCode=$proc.ExitCode;Output=$proc.StandardOutput.ReadToEnd()}}
  & taskkill.exe /PID $proc.Id /T /F|Out-Null
  return [pscustomobject]@{TimedOut=$true;ExitCode=$null;Output=''}
 }finally{Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue}
}
function Invoke-StartPinsNativeExport {
 # 回傳 Status=Ok|Failed|TimedOut。測試可設 $global:StartPinsExportInProcess 以替身 Export-StartLayout 在同一程序執行。
 param([string]$ExportPath,[int]$TimeoutSeconds=20)
 if($global:StartPinsExportInProcess){
  try{Export-StartLayout -Path $ExportPath -ErrorAction Stop;return [pscustomobject]@{Status='Ok';HResult=0;Error=$null}}catch{
   $native=$_.Exception
   while($native.InnerException -and $native.HResult -ne -2147023728){$native=$native.InnerException}
   return [pscustomobject]@{Status='Failed';HResult=$native.HResult;Error=$_}
  }
 }
 $quoted=$ExportPath.Replace("'","''")
 $script="try{Export-StartLayout -Path '$quoted' -ErrorAction Stop;exit 0}catch{`$e=`$_.Exception;while(`$e.InnerException -and `$e.HResult -ne -2147023728){`$e=`$e.InnerException};[Console]::Out.WriteLine('HRESULT='+`$e.HResult);[Console]::Out.WriteLine('MESSAGE='+`$e.Message);exit 2}"
 $r=Invoke-StartPinsBoundedProcess -ScriptText $script -TimeoutSeconds $TimeoutSeconds
 if($r.TimedOut){return [pscustomobject]@{Status='TimedOut';HResult=$null;Error=$null}}
 if($r.ExitCode -eq 0){return [pscustomobject]@{Status='Ok';HResult=0;Error=$null}}
 $hr=if($r.Output -match 'HRESULT=(-?\d+)'){[int]$Matches[1]}else{-1}
 $msg=if($r.Output -match 'MESSAGE=(.*)'){$Matches[1].Trim()}else{'原生匯出子程序失敗'}
 return [pscustomobject]@{Status='Failed';HResult=$hr;Error=(New-Object InvalidOperationException ('Export-StartLayout 失敗：'+$msg))}
}
function Invoke-StartPinsHostActivation {
 # 以系統的 AppX 啟動介面啟用 Start Host：Host 不存在時由系統建立，被暫停時恢復（實機證據見 fixtures/nuc_start_host）。
 param([string]$Aumid='Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy!FullTrustApp')
 if(-not ('StartPinsAppxActivator' -as [type])){
  Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
[ComImport,Guid("2e941141-7f97-4756-ba1d-9decde894a3d"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IStartPinsAppActivationManager{int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)]string appUserModelId,[MarshalAs(UnmanagedType.LPWStr)]string arguments,int options,out uint processId);int ActivateForFile(IntPtr a,IntPtr b,IntPtr c,out uint d);int ActivateForProtocol(IntPtr a,IntPtr b,out uint c);}
[ComImport,Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]public class StartPinsAppActivationManager{}
public static class StartPinsAppxActivator{public static int Activate(string aumid,out uint pid){var m=(IStartPinsAppActivationManager)new StartPinsAppActivationManager();return m.ActivateApplication(aumid,null,0,out pid);}}
'@
 }
 [uint32]$procId=0
 $hr=[StartPinsAppxActivator]::Activate($Aumid,[ref]$procId)
 if($hr -ne 0){throw ('Start Host 啟用失敗，HRESULT 0x{0:x8}' -f $hr)}
 return [pscustomobject]@{ProcessId=[int]$procId}
}
function New-StartPinsPending {
 param([string]$ExportStatus,$NativeHResult,[string]$Reason)
 return [ordered]@{Success=$false;Status='PendingSignIn';PinCount=$null;ExportPath=$null;ExportStatus=$ExportStatus;NativeHResult=$NativeHResult;Reason=$Reason;CheckedAt=(Get-Date).ToString('o')}
}
function Get-StartPinsExportState {
 param([string]$ExportPath,$PolicyState)
 $notFound=-2147023728
 $r=Invoke-StartPinsNativeExport -ExportPath $ExportPath
 if($r.Status -ne 'Ok'){
  if($r.Status -eq 'Failed'){
   if($r.HResult -ne $notFound -or -not $PolicyState.PolicyInstalled){if($r.Error){throw $r.Error}else{throw ('Export-StartLayout 失敗，HRESULT '+$r.HResult)}}
   $session=(Get-Process -Id $PID -ErrorAction Stop).SessionId
   $hosts=@(Get-Process -ErrorAction Stop|Where-Object {$_.ProcessName -eq 'StartMenuExperienceHost' -and $_.SessionId -eq $session})
   if($hosts.Count -gt 0){if($r.Error){throw $r.Error}else{throw 'Export-StartLayout 回報找不到，但 Start Host 已存在。'}}
   $first='NotFound'
  }else{
   if(-not $PolicyState.PolicyInstalled){throw '開始選單原生匯出逾時，且政策尚未安裝。'}
   $first='TimedOut'
  }
  # Start Host 不存在（0x80070490）或被暫停（匯出逾時）：以系統啟用介面喚醒後立即重試，次數與時間皆有上限。
  $detail=''
  $r2=$null
  try{
   Invoke-StartPinsHostActivation|Out-Null
   for($i=1;$i -le 3;$i++){
    $r2=Invoke-StartPinsNativeExport -ExportPath $ExportPath
    if($r2.Status -ne 'Failed' -or $r2.HResult -ne $notFound -or $i -ge 3){break}
    Start-Sleep -Seconds 1
   }
  }catch{$detail=$_.Exception.Message}
  if($detail -or $null -eq $r2 -or $r2.Status -ne 'Ok'){
   if(-not $detail){$detail=if($r2.Status -eq 'TimedOut'){'喚醒後原生匯出仍逾時'}else{'喚醒後原生匯出仍失敗（HRESULT '+$r2.HResult+'）'}}
   if($first -eq 'TimedOut'){return (New-StartPinsPending 'TimedOut' $null ('開始選單原生匯出逾時（Start Host 可能被暫停），已嘗試喚醒仍無法確認：'+$detail+'；登入後請再驗證。'))}
   return (New-StartPinsPending 'Unavailable' '0x80070490' ('開始選單原生匯出尚不可用，且目前工作階段未啟動 Start Host，已嘗試喚醒仍無法確認：'+$detail+'；登入後請再驗證。'))
  }
 }
 $actual=[IO.File]::ReadAllText($ExportPath)|ConvertFrom-Json -ErrorAction Stop
 if(-not $actual -or 'pinnedList' -notin @($actual.PSObject.Properties.Name) -or $null -eq $actual.pinnedList -or $actual.pinnedList -isnot [Array]){throw '開始選單原生匯出缺少有效 pinnedList，不能視為空白。'}
 $count=@($actual.pinnedList).Count
 $status=if($PolicyState.Status -eq 'LegacyPendingApply'){'LegacyPendingApply'}elseif($count -eq 0){'Confirmed'}else{'PendingSignIn'}
 return [ordered]@{Success=($status -eq 'Confirmed');Status=$status;PinCount=$count;ExportPath=$ExportPath;CheckedAt=(Get-Date).ToString('o')}
}
function Invoke-StartPinsConfiguration {
 param([string]$AssetRoot,[string]$OutputRoot,[string]$AdmxPath=(Join-Path $env:WINDIR 'PolicyDefinitions/StartMenu.admx'),[switch]$VerifyOnly,[switch]$ApplyPolicy,[switch]$NonInteractive)
 $version=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
 $admx=if(Test-Path -LiteralPath $AdmxPath -PathType Leaf){[IO.File]::ReadAllText($AdmxPath)}else{''}
 $route=Get-StartPinsRoute ([int]$version.CurrentBuildNumber) ([int]$version.UBR) $admx
 if($route -eq 'Gpo'){
  if(-not $VerifyOnly){
   $layout=Join-Path $OutputRoot 'EmptyStartLayout.json'
   Set-Content -LiteralPath $layout -Value '{"pinnedList":[],"applyOnce":true}' -Encoding UTF8 -ErrorAction Stop
   $key='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
   if(-not(Test-Path -LiteralPath $key -ErrorAction Stop)){New-Item -Path $key -ErrorAction Stop|Out-Null}
   New-ItemProperty -Path $key -Name ConfigureStartPins -PropertyType DWord -Value 1 -Force|Out-Null
   New-ItemProperty -Path $key -Name ConfigureStartPinsJSON -PropertyType String -Value $layout -Force|Out-Null
  }
  $policy=[pscustomobject]@{Status='PendingSignIn';PolicyInstalled=$true}
 }else{
  $policy=Invoke-StartPinsLegacyPolicy -AssetRoot $AssetRoot -ApplyPolicy:($ApplyPolicy -and -not $VerifyOnly) -NonInteractive:$NonInteractive -Confirm {
   Write-Host '舊版 Windows 的開始選單政策套用於整臺電腦，每次登入會重新清空釘選。Windows 可能要求重新登入或重新啟動。' -ForegroundColor Yellow
   Read-Host '請確認其他設定與更新都已完成；現在套用請輸入 YES，其餘輸入保留待處理'
  }
 }
 $result=Get-StartPinsExportState -ExportPath (Join-Path $OutputRoot ('StartMenu-Actual-'+[guid]::NewGuid().ToString('N')+'.json')) -PolicyState $policy
 $result.PolicyRoute=$route
 return $result
}

function Complete-StartPinsPending {
 param($Result,[string[]]$StageErrors=@(),[int]$ProblemCount=0,[switch]$NonInteractive,[scriptblock]$Apply)
 if($null -eq $Result -or $Result.Status -ne 'LegacyPendingApply' -or $StageErrors.Count -gt 0 -or $ProblemCount -gt 0 -or $NonInteractive){return $Result}
 if($null -eq $Apply){throw '開始選單後置套用入口缺失。'}
 return (& $Apply -ApplyPolicy)
}
