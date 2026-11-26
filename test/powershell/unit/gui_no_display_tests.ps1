#Requires -Version 5.1
# 現場重放（#448）：沒有螢幕時，螢幕與圖示入口只顯示 worker 退出碼。NUC 實機擷取、來源與限制見 fixtures/nuc_no_display_scene/readme.md。
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:failures=@()
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){$script:failures+=$Name}}
. (Join-Path $root 'core/gui_stage_library.ps1')
$scenes=@((Get-Content -LiteralPath (Join-Path $root 'test/powershell/fixtures/nuc_no_display_scene/scene.json') -Raw -Encoding UTF8|ConvertFrom-Json).Scenes)
$scene=$scenes[0]
Add-Type -TypeDefinition @'
using System;
namespace NUC8Display{public static class Display{public static uint W=1920,H=1080,Scale=100;public static int Applied,Scaled,Reads;public static uint[] ReadSnapshot(){Reads++;return new uint[]{W,H,Scale};}public static uint[] Apply(){Applied++;return new uint[]{W,H,1920,1080,0,96};}public static uint[] NativeScales(bool apply){Scaled++;return new uint[]{100};}}}
namespace NUC8Icons{public class Icon{public int Index;public string Name;public int X;public int Y;}public class Layout{public int Width;public int Height;public Icon[] Icons;}public static class Desktop{public static Layout Frame;public static int Moves,Captures;public static Layout Capture(){Captures++;return Frame;}public static void Position(int i,int x,int y){Moves++;}}}
'@
$script:ids=@('{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}','{20D04FE0-3AEA-1069-A2D8-08002B30309D}','{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}','{645FF040-5081-101B-9F08-00AA002F954E}')
$template=Get-Content -LiteralPath (Join-Path $root 'modules/desktop/desktop_layout.json') -Raw -Encoding UTF8|ConvertFrom-Json
function Set-Frame([int]$Width,[int]$Height,$Icons=$template.Icons){
 $layout=New-Object NUC8Icons.Layout;$layout.Width=$Width;$layout.Height=$Height;$i=0
 $layout.Icons=@(foreach($icon in $Icons){New-Object NUC8Icons.Icon -Property @{Index=$i;Name=$icon.Name;X=$icon.X;Y=$icon.Y};$i++})
 [NUC8Icons.Desktop]::Frame=$layout
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gui_no_display_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$package=Join-Path $temp 'package'
foreach($file in @(Get-SetupGuiStageFiles Display)+@(Get-SetupGuiStageFiles Icons)+@('modules/desktop/desktop_layout.json')){$to=Join-Path $package $file;[void][IO.Directory]::CreateDirectory((Split-Path $to));Copy-Item -LiteralPath (Join-Path $root $file) -Destination $to -Force}
$templatePath=Join-Path $package 'modules/desktop/desktop_layout.json';$templateText=[IO.File]::ReadAllText($templatePath)
$sid='S-1-5-21-1-2-3-1001'
$script:session=0;$script:tasks=@{};$script:exitCode=0;$script:forceExit=$null;$script:mutate=$null;$script:writes=0;$script:pnp='Present';$script:pnpQueries=0;$script:factsFail=$false
function Get-SetupGuiIdentity {[pscustomobject]@{CommonDataRoot=$temp;UserSID=$sid;SessionId=$script:session;Computer='fixture';PowerShell='fixture powershell.exe'}}
function Assert-SetupGuiAncestors {param($CommonDataRoot) if($CommonDataRoot -ne $temp){throw 'wrong fixture parent'}}
function New-SetupGuiProtectedDirectory {param($Path,$UserSid) if(-not $Path.StartsWith($temp)){throw 'outside TEMP'};[void][IO.Directory]::CreateDirectory($Path)}
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory,$UserSid) if(-not $Path.StartsWith($temp) -or -not(Microsoft.PowerShell.Management\Test-Path -LiteralPath $Path)){throw 'outside protected fixture'}}
# PnP 查詢替身：Present=有螢幕，None=實機查到 0 筆，Phantom=回傳目前不在的裝置，Fail=查詢失敗，Malformed=裝置沒有可用的存在狀態。
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction)
 if($ClassName -eq 'Win32_PnPEntity'){
  $script:pnpQueries++
  if($Filter -notlike '*4d36e96e-e325-11ce-bfc1-08002be10318*' -or [string]$ErrorAction -ne 'Stop'){throw 'unexpected monitor query'}
  switch($script:pnp){
   Present{return [pscustomobject]@{Present=$true;Status='OK'}}
   None{return}
   Phantom{return $scene.PnpDevices}
   Fail{throw [InvalidOperationException]('C:\Users\someone\secret '+$sid)}
   Malformed{return [pscustomobject]@{Present=$null;Status='OK'}}
  }
 }
 if($ClassName -eq 'Win32_VideoController'){if($script:factsFail){throw 'facts unavailable'};return @(foreach($mode in $script:video){$size=$mode.Split('x');[pscustomobject]@{CurrentHorizontalResolution=$size[0];CurrentVerticalResolution=$size[1]}})}
 if($Filter -eq "Name='powershell.exe'"){return @()}
 [pscustomobject]@{SessionId=4}
}
# 互動桌面讀到的值；縮放不是 100% 時寬高是 DPI 換算後的值，不能當成實際解析度。
function Get-SetupGuiDesktopFacts {if($script:factsFail){throw 'facts unavailable'};[pscustomobject]@{MonitorCount=$scene.MonitorCount;Width=$scene.PrimaryWidth;Height=$scene.PrimaryHeight}}
function Invoke-CimMethod {param($InputObject,$MethodName,$ErrorAction) [pscustomobject]@{ReturnValue=0;Sid=$sid}}
function Get-ScheduledTask {param($TaskName,$ErrorAction) if($script:tasks.ContainsKey($TaskName)){[pscustomobject]@{State='Ready'}}}
function Get-ScheduledTaskInfo {param($TaskName,$ErrorAction) [pscustomobject]@{LastTaskResult=$script:exitCode}}
function New-ScheduledTaskAction {param($Execute,$Argument) [pscustomobject]@{Argument=$Argument}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) [pscustomobject]@{}}
function Register-ScheduledTask {param($TaskName,$Action,$Principal,$ErrorAction) $script:tasks[$TaskName]=$Action}
function Unregister-ScheduledTask {param($TaskName,[switch]$Confirm,$ErrorAction) $script:tasks.Remove($TaskName)}
function Start-ScheduledTask {param($TaskName,$ErrorAction)
 if($script:tasks[$TaskName].Argument -notmatch '-File "([^"]+)" -Role (Display|Icons) -RunId ([a-f0-9-]{36})$'){throw 'unexpected fixed worker command'}
 $code=Split-Path (Split-Path $Matches[1] -Parent) -Parent;$role=$Matches[2];$run=$Matches[3];$old=$script:session;$script:session=4;$script:exitCode=0
 try{Invoke-SetupGuiWorker -CodeRoot $code -Role $role -RunId $run|Out-Null}catch{$script:exitCode=1}finally{$script:session=$old}
 if($null -ne $script:forceExit){$script:exitCode=$script:forceExit}
 $script:resultFile=@(Get-ChildItem -LiteralPath (Join-Path (Split-Path $code -Parent) 'data') -Filter '*.json')[0].FullName
 $script:rawResult=[IO.File]::ReadAllText($script:resultFile)|ConvertFrom-Json
 if($script:mutate){$value=[IO.File]::ReadAllText($script:resultFile)|ConvertFrom-Json;if((& $script:mutate $value) -ne 'raw'){[IO.File]::WriteAllText($script:resultFile,($value|ConvertTo-Json -Depth 8))}}
}
function Invoke-SetupGuiLocalWorker {param($Stage,$Scope) Invoke-SetupGuiWorker -CodeRoot $Stage.CodeRoot -Role $Stage.Context.Role -RunId $Stage.Context.RunId|Out-Null}
function Start-Sleep {param($Seconds,$Milliseconds)}
function Test-Path {param($Path,$LiteralPath,$PathType) if($Path -like 'HKCU:*'){return $true};Microsoft.PowerShell.Management\Test-Path @PSBoundParameters}
function New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force) $script:writes++}
function Remove-ItemProperty {param($Path,$Name,$ErrorAction) $script:writes++}
function Set-ItemProperty {param($Path,$Name,$Value) $script:writes++}
function Get-ItemProperty {param($Path,$ErrorAction) [pscustomobject]@{Win8DpiScaling=0;FFlags=3}}
function New-Object {param($TypeName,$ComObject,$ArgumentList,$Property)
 if(-not $ComObject){return (Microsoft.PowerShell.Utility\New-Object @PSBoundParameters)}
 $desktop=[pscustomobject]@{};$desktop|Add-Member ScriptMethod ParseName {param($path) [pscustomobject]@{Name=@('控制台','本機','網路','資源回收筒')[[array]::IndexOf($script:ids,$path.Substring(2))]}}
 $shell=[pscustomobject]@{Desktop=$desktop};$shell|Add-Member ScriptMethod NameSpace {param($id) $this.Desktop};return $shell
}
function Set-Scene($Pnp,[int]$Width=1920,[int]$Height=1080){
 $script:pnp=$Pnp;$script:forceExit=$null;$script:mutate=$null;$script:factsFail=$false;$script:writes=0;$script:pnpQueries=0;$script:session=0;$script:exitCode=0
 [NUC8Display.Display]::W=$Width;[NUC8Display.Display]::H=$Height;[NUC8Display.Display]::Applied=0;[NUC8Display.Display]::Scaled=0
 [NUC8Icons.Desktop]::Moves=0;[NUC8Icons.Desktop]::Captures=0;Set-Frame $Width $Height;[NUC8Display.Display]::Scale=100;$script:video=@($scene.Video)
 [IO.File]::WriteAllText($templatePath,$templateText,[Text.UTF8Encoding]::new($true))
}
function Set-Headless($Pnp='None'){
 $size=$scene.Video[0].Split('x');Set-Scene $Pnp ([int]$size[0]) ([int]$size[1]);[NUC8Display.Display]::Scale=$scene.ScalePercent
 if($scene.DesktopIcons){Set-Frame ([int]$size[0]) ([int]$size[1]) $scene.DesktopIcons}
}
function Invoke-Case($Role,$Mode='Verify'){
 $script:failure=$null;$script:result=$null;$script:rawResult=$null
 try{$script:result=if($Role -eq 'Display'){Invoke-SetupGuiRole -PackageRoot $package -Role Display -VerifyOnly:($Mode -eq 'Verify')}else{Invoke-SetupGuiRole -PackageRoot $package -Role Icons -VerifyOnly:($Mode -eq 'Verify') -IconMode $Mode}}catch{$script:failure=$_}
 if($script:failure){$script:failure.Exception.Message}else{''}
}
function Test-Typed {$null -ne $script:failure -and $script:failure.Exception.Data['SetupGuiStatus'] -ceq 'Unverified'}
$noDisplay='未偵測到螢幕，無法驗收解析度與圖示';$exitText='GUI worker排程退出碼不是0：1'

# 1. 兩個實機擷取：沒有螢幕、worker 退出碼 1；640x480 縮放 100%，以及 1920x1080 縮放 150%。
foreach($scene in $scenes){foreach($kind in 'None','Phantom'){foreach($case in @(,@('Display','Verify'))+@(,@('Display','Load'))+@(,@('Icons','Verify'))+@(,@('Icons','Load'))+@(,@('Icons','Save'))){
 Set-Headless $kind;$m=Invoke-Case $case[0] $case[1];$label=$scene.Name+' '+$kind+' '+$case[0]+' '+$case[1]
 Write-Host ('scene '+$label+' exit='+$script:exitCode+' message='+$m)
 Assert ($script:exitCode -eq $scene.WorkerExitCode) ('現場型態：worker 以非零退出，不算通過：'+$label)
 Assert ($m.Contains($noDisplay) -and $m -cne $scene.UnfixedMessage) ('沒有螢幕時入口明確顯示未偵測到螢幕：'+$label)
 Assert ($m.Contains('目前解析度 '+$scene.Video[0].Replace('x','×')+'，') -and $m.Contains('實體螢幕 0') -and $m.Contains('Windows 螢幕數 1')) ('沒有螢幕時列出實際解析度（不是 DPI 換算值）、實體螢幕數與 Windows 螢幕數：'+$label)
 Assert (Test-Typed) ('沒有螢幕時入口標示未驗證：'+$label)
 Assert ($script:rawResult.Success -eq $false -and $script:rawResult.Status -ceq 'Unverified' -and $script:rawResult.DisplayState -ceq 'NoDisplay' -and $null -eq $script:result) ('本輪結果為未驗證且沒有成功結果：'+$label)
 Assert ([NUC8Display.Display]::Applied -eq 0 -and [NUC8Display.Display]::Scaled -eq 0 -and [NUC8Icons.Desktop]::Moves -eq 0 -and [NUC8Icons.Desktop]::Captures -eq 0 -and $script:writes -eq 0) ('沒有螢幕時不套用解析度、不移動圖示、不寫登錄：'+$label)
 Assert ([IO.File]::ReadAllText($templatePath) -ceq $templateText) ('沒有螢幕時不覆寫圖示範本：'+$label)
}}}
# 同一擷取改為有螢幕：worker 原因必須和實機未修版結果檔記錄的一致，且入口帶得出來。
foreach($scene in $scenes){foreach($role in 'Display','Icons'){
 $captured=if($role -eq 'Display'){$scene.UnfixedDisplayResult}else{$scene.UnfixedIconsResult}
 Set-Headless 'Present';$m=Invoke-Case $role;Write-Host ('captured '+$scene.Name+' '+$role+' message='+$m)
 Assert ($script:exitCode -eq $scene.WorkerExitCode -and $script:rawResult.Success -eq $false -and $script:rawResult.Error -ceq $captured.Error) ('重放 worker 寫出與實機相同的原因：'+$scene.Name+' '+$role)
 Assert ($m -ceq ($scene.UnfixedMessage+'；原因：'+$captured.Error)) ('入口帶出實機記錄的原因：'+$scene.Name+' '+$role)
 if($role -eq 'Icons'){Assert ($script:rawResult.Mode -ceq 'Verify') ('圖示失敗結果帶本輪模式：'+$scene.Name)}
}}
$scene=$scenes[0]
Assert ($null -eq $scene.UnfixedIconsResult.PSObject.Properties['Mode']) '實機未修版的圖示例外結果確實缺少模式'
Set-Headless;$script:video=@('640x480','x','1920x1080','640x480');$m=Invoke-Case 'Display';Assert ($m.Contains('目前解析度 640×480、1920×1080，')) '多個顯示介面列出各自解析度，略過沒有值的介面並去除重複'
Set-Headless;$script:video=@('x');$m=Invoke-Case 'Display';Assert ($m.Contains('目前解析度 未知')) '顯示介面都沒有解析度時標示未知'
foreach($role in 'Display','Icons'){Set-Scene 'None';$m=Invoke-Case $role;Assert ($m.Contains($noDisplay) -and $null -eq $script:result) ('沒有螢幕時即使解析度相符也不標通過：'+$role)}
foreach($role in 'Display','Icons'){Set-Headless;$script:session=4;$m=Invoke-Case $role;Assert ($m.Contains($noDisplay) -and (Test-Typed)) ('互動工作階段同樣回報未偵測到螢幕：'+$role)}
Set-Headless;$script:factsFail=$true;$m=Invoke-Case 'Display';Assert ($m.Contains($noDisplay) -and $m.Contains('解析度 未知') -and $m.Contains('螢幕數 未知')) '讀不到目前解析度與螢幕數時標示未知，仍回報未偵測到螢幕'

# 2. 查詢失敗與沒有螢幕分開。
foreach($kind in 'Fail','Malformed'){foreach($case in @(,@('Display','Verify'))+@(,@('Display','Load'))+@(,@('Icons','Verify'))+@(,@('Icons','Load'))){
 Set-Scene $kind;$m=Invoke-Case $case[0] $case[1];$label=$kind+' '+$case[0]+' '+$case[1]
 Write-Host ('query '+$label+' message='+$m)
 Assert ($m.Contains('螢幕查詢失敗') -and -not $m.Contains('未偵測到螢幕') -and (Test-Typed)) ('查詢失敗與沒有螢幕分開並標未驗證：'+$label)
 Assert ($script:rawResult.DisplayState -ceq 'QueryFailed' -and $null -eq $script:result) ('查詢失敗的本輪結果不是沒有螢幕：'+$label)
 Assert ([NUC8Display.Display]::Applied -eq 0 -and [NUC8Icons.Desktop]::Moves -eq 0 -and $script:writes -eq 0) ('查詢失敗時不套用：'+$label)
 Assert (@(@($m,[string]$script:rawResult.Error)|Where-Object {$_.Contains('someone') -or $_.Contains($sid) -or $_.Contains('C:\')}).Count -eq 0) ('查詢失敗訊息與本輪結果檔都不含路徑或 SID：'+$label)
 Assert ($m.Contains($(if($kind -eq 'Fail'){'（InvalidOperationException）'}else{'（裝置存在狀態格式不符）'}))) ('查詢失敗只列固定分類：'+$label)
}}

# 3. 有螢幕：原判定不變。
Set-Scene 'Present';$m=Invoke-Case 'Display';Assert ($m -eq '' -and $script:result.Success -eq $true -and $null -eq $script:result.PSObject.Properties['Status']) '有螢幕且 1920×1080 時驗收仍通過'
Assert ($script:pnpQueries -eq 1) '驗收前只查詢一次螢幕'
Set-Scene 'Present';$m=Invoke-Case 'Display' 'Load';Assert ($m -eq '' -and [NUC8Display.Display]::Applied -eq 1) '有螢幕時仍套用解析度'
Set-Scene 'Present';$m=Invoke-Case 'Icons';Assert ($m -eq '' -and $script:result.Success -eq $true -and [NUC8Icons.Desktop]::Moves -eq 0) '有螢幕時圖示驗收仍通過且不移動'
Set-Scene 'Present';$m=Invoke-Case 'Icons' 'Load';Assert ($m -eq '' -and [NUC8Icons.Desktop]::Moves -eq 4) '有螢幕時仍套用圖示排列'
Set-Headless 'Present';$m=Invoke-Case 'Display';Write-Host ('present Display 640x480 message='+$m)
Assert ($m.Contains($exitText) -and $m.Contains('解析度或實際 DPI 尚未符合') -and -not $m.Contains('未偵測到螢幕') -and -not (Test-Typed)) '有螢幕但解析度不符：帶出解析度原因，不寫成沒有螢幕'
Set-Headless 'Present';$m=Invoke-Case 'Icons';Write-Host ('present Icons 640x480 message='+$m)
Assert ($m.Contains($exitText) -and $m.Contains('桌面範圍與範本不同') -and -not (Test-Typed)) '有螢幕但桌面範圍不符：帶出圖示 worker 例外的原因'
Set-Headless 'Present';$null=Invoke-Case 'Icons' 'Load';Assert ([NUC8Icons.Desktop]::Moves -eq 0 -and $script:rawResult.Mode -ceq 'Load') '圖示 worker 例外結果帶本輪模式，範圍不符不移動'

# 4. worker 失敗原因的取得與邊界。
Set-Scene 'Present';$script:forceExit=1;$m=Invoke-Case 'Display';Assert ($m.Contains($exitText) -and $null -eq $script:result -and $m.Contains('與退出碼不符')) '結果寫成功但退出碼不是0：仍失敗，不放寬'
Set-Scene 'Present';$script:forceExit=3221225786;$m=Invoke-Case 'Icons';Assert ($m.Contains('3221225786') -and $null -eq $script:result) '任何非零退出碼都保留並失敗'
foreach($empty in @($null,'','   ')){Set-Headless 'Present';$script:mutate={param($v) $v.Error=$empty};$m=Invoke-Case 'Display';Assert ($m.Contains($exitText) -and $m.Contains('worker 未寫入具體原因') -and -not $m.Contains('未偵測到螢幕')) ('worker 沒有寫原因時如實說明：['+$empty+']')}
Set-Headless 'Present';$script:mutate={param($v) $v.PSObject.Properties.Remove('Error')};$m=Invoke-Case 'Display';Assert ($m.Contains('worker 未寫入具體原因')) 'worker 結果沒有原因欄位時如實說明'
Set-Headless 'Present';$script:mutate={param($v) $v.RunId=[guid]::NewGuid().ToString('D');$v.Error='stale reason'};$m=Invoke-Case 'Display';Assert ($m.Contains($exitText) -and $m.Contains('worker 結果無法驗證') -and -not $m.Contains('stale reason')) '他輪結果的原因不採信'
Set-Headless 'Present';$script:mutate={param($v) [IO.File]::WriteAllText($script:resultFile,'not json');'raw'};$m=Invoke-Case 'Display';Assert ($m.Contains($exitText) -and $m.Contains('worker 結果無法驗證')) '結果檔損壞時保留退出碼並說明無法驗證'
foreach($forged in @(@{Success=$true},@{DisplayState='Other'},@{Error=''},@{Status='Confirmed'})){
 Set-Headless;$script:mutate={param($v) foreach($key in $forged.Keys){$v|Add-Member -NotePropertyName $key -NotePropertyValue $forged[$key] -Force}};$m=Invoke-Case 'Display'
 Assert ($m.Contains('worker 結果無法驗證') -and -not (Test-Typed) -and $null -eq $script:result) ('未驗證結果格式不符時不採信：'+(($forged.Keys|ForEach-Object {$_+'='+$forged[$_]}) -join ','))
}
Set-Headless;$script:mutate={param($v) $v.Success=$true};$script:forceExit=0;$m=Invoke-Case 'Display';Assert ($m -ne '' -and $null -eq $script:result) '未驗證結果被改成成功且退出碼為 0 也不通過'
Set-Headless;$script:forceExit=0;$m=Invoke-Case 'Display';Assert ($m.Contains($noDisplay) -and (Test-Typed) -and $null -eq $script:result) '未驗證結果即使退出碼為 0 也不通過'

# 5. 原因去識別。
$user=[Environment]::UserName;$machine=[Environment]::MachineName
$samples=@(
 @{In="無法讀取 'C:\Users\王 小明\Desktop\a.lnk'，存取被拒";Keep=@('無法讀取','存取被拒');Drop=@('王','小明','Desktop','C:\')},
 @{In="Cannot find path 'C:\Users\O'Brien\x' because it does not exist.";Keep=@('Cannot find path','because it does not exist');Drop=@('Brien','C:\')},
 @{In='來源 D:/kit folder/模組 有問題';Keep=@('來源');Drop=@('kit','folder','D:/')},
 @{In='來源 \\server\share\kit 無法讀取';Keep=@('來源');Drop=@('server','share')},
 @{In='來源不接受重新解析點：\\?\C:\Users\someone\kit';Keep=@('來源不接受重新解析點');Drop=@('someone','kit','C:\')},
 @{In='擁有者 S-1-5-21-111-222-333-1001 不符';Keep=@('擁有者','不符');Drop=@('S-1-5-21','1001')},
 @{In=('帳號 '+$machine+'\'+$user+' 沒有權限');Keep=@('帳號','沒有權限');Drop=@($machine,$user)},
 @{In=('使用者 '+$user.ToUpperInvariant()+' 在 '+$machine+' 失敗');Keep=@('使用者','失敗');Drop=@($user,$machine)},
 @{In='帳號 someone@example.com 無效';Keep=@('帳號','無效');Drop=@('someone','example')},
 @{In='帳號 CORP\other.user 無效';Keep=@('帳號','無效');Drop=@('CORP','other')},
 @{In='登錄 HKCU:\Control Panel\Desktop 讀取失敗';Keep=@('HKCU:\Control Panel\Desktop','讀取失敗');Drop=@()},
 @{In='解析度或實際 DPI 尚未符合 1920×1080 / 100%，可能需要重新登入。';Keep=@('解析度或實際 DPI 尚未符合 1920×1080 / 100%，可能需要重新登入。');Drop=@()}
)
$number=0
foreach($sample in $samples){
 $number++;$text=$sample.In;Set-Headless 'Present';$script:mutate={param($v) $v.Error=$text};$m=Invoke-Case 'Display'
 Assert ($m.Contains($exitText) -and @($sample.Keep|Where-Object {-not $m.Contains($_)}).Count -eq 0) ('保留可讀原因：第 '+$number+' 例')
 Assert (@($sample.Drop|Where-Object {$m.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0}).Count -eq 0) ('原因不含帳號、SID 或路徑：第 '+$number+' 例')
}
Set-Headless 'Present';$script:mutate={param($v) $v.Error="第一行`r`n第二行"};$m=Invoke-Case 'Display';Assert ($m.Contains('第一行 第二行')) '多行原因併成單行'
Set-Headless 'Present';$script:mutate={param($v) $v.Error='甲'*5000};$m=Invoke-Case 'Display';Assert ($m.Contains('甲') -and $m.Length -lt 700) '原因有長度上限'
if($temp.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
if($script:failures.Count){throw ('FAIL '+$script:failures.Count+'：'+$script:failures[0])}
Write-Host 'ALL PASS: no-display scene replay; native, PnP and scheduler boundaries mocked'
