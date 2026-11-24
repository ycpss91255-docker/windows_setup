#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Reject([scriptblock]$Action,[string]$Expected,[string]$Name){$errorText='';try{& $Action|Out-Null}catch{$errorText=$_.Exception.Message};Assert ($errorText.Contains($Expected)) ($Name+'; actual='+$errorText)}
$library=Join-Path $root 'modules/theme/theme_settings_library.ps1'
Assert (Test-Path -LiteralPath $library) 'Theme has a named original-source leaf without importing the elevated public entry'
. $library
Add-Type -TypeDefinition 'using System;using System.Text;public static class NUC8Theme{public sealed class TaskbarSample{public int[] RGB;public bool AutoHidden;}public static bool AutoHidden;public static TaskbarSample ObserveTaskbar(){return new TaskbarSample{RGB=AutoHidden?new int[0]:TaskbarColor(),AutoHidden=AutoHidden};}public static bool ColorOk=true,WallpaperOk=true,ReadOk=true;public static uint Color;public static string Wallpaper="";public static int SetColorCalls,SetWallpaperCalls,NotifyCalls,Reads,LightReads;public static bool SetSysColors(int count,int[] elements,uint[] colors){SetColorCalls++;if(count!=1||elements[0]!=1||colors[0]!=0)throw new Exception("wrong colors");return ColorOk;}public static bool SystemParametersInfo(uint action,uint param,string value,uint flags){SetWallpaperCalls++;if(action!=20||param!=0||value!=""||flags!=3)throw new Exception("wrong wallpaper");if(WallpaperOk)Wallpaper="";return WallpaperOk;}public static IntPtr SendMessageTimeout(IntPtr hwnd,uint msg,IntPtr wp,string lp,uint flags,uint timeout,out IntPtr result){NotifyCalls++;result=IntPtr.Zero;return IntPtr.Zero;}public static int[] TaskbarColor(){Reads++;if(LightReads>0){LightReads--;return new int[]{240,240,240};}return new int[]{21,21,21};}public static bool ReadWallpaper(uint action,uint param,StringBuilder value,uint flags){if(ReadOk)value.Append(Wallpaper);return ReadOk;}public static uint GetSysColor(int index){return Color;}}'
$personalize='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$wallpapers='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Wallpapers';$cloud='HKCU:\Software\Policies\Microsoft\Windows\CloudContent'
$script:keys=@{};$script:values=@{AppsUseLightTheme=0;SystemUsesLightTheme=0};$script:writes=@();$script:created=@();$script:stopped=@();$script:started=0;$script:startedPaths=@()
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
$script:processes=@([pscustomobject]@{SessionId=$session;Name='current'},[pscustomobject]@{SessionId=($session+10);Name='other'})
function Test-Path {param($Path) if($Path -notin @($personalize,$wallpapers,$cloud)){throw 'unexpected theme registry path'};$script:keys.ContainsKey($Path)}
function New-Item {param($Path,[switch]$Force) $script:keys[$Path]=$true;$script:created+=@($Path)}
function New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force) if($Path -notin @($personalize,$wallpapers,$cloud) -or $PropertyType -ne 'DWord' -or -not $Force){throw 'unexpected theme preference'};$script:values[$Name]=$Value;$script:writes+=@($Path+'|'+$Name+'|'+$Value)}
function Set-ItemProperty {param($Path,$Name,$Value) if(($Path -ne 'HKCU:\Control Panel\Colors' -or $Name -ne 'Background' -or $Value -ne '0 0 0') -and ($Path -ne 'HKCU:\Control Panel\Desktop' -or $Name -ne 'Wallpaper' -or $Value -ne '')){throw 'unexpected theme registry write'};$script:writes+=@($Path+'|'+$Name+'|'+$Value)}
function Get-ItemProperty {param($Path) if($Path -ne $personalize){throw 'unexpected theme verification read'};[pscustomobject]$script:values}
function Get-Process {param($Name,$ErrorAction) if($Name -ne 'explorer'){throw 'unexpected process lookup'};$script:processes}
function Stop-Process {param([Parameter(ValueFromPipeline=$true)]$InputObject,[switch]$Force) process{if(-not $Force -or $InputObject.SessionId -ne $session){throw 'unsafe theme Explorer stop'};$script:stopped+=@($InputObject.Name);$script:processes=@($script:processes|Where-Object SessionId -ne $session)}}
function Start-Process {param($FilePath) if($FilePath -notin @('explorer.exe',$actualExplorer)){throw 'unexpected theme process'};$script:startedPaths+=@($FilePath);$script:started++}
function Start-Sleep {param($Seconds,$Milliseconds)}
$module=Join-Path $root 'modules/theme'
# NUC scene replay for issue 354: field-level replay of two de-identified captured Theme results.
$fixtureRoot=Join-Path $root 'test/powershell/fixtures/nuc_theme_issue354'
function Read-SceneResult([string]$Name){Get-Content -LiteralPath (Join-Path $fixtureRoot $Name) -Raw -Encoding UTF8|ConvertFrom-Json}
$productFields=@('Success','AppsMode','WindowsMode','Background','TaskbarRGB','TaskbarIsDark','TaskbarAppearanceStatus','TaskbarPixelsVerified','ExplorerReloaded','ActualBackgroundColor','ActualWallpaper')
function Test-SceneFields($Actual,$Expected,[string]$Name){
 foreach($f in $productFields){
  $a=ConvertTo-Json -InputObject $Actual.$f -Compress;$e=ConvertTo-Json -InputObject $Expected.$f -Compress
  Assert ($a -ceq $e) ($Name+': '+$f+' actual='+$a+' captured='+$e)
 }
}
# Captured apply run: taskbar was auto-hidden, no pixels, success reported.
$captured=Read-SceneResult 'theme_apply_autohidden_result.json'
[NUC8Theme]::ReadOk=$true;[NUC8Theme]::AutoHidden=$true
$r=Invoke-SetupThemeSettings -ModuleRoot $module
Test-SceneFields $r $captured 'captured auto-hidden apply replays'
# Captured later VerifyOnly run on the same machine: taskbar visible, sampled dark, pixels verified.
$captured=Read-SceneResult 'theme_verify_visible_result.json'
[NUC8Theme]::AutoHidden=$false
$r=Invoke-SetupThemeSettings -ModuleRoot $module -VerifyOnly
Assert ($r.TaskbarPixelsVerified -eq $true -and $r.TaskbarAppearanceStatus -ceq 'Visible') 'captured visible verify replays as verified dark taskbar'
foreach($f in @('Success','AppsMode','WindowsMode','Background','TaskbarAppearanceStatus','TaskbarPixelsVerified','ExplorerReloaded','ActualBackgroundColor','ActualWallpaper')){Assert ((ConvertTo-Json -InputObject $r.$f -Compress) -ceq (ConvertTo-Json -InputObject $captured.$f -Compress)) ('captured visible verify: '+$f)}
