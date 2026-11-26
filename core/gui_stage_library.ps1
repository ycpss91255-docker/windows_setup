#Requires -Version 5.1
# Definitions only. No directories, ACLs or tasks are changed when this file is loaded.
function Assert-SetupGuiPlainPath {
 param([Parameter(Mandatory=$true)][string]$Path)
 $cursor=[IO.Path]::GetFullPath($Path)
 if($cursor -notmatch '^[a-zA-Z]:\\'){throw 'GUI workerstage必須使用本機絕對磁碟路徑。'}
 while($cursor){
  if(Test-Path -LiteralPath $cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('GUI worker來源不接受重新解析點：'+$cursor)}}
  $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
 }
}
function New-SetupGuiDirectorySecurity {
 param([string]$UserSid)
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false)
 $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
 foreach($id in @('S-1-5-18','S-1-5-32-544')){$sid=New-Object Security.Principal.SecurityIdentifier($id);$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))}
 if($UserSid){$sid=New-Object Security.Principal.SecurityIdentifier($UserSid);$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')))}
 return $acl
}
function Assert-SetupGuiAcl {
 param([Parameter(Mandatory=$true)]$Acl,[switch]$Directory,[switch]$Ancestor,[string]$UserSid)
 $trusted=@('S-1-5-18','S-1-5-32-544')
 $owners=@($trusted)
 if($Ancestor){try{$owners+=@((New-Object Security.Principal.NTAccount('NT SERVICE','TrustedInstaller')).Translate([Security.Principal.SecurityIdentifier]).Value)}catch{}}
 $owner=$Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
 if($owner -notin $owners){throw 'GUI worker路徑擁有者不可信，保留原資料並拒絕接管。'}
 $rules=@($Acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
 if($Ancestor){
  $danger=[Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
  foreach($rule in $rules){
   if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $owners -and -not($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -and ($rule.FileSystemRights -band $danger)){throw 'GUI worker父目錄允許非可信身分刪除或替換子目錄，拒絕使用。'}
  }
  return
 }
 if($Directory -and -not $Acl.AreAccessRulesProtected){throw 'GUI worker目錄ACL未停用繼承。'}
 if($Directory -and $UserSid -and $owner -cne 'S-1-5-32-544'){throw 'GUI worker data目錄擁有者必須是管理員群組。'}
 $readOnly=[Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [Security.AccessControl.FileSystemRights]::Synchronize
 foreach($rule in $rules){
  if($rule.AccessControlType -ne 'Allow'){throw 'GUI worker來源ACL含非預期存取規則。'}
  if($rule.IdentityReference.Value -in $trusted){continue}
  if(-not $UserSid -or $rule.IdentityReference.Value -cne $UserSid -or ($rule.FileSystemRights -band (-bnot $readOnly)) -ne 0){throw 'GUI worker來源ACL含非預期存取規則。'}
 }
 if($UserSid -and -not @($rules|Where-Object {$_.IdentityReference.Value -ceq $UserSid -and ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::ReadAndExecute) -eq [Security.AccessControl.FileSystemRights]::ReadAndExecute -and -not($_.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly)}).Count){throw 'GUI worker data ACL缺少原使用者讀取權限。'}
 foreach($sid in $trusted){
  $matches=@($rules|Where-Object {$_.IdentityReference.Value -eq $sid -and ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl -and -not($_.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly)})
  if(-not $matches.Count){throw 'GUI worker來源ACL缺少SYSTEM或管理員完整權限。'}
  if($Directory -and -not @($matches|Where-Object {$_.InheritanceFlags -eq ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit) -and $_.PropagationFlags -eq [Security.AccessControl.PropagationFlags]::None}).Count){throw 'GUI worker目錄ACL缺少子檔繼承保護。'}
 }
}
function Assert-SetupGuiProtectedPath {
 param([Parameter(Mandatory=$true)][string]$Path,[switch]$Directory,[string]$UserSid)
 Assert-SetupGuiPlainPath $Path
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if([bool]$item.PSIsContainer -ne [bool]$Directory){throw 'GUI workerstage檔案或目錄類型不符。'}
 Assert-SetupGuiAcl -Acl (Get-Acl -LiteralPath $Path -ErrorAction Stop) -Directory:$Directory -UserSid $UserSid
}
function Assert-SetupGuiAncestors {
 param([Parameter(Mandatory=$true)][string]$CommonDataRoot)
 Assert-SetupGuiPlainPath $CommonDataRoot
 $cursor=[IO.Path]::GetFullPath($CommonDataRoot)
 while($cursor){
  $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
  if(-not $item.PSIsContainer){throw 'GUI worker父路徑不是目錄。'}
  Assert-SetupGuiAcl -Acl (Get-Acl -LiteralPath $cursor -ErrorAction Stop) -Ancestor
  $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
 }
}
function New-SetupGuiProtectedDirectory {
 param([Parameter(Mandatory=$true)][string]$Path,[string]$UserSid)
 Assert-SetupGuiPlainPath $Path
 if(-not(Test-Path -LiteralPath $Path)){
  $acl=New-SetupGuiDirectorySecurity -UserSid $UserSid
  # The security descriptor is supplied at creation; there is no create-then-protect interval.
  [void][IO.Directory]::CreateDirectory($Path,$acl)
 }
 Assert-SetupGuiProtectedPath -Path $Path -Directory -UserSid $UserSid
}
function Assert-SetupIconReference {
 param($Reference)
 if($null -eq $Reference -or $Reference.Width -isnot [int] -or $Reference.Height -isnot [int] -or $Reference.Width -le 0 -or $Reference.Height -le 0 -or @($Reference.Icons).Count -ne 4){throw '圖示範本必須包含有效尺寸與四個唯一圖示。'}
 $names=@()
 foreach($icon in $Reference.Icons){if($icon.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($icon.Name) -or $icon.X -isnot [int] -or $icon.Y -isnot [int]){throw '圖示範本名稱或座標格式不符。'};$names+=@($icon.Name)}
 if(@($names|Select-Object -Unique).Count -ne 4){throw '圖示範本名稱必須唯一。'}
}
function Write-SetupIconReference {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,$Reference)
 Assert-SetupIconReference $Reference
 $path=Join-Path ([IO.Path]::GetFullPath($PackageRoot)) 'modules/desktop/desktop_layout.json'
 Assert-SetupGuiPlainPath $path
 $temporary=Join-Path (Split-Path $path -Parent) ([guid]::NewGuid().ToString('N')+'.tmp')
 try{
  [IO.File]::WriteAllText($temporary,($Reference|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($true))
  Assert-SetupGuiPlainPath $path
  if(Test-Path -LiteralPath $path){[IO.File]::Replace($temporary,$path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$path)}
 }finally{if(Test-Path -LiteralPath $temporary){[IO.File]::Delete($temporary)}}
}
function Get-SetupGuiStageFiles {
 param([string]$Role)
 if($Role -cin @('Taskbar','TaskbarFinalize')){return @('core/gui_stage_library.ps1','core/gui_worker.ps1','modules/taskbar/taskbar_stage_library.ps1','modules/taskbar/taskbar_settings_library.ps1','modules/taskbar/native/taskbar.cs')}
 if($Role -ceq 'Start'){return @('core/gui_stage_library.ps1','core/gui_worker.ps1','modules/start_menu/start_menu_settings_library.ps1','modules/start_menu/start_pins_policy_library.ps1','modules/start_menu/start_pins_asset_library.ps1','modules/start_menu/assets/empty_start.xml','modules/start_menu/assets/empty_start.ppkg','modules/start_menu/assets/provenance.json')}
 if($Role -ceq 'Desktop'){return @('core/gui_stage_library.ps1','core/gui_worker.ps1','modules/desktop/desktop_settings_library.ps1','modules/desktop/desktop_safety.ps1')}
 if($Role -ceq 'Icons'){return @('core/gui_stage_library.ps1','core/gui_worker.ps1','modules/desktop/icons_settings_library.ps1','modules/desktop/native/desktop_icons.cs')}
 if($Role -cnotin @('Explorer','Display','Theme')){throw 'GUI worker角色尚未核准。'}
 $leaf=$Role.ToLowerInvariant()
 return @('core/gui_stage_library.ps1','core/gui_worker.ps1',('modules/'+$leaf+'/'+$leaf+'_settings_library.ps1'),('modules/'+$leaf+'/native/'+$leaf+'.cs'))
}
function Get-SetupGuiRunPaths {
 param([string]$CommonDataRoot,[string]$Role,[string]$RunId)
 $null=Get-SetupGuiStageFiles $Role
 $guid=[guid]::Empty
 if(-not [guid]::TryParse($RunId,[ref]$guid) -or $guid.ToString('D') -cne $RunId){throw 'GUI worker本輪ID格式不符。'}
 $roleRoot=Join-Path (Join-Path ([IO.Path]::GetFullPath($CommonDataRoot)) 'windows_setup_gui') $Role.ToLowerInvariant()
 $runRoot=Join-Path $roleRoot $RunId
 [pscustomobject]@{RoleRoot=$roleRoot;RunRoot=$runRoot;CodeRoot=(Join-Path $runRoot 'code');DataRoot=(Join-Path $runRoot 'data')}
}
function Assert-SetupGuiCaller {
 param([string]$UserSid,[int]$CallerSession,[int]$DesktopSession,[string]$Computer)
 if($UserSid -notmatch '^S-1-(5-21|12-1)-\d+(-\d+)+$' -or [string]::IsNullOrWhiteSpace($Computer)){throw 'GUI worker呼叫身分格式不符。'}
 if($CallerSession -lt 0 -or $DesktopSession -le 0 -or ($CallerSession -gt 0 -and $CallerSession -ne $DesktopSession)){throw 'GUI worker必須對應同一使用者的唯一互動桌面。'}
}
function Write-SetupGuiAtomicJson {
 param([string]$Path,$Value,[string]$UserSid)
 $parent=Split-Path $Path -Parent
 Assert-SetupGuiProtectedPath $parent -Directory -UserSid $UserSid
 if(Test-Path -LiteralPath $Path){Assert-SetupGuiProtectedPath $Path -UserSid $UserSid}
 $temporary=Join-Path $parent ([guid]::NewGuid().ToString('N')+'.tmp')
 [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($true))
 Assert-SetupGuiProtectedPath $temporary -UserSid $UserSid
 if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temporary,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$Path)}
}
function New-SetupGuiStage {
 param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$CommonDataRoot,
 [string]$Role,[string]$UserSid,[int]$CallerSession,[int]$DesktopSession,[string]$Computer,[switch]$VerifyOnly,[string]$RunId=([guid]::NewGuid().ToString('D')),[ValidateSet('Save','Load','Verify')][string]$IconMode='Load',[switch]$ApplyPolicy,[switch]$NonInteractive)
 $ErrorActionPreference='Stop'
 $manifest=@(Get-SetupGuiStageFiles $Role)
 Assert-SetupGuiCaller -UserSid $UserSid -CallerSession $CallerSession -DesktopSession $DesktopSession -Computer $Computer
 Assert-SetupGuiAncestors $CommonDataRoot
 $paths=Get-SetupGuiRunPaths -CommonDataRoot $CommonDataRoot -Role $Role -RunId $RunId
 New-SetupGuiProtectedDirectory (Split-Path $paths.RoleRoot -Parent)
 New-SetupGuiProtectedDirectory $paths.RoleRoot
 $lockPath=Join-Path $paths.RoleRoot 'stage.lock'
 if(Test-Path -LiteralPath $lockPath){Assert-SetupGuiProtectedPath $lockPath}
 try{$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'GUI stage已被另一個程序使用，未複製或啟動工作。'}
 try{
  Assert-SetupGuiProtectedPath $lockPath
  Assert-SetupGuiAncestors $CommonDataRoot
  foreach($path in @($paths.RunRoot,$paths.CodeRoot)){New-SetupGuiProtectedDirectory $path}
  New-SetupGuiProtectedDirectory $paths.DataRoot -UserSid $UserSid
  $files=@()
  foreach($name in $manifest){
   $source=Join-Path $SourceRoot $name;Assert-SetupGuiPlainPath $source
   if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw ('GUI worker來源缺少檔案：'+$name)}
   $expected=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
   $parent=$paths.CodeRoot
   foreach($part in @($name.Split('/')[0..($name.Split('/').Length-2)])){$parent=Join-Path $parent $part;New-SetupGuiProtectedDirectory $parent}
   $target=Join-Path $paths.CodeRoot $name;Assert-SetupGuiPlainPath $target
   if(Test-Path -LiteralPath $target){throw 'GUI worker全新stage已有非預期檔案，拒絕覆寫。'}
   Copy-Item -LiteralPath $source -Destination $target -ErrorAction Stop
   Assert-SetupGuiProtectedPath $target
   if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $expected -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $expected){throw 'GUI worker來源複製前後雜湊不符。'}
   $files+=@([pscustomobject]@{Name=$name;SHA256=$expected.ToLowerInvariant()})
  }
  $context=[pscustomobject][ordered]@{Schema=1;Role=$Role;RunId=(Split-Path $paths.RunRoot -Leaf);Computer=$Computer;CallerSID=$UserSid;CallerSession=$CallerSession;UserSID=$UserSid;DesktopSession=$DesktopSession;VerifyOnly=[bool]$VerifyOnly;Files=$files}
  if($Role -ceq 'Start'){$context|Add-Member ApplyPolicy ([bool]$ApplyPolicy);$context|Add-Member NonInteractive ([bool]($NonInteractive -or ($ApplyPolicy -and $CallerSession -eq 0)))}
  if($Role -ceq 'TaskbarFinalize'){if($VerifyOnly){throw '工作列收尾不能使用驗收模式。'};$context|Add-Member ApplyRunID $context.RunId}
  if($Role -cin @('Desktop','Icons')){$context|Add-Member SourcePackageRoot ([IO.Path]::GetFullPath($SourceRoot))}
  if($Role -ceq 'Icons'){
   if($VerifyOnly){$IconMode='Verify'}elseif($IconMode -ceq 'Verify'){throw '圖示 Verify 必須使用唯讀驗收模式。'}
   $context|Add-Member IconMode $IconMode
   if($IconMode -cne 'Save'){
    $referencePath=Join-Path $SourceRoot 'modules/desktop/desktop_layout.json';Assert-SetupGuiPlainPath $referencePath
    $digest=(Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash
    $reference=Get-Content -LiteralPath $referencePath -Raw -Encoding UTF8|ConvertFrom-Json
    if((Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash -cne $digest){throw '圖示來源範本讀取期間改變。'}
    Assert-SetupIconReference $reference
    $context|Add-Member IconReference $reference
   }
  }
  Write-SetupGuiAtomicJson -Path (Join-Path $paths.CodeRoot 'context.json') -Value $context
  $verified=Read-SetupGuiContext -CodeRoot $paths.CodeRoot -CommonDataRoot $CommonDataRoot -Role $Role -RunId $context.RunId
  [pscustomobject]@{CodeRoot=$paths.CodeRoot;DataRoot=$paths.DataRoot;CommonDataRoot=$CommonDataRoot;Lock=$lock;Context=$verified}
 }catch{$lock.Dispose();throw}
}
function Read-SetupGuiContext {
 param([string]$CodeRoot,[string]$CommonDataRoot,[string]$Role,[string]$RunId)
 $paths=Get-SetupGuiRunPaths -CommonDataRoot $CommonDataRoot -Role $Role -RunId $RunId
 if([IO.Path]::GetFullPath($CodeRoot) -ine $paths.CodeRoot){throw 'GUI worker必須使用固定角色與本輪code目錄。'}
 Assert-SetupGuiAncestors $CommonDataRoot
 Assert-SetupGuiProtectedPath (Split-Path $paths.RoleRoot -Parent) -Directory
 Assert-SetupGuiProtectedPath $paths.RoleRoot -Directory
 Assert-SetupGuiProtectedPath $paths.RunRoot -Directory
 Assert-SetupGuiProtectedPath $CodeRoot -Directory
 $path=Join-Path $CodeRoot 'context.json';Assert-SetupGuiProtectedPath $path
 $context=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
 if($context.Schema -ne 1 -or $context.Role -cne $Role -or $context.RunId -cne $RunId -or $context.CallerSID -cne $context.UserSID -or $context.VerifyOnly -isnot [bool] -or $context.CallerSession -isnot [int] -or $context.DesktopSession -isnot [int]){throw 'GUI worker context身分或格式不符。'}
 Assert-SetupGuiCaller -UserSid $context.UserSID -CallerSession $context.CallerSession -DesktopSession $context.DesktopSession -Computer $context.Computer
 if($Role -ceq 'Start' -and ($context.ApplyPolicy -isnot [bool] -or $context.NonInteractive -isnot [bool])){throw 'GUI worker開始選單模式格式不符。'}
 if($Role -ceq 'TaskbarFinalize' -and ($context.ApplyRunID -cne $context.RunId -or $context.VerifyOnly)){throw 'GUI worker工作列收尾本輪身分不符。'}
 if($Role -cin @('Desktop','Icons')){if([string]::IsNullOrWhiteSpace($context.SourcePackageRoot) -or [IO.Path]::GetFullPath($context.SourcePackageRoot) -cne $context.SourcePackageRoot){throw 'GUI worker原始套件來源格式不符。'};Assert-SetupGuiPlainPath $context.SourcePackageRoot}
 if($Role -ceq 'Icons'){
  if($context.IconMode -cnotin @('Save','Load','Verify') -or ($context.VerifyOnly -ne ($context.IconMode -ceq 'Verify'))){throw 'GUI worker圖示模式不符。'}
  if($context.IconMode -cne 'Save'){Assert-SetupIconReference $context.IconReference}elseif($context.PSObject.Properties['IconReference']){throw '圖示 Save 不可載入 staged 範本。'}
 }
 $expected=@(Get-SetupGuiStageFiles $Role|Sort-Object)
 if(@($context.Files).Count -ne $expected.Count -or (@($context.Files|ForEach-Object Name|Sort-Object) -join '|') -cne ($expected -join '|')){throw 'GUI worker context來源清單不符。'}
 foreach($file in $context.Files){
  if($file.SHA256 -cnotmatch '^[a-f0-9]{64}$'){throw 'GUI worker context雜湊格式不符。'}
  $target=Join-Path $CodeRoot $file.Name;Assert-SetupGuiProtectedPath $target
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.SHA256){throw ('GUI worker stage來源雜湊不符：'+$file.Name)}
 }
 Assert-SetupGuiProtectedPath $paths.DataRoot -Directory -UserSid $context.UserSID
 return $context
}
function Assert-SetupGuiWorkerScope {
 param($Context,$Scope)
 if($Context.Role -ceq 'TaskbarFinalize'){
  if($Scope.UserSID -cne $Context.UserSID -or $Scope.Computer -cne $Context.Computer -or $Scope.SessionId -le 0 -or (Get-SetupGuiDesktopSession $Scope) -ne $Scope.SessionId){throw 'GUI 收尾必須由原帳號在目前唯一互動桌面執行。'}
  return
 }
 if($Scope.UserSID -cne $Context.UserSID -or $Scope.Computer -cne $Context.Computer -or $Scope.SessionId -ne $Context.DesktopSession -or $Scope.SessionId -le 0){throw 'GUI worker實際執行身分或桌面不符，未套用任何設定。'}
}
function Get-SetupGuiResultName {
 param($Context)
 $null=Get-SetupGuiStageFiles $Context.Role
 if($Context.VerifyOnly){return ($Context.Role+'-Verification.json')}
 return ($Context.Role+'-Result.json')
}
function Write-SetupGuiResult {
 param([string]$DataRoot,$Context,[Collections.IDictionary]$Result,[int]$ExecutionSessionId)
 $envelope=[ordered]@{Schema=1;Role=$Context.Role;RunId=$Context.RunId;UserSID=$Context.UserSID;SessionId=$Context.DesktopSession;Computer=$Context.Computer;VerifyOnly=$Context.VerifyOnly}
 if($Context.Role -ceq 'TaskbarFinalize'){if($ExecutionSessionId -le 0){throw 'GUI 收尾缺少本次互動桌面身分。'};$envelope.OriginalDesktopSession=$Context.DesktopSession;$envelope.SessionId=$ExecutionSessionId}
 foreach($name in $Result.Keys){if($envelope.Contains($name)){throw 'GUI worker結果不可覆寫本輪身分。'};$envelope[$name]=$Result[$name]}
 Write-SetupGuiAtomicJson -Path (Join-Path $DataRoot (Get-SetupGuiResultName $Context)) -Value $envelope -UserSid $Context.UserSID
}
function Read-SetupGuiResult {
 param($Stage)
 $context=Read-SetupGuiContext -CodeRoot $Stage.CodeRoot -CommonDataRoot $Stage.CommonDataRoot -Role $Stage.Context.Role -RunId $Stage.Context.RunId
 if(($context|ConvertTo-Json -Depth 8 -Compress) -cne ($Stage.Context|ConvertTo-Json -Depth 8 -Compress)){throw 'GUI worker context在本輪執行期間改變。'}
 $paths=Get-SetupGuiRunPaths -CommonDataRoot $Stage.CommonDataRoot -Role $context.Role -RunId $context.RunId
 if([IO.Path]::GetFullPath($Stage.DataRoot) -ine $paths.DataRoot){throw 'GUI worker結果必須使用本輪固定data目錄。'}
 $path=Join-Path $paths.DataRoot (Get-SetupGuiResultName $context);Assert-SetupGuiProtectedPath $path -UserSid $context.UserSID
 $result=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
 $expectedSession=$context.DesktopSession
 if($context.Role -ceq 'TaskbarFinalize'){
  $scope=Get-SetupGuiIdentity
  if($scope.UserSID -cne $context.UserSID -or $scope.Computer -cne $context.Computer -or $result.OriginalDesktopSession -ne $context.DesktopSession){throw 'GUI 收尾結果不是原帳號或原電腦的本輪資料。'}
  $expectedSession=Get-SetupGuiDesktopSession $scope
 }
 if($result.Schema -ne 1 -or $result.Role -cne $context.Role -or $result.RunId -cne $context.RunId -or $result.UserSID -cne $context.UserSID -or $result.Computer -cne $context.Computer -or $result.SessionId -ne $expectedSession -or $result.VerifyOnly -isnot [bool] -or $result.VerifyOnly -ne $context.VerifyOnly -or $result.Success -isnot [bool]){throw 'GUI worker結果身分或本輪ID不符。'}
 if($context.Role -ceq 'Icons' -and $result.Mode -cne $context.IconMode){throw 'GUI worker結果圖示模式不符。'}
 if($context.Role -cin @('Display','Icons')){Assert-SetupGuiDisplayResult $result}
 if($context.Role -ceq 'Start'){Assert-SetupGuiStartResult $result}
 if($context.Role -cin @('Taskbar','TaskbarFinalize')){Assert-SetupGuiTaskbarResult -Result $result -VerifyOnly:$context.VerifyOnly -Finalize:($context.Role -ceq 'TaskbarFinalize')}
 return $result
}
function Get-SetupGuiIdentity {
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 [pscustomobject]@{UserSID=$identity.User.Value;Computer=[Environment]::MachineName;SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;CommonDataRoot=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData);PowerShell=(Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell/v1.0/powershell.exe')}
}
function Export-SetupTaskbarBackup {
 param([string]$Path)
 & (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'reg.exe') export 'HKCU\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced' $Path /y|Out-Null
 if($LASTEXITCODE -ne 0){throw '工作列原設定匯出失敗。'}
}
function Get-SetupGuiDesktopSession {
 param($Scope)
 $matching=@(foreach($process in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop)){
  if($process.SessionId -le 0 -or ($Scope.SessionId -gt 0 -and $Scope.SessionId -ne $process.SessionId)){continue}
  $owner=Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop
  if(($owner.ReturnValue -is [uint32] -or $owner.ReturnValue -is [int]) -and $owner.ReturnValue -eq 0 -and $owner.Sid -ceq $Scope.UserSID){[int]$process.SessionId}
 })
 $sessions=@($matching|Select-Object -Unique)
 if($sessions.Count -ne 1){throw 'GUI worker找不到同一使用者唯一的互動桌面，未啟動工作。'}
 return $sessions[0]
}
function Invoke-SetupGuiLocalWorker {
 param($Stage,$Scope)
 $null= & (Join-Path $Stage.CodeRoot 'core/gui_worker.ps1') -Role $Stage.Context.Role -RunId $Stage.Context.RunId
}
function Stop-SetupGuiProcessTree {
 param([Parameter(Mandatory=$true)][int]$ProcessId)
 & taskkill.exe /PID $ProcessId /T /F|Out-Null
}
function Get-SetupGuiWorkerProcess {
 # 只認本倉庫固定格式的 worker：-File "<資料根>\windows_setup_gui\<角色>\<RunId>\code\core/gui_worker.ps1" -Role <角色> -RunId <RunId>，且路徑必須落在受保護資料根下。
 param([Parameter(Mandatory=$true)][string]$CommonDataRoot,[Parameter(Mandatory=$true)][string]$Role)
 $null=Get-SetupGuiStageFiles $Role
 $roleRoot=Join-Path (Join-Path ([IO.Path]::GetFullPath($CommonDataRoot)) 'windows_setup_gui') $Role.ToLowerInvariant()
 foreach($process in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)){
  if(-not $process.CommandLine){continue}
  if($process.CommandLine -notmatch '-File "(?<path>[^"]+)" -Role (?<role>[A-Za-z]+) -RunId (?<id>[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})\s*$'){continue}
  if($Matches.role -cne $Role){continue}
  $runId=$Matches.id;$actual=$Matches.path
  try{$expected=[IO.Path]::GetFullPath((Join-Path (Join-Path (Join-Path $roleRoot $runId) 'code') 'core/gui_worker.ps1'));$actual=[IO.Path]::GetFullPath($actual)}catch{continue}
  if($actual -ine $expected){continue}
  [pscustomobject]@{RunId=$runId;ProcessId=[int]$process.ProcessId;CreatedAt=$process.CreationDate;TaskName=('WindowsSetup-Gui-'+$Role+'-'+$runId)}
 }
}
function Stop-SetupGuiWorkerRun {
 param([Parameter(Mandatory=$true)]$Worker)
 $task=Get-ScheduledTask -TaskName $Worker.TaskName -ErrorAction SilentlyContinue
 if($task){Stop-ScheduledTask -TaskName $Worker.TaskName -ErrorAction SilentlyContinue}
 Stop-SetupGuiProcessTree -ProcessId $Worker.ProcessId
 if($task){Unregister-ScheduledTask -TaskName $Worker.TaskName -Confirm:$false -ErrorAction SilentlyContinue}
}
function Stop-SetupGuiStaleWorkers {
 # 清掉「我們自己建立、仍在執行、且超過上限」的舊 worker：同角色、他輪、有對應的執行中排程。正在工作的合法 worker（未超過上限）一律不動。
 param([Parameter(Mandatory=$true)][string]$CommonDataRoot,[Parameter(Mandatory=$true)][string]$Role,[Parameter(Mandatory=$true)][string]$CurrentRunId,[int]$MaxAgeSeconds=300)
 foreach($worker in @(Get-SetupGuiWorkerProcess -CommonDataRoot $CommonDataRoot -Role $Role)){
  if($worker.RunId -ieq $CurrentRunId){continue}
  if(((Get-Date)-$worker.CreatedAt).TotalSeconds -lt $MaxAgeSeconds){continue}
  $task=Get-ScheduledTask -TaskName $worker.TaskName -ErrorAction SilentlyContinue
  if(-not $task -or $task.State -ne 'Running'){continue}
  Stop-SetupGuiWorkerRun -Worker $worker
  $worker.RunId
 }
}
function ConvertTo-SetupGuiSafeReason {
 # worker 原因會寫入畫面與驗收紀錄：先移除路徑，再移除 SID、電子郵件、帳號與電腦名稱；寧可多遮也不洩漏。
 param([AllowNull()][AllowEmptyString()][string]$Text)
 $safe=([string]$Text -replace '\s+',' ').Trim()
 $path='(?:\\\\|(?<![A-Za-z])[A-Za-z]:[\\/]|[\\/]Users[\\/])'
 $safe=[regex]::Replace($safe,'(["''「])'+$path+'.*?(["''」])(?=[\s，。；：、,.;:)）]|$)','$1[路徑]$2','IgnoreCase')
 $safe=[regex]::Replace($safe,$path+'.*$','[路徑]','IgnoreCase')
 $safe=[regex]::Replace($safe,'S-1-\d+(?:-\d+)+','[SID]','IgnoreCase')
 $safe=[regex]::Replace($safe,'[^\s@''"，。；：]+@[^\s@''"，。；：]+','[帳號]')
 foreach($name in @([Environment]::UserName,[Environment]::MachineName,[Environment]::UserDomainName)){
  if(-not [string]::IsNullOrWhiteSpace($name)){$safe=[regex]::Replace($safe,'(?<![A-Za-z0-9_])'+[regex]::Escape($name)+'(?![A-Za-z0-9_])','[帳號]','IgnoreCase')}
 }
 $safe=[regex]::Replace($safe,'(?<!HK[A-Z_]+:?\\[^，。；]*)(?<![\w\\:\]])(?!HK)(?:\[帳號\]|[A-Za-z0-9][\w.-]*)\\[^\s''"，。；：]+','[帳號]','IgnoreCase')
 if($safe.Length -gt 500){$safe=$safe.Substring(0,500)+'…'}
 return $safe
}
function New-SetupGuiResultException {
 param([Parameter(Mandatory=$true)][string]$Role,$Result,[string]$Prefix)
 $reason=ConvertTo-SetupGuiSafeReason $Result.Error
 if($Role -cin @('Display','Icons') -and $Result.Status -ceq 'Unverified'){
  $exception=[InvalidOperationException]::new($reason);$exception.Data['SetupGuiStatus']='Unverified';return $exception
 }
 if(-not $reason){$reason='worker 未寫入具體原因'}
 if($Prefix){$reason=$Prefix+'；原因：'+$reason}
 return [InvalidOperationException]::new($reason)
}
function New-SetupGuiExitException {
 # 退出碼不是 0 一律失敗；這裡只決定能帶出哪些可信原因。
 param($Stage,[string]$ExitCode)
 $prefix='GUI worker排程退出碼不是0：'+$ExitCode
 try{$result=Read-SetupGuiResult -Stage $Stage}catch{return [InvalidOperationException]::new($prefix+'；worker 結果無法驗證：'+(ConvertTo-SetupGuiSafeReason $_.Exception.Message))}
 if($result.Success){return [InvalidOperationException]::new($prefix+'；worker 結果記為成功，與退出碼不符，原因未知')}
 return New-SetupGuiResultException -Role $Stage.Context.Role -Result $result -Prefix $prefix
}
function Get-SetupGuiDesktopFacts {
 Add-Type -AssemblyName System.Windows.Forms
 [pscustomobject]@{MonitorCount=[int][System.Windows.Forms.SystemInformation]::MonitorCount}
}
function Get-SetupGuiCurrentResolution {
 # 桌面尺寸在縮放不是 100% 時會被 DPI 換算；改讀顯示介面目前的模式。
 $modes=@(foreach($adapter in @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)){
  if([int]$adapter.CurrentHorizontalResolution -gt 0 -and [int]$adapter.CurrentVerticalResolution -gt 0){[string]$adapter.CurrentHorizontalResolution+'×'+[string]$adapter.CurrentVerticalResolution}
 })
 return (@($modes|Select-Object -Unique) -join '、')
}
function Get-SetupGuiDisplayGate {
 # 唯讀；有螢幕時不回傳任何內容，由葉節點照原規則判定。沒有螢幕與查詢失敗分開，兩者都是未驗證。
 # Get-PnpDevice 會列出目前不在的裝置，且沒有符合項目時會丟錯，無法和查詢失敗區分，因此直接查 CIM。
 $physical=$null;$category=''
 try{
  $devices=@(Get-CimInstance -ClassName Win32_PnPEntity -Filter "ClassGuid='{4d36e96e-e325-11ce-bfc1-08002be10318}'" -ErrorAction Stop)
  if(@($devices|Where-Object {$_.Present -isnot [bool]}).Count){$category='裝置存在狀態格式不符'}
  else{$physical=@($devices|Where-Object {$_.Present}).Count}
 }catch{$category=$_.Exception.GetType().Name;if($_.Exception.PSObject.Properties['NativeErrorCode']){$category+='/'+[string]$_.Exception.NativeErrorCode}}
 if($physical -gt 0){return}
 # 只在不會進入葉節點時才載入 Windows Forms，避免影響葉節點的 DPI 狀態。
 $facts=$null;try{$facts=Get-SetupGuiDesktopFacts}catch{}
 $resolution='未知';$monitors='未知';$present='未知'
 try{$current=Get-SetupGuiCurrentResolution;if($current){$resolution=$current}}catch{}
 if($null -ne $facts -and $null -ne $facts.MonitorCount){$monitors=[string]$facts.MonitorCount}
 if($null -ne $physical){$present=[string]$physical}
 $state=if($null -eq $physical){'QueryFailed'}else{'NoDisplay'}
 $message=if($state -ceq 'NoDisplay'){'未偵測到螢幕，無法驗收解析度與圖示'}else{'螢幕查詢失敗（'+$category+'），無法判斷是否有螢幕，未驗收解析度與圖示'}
 $message+='；未變更解析度、圖示排列或範本。目前解析度 '+$resolution+'，實體螢幕 '+$present+'，Windows 螢幕數 '+$monitors+'。'
 [pscustomobject][ordered]@{Success=$false;Status='Unverified';DisplayState=$state;PhysicalMonitorCount=$physical;MonitorCount=$facts.MonitorCount;CurrentResolution=$resolution;CheckedAt=(Get-Date).ToString('o');Error=$message}
}
function Assert-SetupGuiDisplayResult {
 # 螢幕與圖示結果只有未驗證時帶 Status；未驗證必須是失敗結果，並有固定分類與原因。
 param($Result)
 if(-not $Result.PSObject.Properties['Status']){return}
 if($Result.Status -cne 'Unverified' -or $Result.Success -or $Result.DisplayState -cnotin @('NoDisplay','QueryFailed') -or [string]::IsNullOrWhiteSpace($Result.Error)){throw 'GUI worker螢幕狀態結果格式不符。'}
}
function Invoke-SetupGuiScheduledWorker {
 param($Stage,$Scope)
 $context=$Stage.Context;$worker=Join-Path $Stage.CodeRoot 'core/gui_worker.ps1'
 Assert-SetupGuiProtectedPath $worker
 $name='WindowsSetup-Gui-'+$context.Role+'-'+$context.RunId
 if(Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue){throw 'GUI worker本輪排程名稱已存在，拒絕接管。'}
 $arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$worker+'" -Role '+$context.Role+' -RunId '+$context.RunId
 $action=New-ScheduledTaskAction -Execute $Scope.PowerShell -Argument $arguments
 $principal=New-ScheduledTaskPrincipal -UserId $context.UserSID -LogonType Interactive -RunLevel Highest
 $registered=$false
 try{
  try{$null=@(Stop-SetupGuiStaleWorkers -CommonDataRoot $Scope.CommonDataRoot -Role $context.Role -CurrentRunId $context.RunId)}catch{Write-Warning ('舊GUI worker清理失敗，未接管：'+$_.Exception.Message)}
  Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -ErrorAction Stop|Out-Null
  $registered=$true;Start-ScheduledTask -TaskName $name -ErrorAction Stop
  $resultPath=Join-Path $Stage.DataRoot (Get-SetupGuiResultName $context);$deadline=(Get-Date).AddSeconds(60)
  do{
   Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $name -ErrorAction Stop
   if((Test-Path -LiteralPath $resultPath) -and $task -and $task.State -ne 'Running'){
    $info=Get-ScheduledTaskInfo -TaskName $name -ErrorAction Stop
    if($null -eq $info -or $info.LastTaskResult -ne 0){throw (New-SetupGuiExitException -Stage $Stage -ExitCode ([string]$info.LastTaskResult))}
    return
   }
  }while((Get-Date) -lt $deadline)
  foreach($own in @(Get-SetupGuiWorkerProcess -CommonDataRoot $Scope.CommonDataRoot -Role $context.Role|Where-Object {$_.RunId -ieq $context.RunId})){try{Stop-SetupGuiWorkerRun -Worker $own}catch{Write-Warning ('本輪逾時worker清理失敗：'+$_.Exception.Message)}}
  Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
  throw '尚未取得受保護的本輪GUI worker結果；請確認原帳號已登入桌面。'
 }finally{
  if($registered){$task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue;if($task -and $task.State -ne 'Running'){Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop}}
 }
}
function Assert-SetupGuiStartResult {
 param($Result)
 if($Result.Success -isnot [bool] -or $Result.Status -cnotin @('Confirmed','LegacyPendingApply','PendingSignIn','Failed') -or $Result.Success -ne ($Result.Status -ceq 'Confirmed')){throw 'GUI worker開始選單結果狀態與成功值不符。'}
}
function Assert-SetupGuiTaskbarResult {
 param($Result,[switch]$VerifyOnly,[switch]$Finalize)
 $allowed=if($Finalize){@('Finalized','Obsolete','Failed')}elseif($VerifyOnly){@('Confirmed','PendingSignIn','Failed')}else{@('Applied','Failed')}
 $complete=if($Finalize){'Finalized'}elseif($VerifyOnly){'Confirmed'}else{'Applied'}
 if($Result.Success -isnot [bool] -or $Result.Status -cnotin $allowed -or $Result.Success -ne ($Result.Status -ceq $complete)){throw 'GUI worker工作列結果狀態與模式或成功值不符。'}
 if($Finalize -and ($Result.TemporaryLayoutPolicyRemoved -isnot [bool] -or $Result.TemporaryLayoutPolicyRemoved -ne $Result.Success)){throw 'GUI worker工作列結果未明確確認暫時政策讀回。'}
 if($Result.Status -ceq 'PendingSignIn' -and ($Result.RequiresNextSignIn -isnot [bool] -or -not $Result.RequiresNextSignIn -or $Result.Configured -isnot [bool] -or -not $Result.Configured -or $Result.BindingMatches -isnot [bool] -or -not $Result.BindingMatches)){throw 'GUI worker工作列結果待登入狀態不完整。'}
}
function Test-SetupGuiPendingResult {
 param([string]$Role,$Result)
 if($Result.Success -isnot [bool] -or $Result.Success){return $false}
 return (($Role -ceq 'Start' -and $Result.Status -cin @('LegacyPendingApply','PendingSignIn')) -or ($Role -ceq 'Taskbar' -and $Result.Status -ceq 'PendingSignIn' -and $Result.RequiresNextSignIn -eq $true -and $Result.Configured -eq $true -and $Result.BindingMatches -eq $true) -or ($Role -ceq 'TaskbarFinalize' -and $Result.Status -ceq 'Obsolete'))
}
function Invoke-SetupGuiPublicDispatch {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[Parameter(Mandatory=$true)][ValidateSet('Display','Theme','Icons')][string]$Role,[switch]$Worker,[switch]$VerifyOnly,[string]$VerificationRunId,[ValidateSet('Save','Load','Verify')][string]$IconMode='Load')
 if($Role -ceq 'Icons'){
  Invoke-SetupGuiRole -PackageRoot $PackageRoot -Role $Role -Worker:$Worker -VerifyOnly:$VerifyOnly -IconMode $IconMode -VerificationRunId $VerificationRunId
 }else{
  Invoke-SetupGuiRole -PackageRoot $PackageRoot -Role $Role -Worker:$Worker -VerifyOnly:$VerifyOnly -VerificationRunId $VerificationRunId
 }
}
function Invoke-SetupGuiRole {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[string]$Role,[switch]$Worker,[switch]$VerifyOnly,[string]$VerificationRunId,[ValidateSet('Save','Load','Verify')][string]$IconMode='Load',[switch]$ApplyPolicy,[switch]$NonInteractive)
 $ErrorActionPreference='Stop'
 $null=Get-SetupGuiStageFiles $Role
 if($Role -ceq 'TaskbarFinalize'){throw '工作列收尾只能由原 Apply 建立的固定工作執行。'}
 $scope=Get-SetupGuiIdentity
 if($Worker -and $scope.SessionId -eq 0){throw 'GUI -Worker不能在session 0繞過原使用者桌面身分。'}
 $desktop=Get-SetupGuiDesktopSession $scope
 $creation=@{SourceRoot=$PackageRoot;CommonDataRoot=$scope.CommonDataRoot;Role=$Role;UserSid=$scope.UserSID;CallerSession=$scope.SessionId;DesktopSession=$desktop;Computer=$scope.Computer;VerifyOnly=[bool]$VerifyOnly}
 if($Role -ceq 'Icons'){$creation.IconMode=$IconMode}
 if($Role -ceq 'Start'){$creation.ApplyPolicy=[bool]$ApplyPolicy;$creation.NonInteractive=[bool]$NonInteractive}
 if($VerificationRunId){$requested=[guid]::Empty;if(-not [guid]::TryParse($VerificationRunId,[ref]$requested)){throw 'GUI 驗證本輪ID格式不符。'};$creation.RunId=$requested.ToString('D')}
 $stage=New-SetupGuiStage @creation
 try{
  $context=Read-SetupGuiContext -CodeRoot $stage.CodeRoot -CommonDataRoot $stage.CommonDataRoot -Role $Role -RunId $stage.Context.RunId
  if(($context|ConvertTo-Json -Depth 8 -Compress) -cne ($stage.Context|ConvertTo-Json -Depth 8 -Compress)){throw 'GUI worker啟動前context已改變。'}
  if($Role -ceq 'Taskbar'){. (Join-Path $stage.CodeRoot 'modules/taskbar/taskbar_stage_library.ps1');. (Join-Path $stage.CodeRoot 'modules/taskbar/taskbar_settings_library.ps1')}
  if($scope.SessionId -eq 0){Invoke-SetupGuiScheduledWorker -Stage $stage -Scope $scope}else{Invoke-SetupGuiLocalWorker -Stage $stage -Scope $scope}
  $result=Read-SetupGuiResult -Stage $stage
  if(-not $result.Success -and -not(Test-SetupGuiPendingResult -Role $Role -Result $result)){throw (New-SetupGuiResultException -Role $Role -Result $result)}
  if($Role -ceq 'Icons' -and $stage.Context.IconMode -ceq 'Save'){Write-SetupIconReference -PackageRoot $stage.Context.SourcePackageRoot -Reference $result.Reference}
  if($Role -ceq 'Taskbar' -and -not $VerifyOnly){Register-SetupTaskbarFinalize -Stage $stage -Scope $scope}
  if($Role -ceq 'Theme' -and $result.TaskbarPixelsVerified -cne $true){
   if($result.TaskbarAppearanceStatus -ceq 'AutoHidden') {Write-Warning '深色與背景設定已確認；工作列目前自動隱藏，顏色尚未驗證。請顯示工作列後重新驗證。'}
   else {Write-Warning '深色與背景設定已確認；工作列顏色尚未驗證。'}
  }
  return $result
 }finally{$stage.Lock.Dispose()}
}
function Invoke-SetupGuiFreshVerification {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[Parameter(Mandatory=$true)][ValidateSet('Display','Theme','Desktop','Icons','Start','Taskbar')][string]$Role)
 $scope=Get-SetupGuiIdentity
 $run=[guid]::NewGuid().ToString('D')
 $result=Invoke-SetupGuiRole -PackageRoot $PackageRoot -Role $Role -VerifyOnly -VerificationRunId $run
 if($null -eq $result -or $result -is [array] -or $result.Schema -ne 1 -or $result.RunId -cne $run -or $result.Role -cne $Role -or $result.UserSID -cne $scope.UserSID -or $result.Computer -cne $scope.Computer -or $result.SessionId -le 0 -or ($scope.SessionId -gt 0 -and $result.SessionId -ne $scope.SessionId) -or $result.VerifyOnly -isnot [bool] -or -not $result.VerifyOnly -or $result.Success -isnot [bool]){throw 'GUI 即時驗證不是本輪、原使用者、原電腦或原桌面的受保護結果。'}
 return $result
}
function Open-SetupGuiExecutionLock {
 param($Paths)
 Assert-SetupGuiProtectedPath $Paths.RoleRoot -Directory
 $path=Join-Path $Paths.RoleRoot 'execution.lock'
 if(Test-Path -LiteralPath $path){Assert-SetupGuiProtectedPath $path}
 try{$lease=[IO.File]::Open($path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'GUI worker角色已有執行程序，未執行任何UI設定。'}
 try{Assert-SetupGuiProtectedPath $path;return $lease}catch{$lease.Dispose();throw}
}
function Get-SetupDesktopRoots {
 @([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))|Select-Object -Unique
}
function Invoke-SetupGuiWorker {
 param([Parameter(Mandatory=$true)][string]$CodeRoot,[string]$Role,[string]$RunId)
 $ErrorActionPreference='Stop'
 $scope=Get-SetupGuiIdentity
 $context=Read-SetupGuiContext -CodeRoot $CodeRoot -CommonDataRoot $scope.CommonDataRoot -Role $Role -RunId $RunId
 Assert-SetupGuiWorkerScope -Context $context -Scope $scope
 $paths=Get-SetupGuiRunPaths -CommonDataRoot $scope.CommonDataRoot -Role $Role -RunId $RunId
 $lease=$null;$applyLease=$null;$published=$false;$publication=@{}
 if($Role -ceq 'TaskbarFinalize'){$publication.ExecutionSessionId=$scope.SessionId}
 try{
  $lease=Open-SetupGuiExecutionLock -Paths $paths
  if($Role -cin @('Taskbar','TaskbarFinalize')){
   . (Join-Path $CodeRoot 'modules/taskbar/taskbar_stage_library.ps1')
   if($Role -ceq 'TaskbarFinalize'){$applyLease=Open-SetupGuiExecutionLock -Paths (Get-SetupGuiRunPaths -CommonDataRoot $scope.CommonDataRoot -Role Taskbar -RunId $context.ApplyRunID)}
  }
  $gate=if($Role -cin @('Display','Icons')){Get-SetupGuiDisplayGate}
  # Role and all executable file hashes were validated before importing this fixed library.
  $module=Join-Path $CodeRoot ('modules/'+$(switch -CaseSensitive ($Role){Icons{'desktop'} Start{'start_menu'} TaskbarFinalize{'taskbar'} default{$Role.ToLowerInvariant()}}))
  $library=switch -CaseSensitive ($Role){Explorer{'explorer_settings_library.ps1'} Display{'display_settings_library.ps1'} Theme{'theme_settings_library.ps1'} Desktop{'desktop_settings_library.ps1'} Icons{'icons_settings_library.ps1'} Start{'start_menu_settings_library.ps1'} Taskbar{'taskbar_settings_library.ps1'} TaskbarFinalize{'taskbar_settings_library.ps1'} default{throw 'GUI worker角色尚未核准。'}}
  if($null -eq $gate){. (Join-Path $module $library)}
  $result=if($null -ne $gate){if($Role -ceq 'Icons'){$gate|Add-Member -NotePropertyName Mode -NotePropertyValue $context.IconMode};$gate}else{switch -CaseSensitive ($Role){Explorer{Invoke-SetupExplorerSettings -ModuleRoot $module -VerifyOnly:$context.VerifyOnly} Display{Invoke-SetupDisplaySettings -ModuleRoot $module -VerifyOnly:$context.VerifyOnly} Theme{Invoke-SetupThemeSettings -ModuleRoot $module -VerifyOnly:$context.VerifyOnly} Desktop{Invoke-SetupDesktopSettings -ModuleRoot $module -SourcePackageRoot $context.SourcePackageRoot -DesktopRoots @(Get-SetupDesktopRoots) -VerifyOnly:$context.VerifyOnly} Icons{Invoke-SetupIconsSettings -ModuleRoot $module -Mode $context.IconMode -Reference $context.IconReference} Start{Invoke-SetupStartMenuSettings -ModuleRoot $module -OutputRoot $paths.DataRoot -VerifyOnly:$context.VerifyOnly -ApplyPolicy:$context.ApplyPolicy -NonInteractive:$context.NonInteractive} Taskbar{$binding=if($context.VerifyOnly){Get-SetupTaskbarLayoutBinding -CommonDataRoot $scope.CommonDataRoot -Context $context}else{[pscustomobject]@{LayoutPath=(Join-Path $paths.DataRoot 'TaskbarLayout.xml');FinalizeCommand=''}};Invoke-SetupTaskbarSettings -OutputRoot $paths.DataRoot -LayoutPath $binding.LayoutPath -ExpectedFinalizeCommand $binding.FinalizeCommand -PendingFinalizeTask:($binding.PendingFinalizeTask -eq $true) -VerifyOnly:$context.VerifyOnly} TaskbarFinalize{Invoke-SetupTaskbarBoundFinalize -CommonDataRoot $scope.CommonDataRoot -Context $context}}}
  if($result.Success -isnot [bool]){throw 'GUI worker葉節點未提供有效成功狀態。'}
  if($Role -ceq 'Start'){Assert-SetupGuiStartResult $result}
  if($Role -cin @('Taskbar','TaskbarFinalize')){Assert-SetupGuiTaskbarResult -Result $result -VerifyOnly:$context.VerifyOnly -Finalize:($Role -ceq 'TaskbarFinalize')}
  $details=[ordered]@{};foreach($property in $result.PSObject.Properties){$details[$property.Name]=$property.Value}
  Write-SetupGuiResult -DataRoot $paths.DataRoot -Context $context -Result $details @publication
  $published=$true
  if(-not $result.Success -and -not(Test-SetupGuiPendingResult -Role $Role -Result $result)){throw (New-SetupGuiResultException -Role $Role -Result $result)}
  if($Role -ceq 'TaskbarFinalize'){Complete-SetupTaskbarFinalizeTask -RunId $context.RunId}
  return $result
 }catch{
  if(-not $published){$failure=@{Success=$false;Error=$_.Exception.Message;FailedAt=(Get-Date).ToString('o')};if($Role -cin @('Start','Taskbar','TaskbarFinalize')){$failure.Status='Failed'};if($Role -ceq 'Icons'){$failure.Mode=$context.IconMode};if($Role -ceq 'TaskbarFinalize'){$failure.TemporaryLayoutPolicyRemoved=$false};Write-SetupGuiResult -DataRoot $paths.DataRoot -Context $context -Result $failure @publication}
  throw
 }finally{if($applyLease){$applyLease.Dispose()};if($lease){$lease.Dispose()}}
}
