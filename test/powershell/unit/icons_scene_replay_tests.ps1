#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'modules/desktop/icons_settings_library.ps1')
function Get-SetupSystemIconNames {@('本機','網路','資源回收筒','控制台')}
# 重放 NUC8 現場擷取（去識別，來源與缺漏見 fixtures/nuc_icons_scene/readme.md）。Capture 依序回傳「套用前」與「套用後」畫面；Position 為記錄用空操作。
Add-Type -TypeDefinition @'
using System;using System.Collections.Generic;using System.Linq;
namespace NUC8Icons{
public class Icon{public int Index;public string Name;public int X;public int Y;}
public class Layout{public int Width;public int Height;public bool AutoArrange;public Icon[] Icons;}
public static class Desktop{
 public static Queue<Layout> Frames=new Queue<Layout>();public static Layout Last;public static int Moves;
 public static bool Scene;public static Layout Initial,AfterFirst,AfterRetry;
 public static Layout Capture(){if(Scene)return Moves==0?Initial:(Moves<=4?AfterFirst:AfterRetry);if(Frames.Count>0)Last=Frames.Dequeue();return Last;}
 public static void Position(int index,int x,int y){Moves++;}
}}
'@
function Get-Fixture($name){Get-Content -LiteralPath (Join-Path $root "test/powershell/fixtures/nuc_icons_scene/$name") -Raw -Encoding UTF8|ConvertFrom-Json}
function New-Frame($icons){$l=New-Object NUC8Icons.Layout;$l.Width=1920;$l.Height=1080;$i=0;$l.Icons=@(foreach($n in $icons){New-Object NUC8Icons.Icon -Property @{Index=$i++;Name=$n.Name;X=[int]$n.X;Y=[int]$n.Y}});$l}
function Get-ItemProperty {param($Path,$ErrorAction) [pscustomobject]@{FFlags=3}}
function Set-ItemProperty {param($Path,$Name,$Value)}
function Start-Sleep {param($Milliseconds)}
$reference=Get-Content -LiteralPath (Join-Path $root 'modules/desktop/desktop_layout.json') -Raw -Encoding UTF8|ConvertFrom-Json
$setup=Get-Fixture 'setup_run_load_result.json'
# 套用前座標未擷取：以套用後畫面作佔位（Position 為空操作，不影響結論），只重放實機讀回症狀。
[NUC8Icons.Desktop]::Frames.Enqueue((New-Frame $setup.Actual));[NUC8Icons.Desktop]::Frames.Enqueue((New-Frame $setup.Actual))
$r=Invoke-SetupIconsSettings -ModuleRoot (Join-Path $root 'modules/desktop') -Mode Load -Reference $reference
Assert (-not $r.Success -and ($r.Differences -join ',') -eq (($setup.Differences) -join ',') -and $r.Error -eq $setup.Error) '現場讀回 (14,198) 時如實回報與實機相同的「位置不符：本機」'
$a=@($r.Actual|Where-Object Name -eq '本機')[0]
Assert ($a.X -eq 14 -and $a.Y -eq 198) '回報的實際座標即現場讀回，不被改寫'
# 套用前（Verify）現場畫面：本機 (14,202) 超出容差，必須回報不符且不移動。
$before=Get-Fixture 'stage_before_verify_result.json'
[NUC8Icons.Desktop]::Moves=0;[NUC8Icons.Desktop]::Frames.Enqueue((New-Frame $before.Actual))
$r=Invoke-SetupIconsSettings -ModuleRoot (Join-Path $root 'modules/desktop') -Mode Verify -Reference $reference
Assert (-not $r.Success -and ($r.Differences -join ',') -eq (($before.Differences) -join ',') -and [NUC8Icons.Desktop]::Moves -eq 0) '現場 Verify 畫面 (14,202) 如實回報位置不符且不移動'
# 目標格被佔用的現場重放（occupied_target_cell_scene.json）：Capture 依已送出的 Position 次數回傳實機觀察到的畫面。
# 起始畫面 → 第一輪四次 Position 後為「未修版 Load 後」→ 之後再有 Position（補套用）為「含補套用 Load 後」。
$scene=Get-Fixture 'occupied_target_cell_scene.json'
[NUC8Icons.Desktop]::Scene=$true;[NUC8Icons.Desktop]::Moves=0
[NUC8Icons.Desktop]::Initial=New-Frame $scene.Initial;[NUC8Icons.Desktop]::AfterFirst=New-Frame $scene.AfterUnfixedLoad;[NUC8Icons.Desktop]::AfterRetry=New-Frame $scene.AfterFixedLoad
$r=Invoke-SetupIconsSettings -ModuleRoot (Join-Path $root 'modules/desktop') -Mode Load -Reference $reference
Assert ($r.Success -and $r.Differences.Count -eq 0) '現場「目標格被佔用」：Load 後須讀回四個圖示全部符合範本'
$mine=@($r.Actual|Where-Object Name -eq '本機')[0]
Assert ($mine.X -eq 14 -and $mine.Y -eq 100) '現場「目標格被佔用」：本機最終位於 (14,100)'
