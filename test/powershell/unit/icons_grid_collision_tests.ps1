#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'modules/desktop/icons_settings_library.ps1')
function Get-SetupSystemIconNames {@('本機','網路','資源回收筒','控制台')}
# 合成替身：貼齊格線（欄 x=14,90；列 y=2,100,198,...），目標格被其他圖示佔用時推到同欄下一個空格。
Add-Type -TypeDefinition @'
using System;using System.Collections.Generic;using System.Linq;
namespace NUC8Icons{
public class Icon{public int Index;public string Name;public int X;public int Y;}
public class Layout{public int Width;public int Height;public bool AutoArrange;public Icon[] Icons;}
public static class Desktop{
 public static List<Icon> State=new List<Icon>();public static int Moves;
 static int[] Cols={14,90};
 public static Layout Capture(){return new Layout{Width=1920,Height=1080,Icons=State.Select(i=>new Icon{Index=i.Index,Name=i.Name,X=i.X,Y=i.Y}).ToArray()};}
 public static void Position(int index,int x,int y){
  Moves++;int col=Cols.OrderBy(c=>Math.Abs(c-x)).First();int row=Math.Max(0,(int)Math.Round((y-2)/98.0));
  Icon me=State.First(i=>i.Index==index);
  while(State.Any(o=>o!=me&&o.X==col&&o.Y==2+row*98))row++;
  me.X=col;me.Y=2+row*98;}
}}
'@
function Set-Initial($items){[NUC8Icons.Desktop]::State.Clear();[NUC8Icons.Desktop]::Moves=0;$i=0;foreach($n in $items.Keys){$p=$items[$n];[NUC8Icons.Desktop]::State.Add((New-Object NUC8Icons.Icon -Property @{Index=$i;Name=$n;X=$p[0];Y=$p[1]}));$i++}}
function Get-ItemProperty {param($Path,$ErrorAction) [pscustomobject]@{FFlags=3}}
function Set-ItemProperty {param($Path,$Name,$Value)}
function Start-Sleep {param($Milliseconds)}
$reference=[pscustomobject]@{Width=1920;Height=1080;Icons=@(
 [pscustomobject]@{Name='本機';X=14;Y=102},[pscustomobject]@{Name='網路';X=90;Y=102},
 [pscustomobject]@{Name='資源回收筒';X=14;Y=2},[pscustomobject]@{Name='控制台';X=90;Y=2})}
# 實機初始：資源回收筒 (14,2)、網路 (14,100)、本機 (14,198)、控制台 (90,2)
Set-Initial ([ordered]@{'本機'=@(14,198);'網路'=@(14,100);'資源回收筒'=@(14,2);'控制台'=@(90,2)})
$r=Invoke-SetupIconsSettings -ModuleRoot (Join-Path $root 'modules/desktop') -Mode Load -Reference $reference
Assert ($r.Success -and $r.Differences.Count -eq 0) 'Load 目標格先被其他圖示佔用時，補套用後仍須讀回全部符合'
$mine=@($r.Actual|Where-Object Name -eq '本機')[0]
Assert ($mine.X -eq 14 -and $mine.Y -eq 100) '本機最終位於貼齊後的目標格 (14,100)'
# 兩個範本座標貼齊後落在同一格（無法收斂）時，仍須如實回報位置不符，且補套用次數有上限
Set-Initial ([ordered]@{'本機'=@(14,198);'網路'=@(14,100);'資源回收筒'=@(14,2);'控制台'=@(90,2)})
$permanent=[pscustomobject]@{Width=1920;Height=1080;Icons=@([pscustomobject]@{Name='本機';X=14;Y=102},[pscustomobject]@{Name='網路';X=14;Y=100},[pscustomobject]@{Name='資源回收筒';X=14;Y=2},[pscustomobject]@{Name='控制台';X=90;Y=2})}
$r=Invoke-SetupIconsSettings -ModuleRoot (Join-Path $root 'modules/desktop') -Mode Load -Reference $permanent
Assert (-not $r.Success -and $r.Differences.Count -ge 1 -and [NUC8Icons.Desktop]::Moves -le 12) '無法收斂的位置衝突仍回報位置不符且補套用有上限'
