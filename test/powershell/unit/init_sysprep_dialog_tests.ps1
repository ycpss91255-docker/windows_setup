#Requires -Version 5.1
# 現場重放（#481）：稽核模式自動開啟的 Sysprep 對話框讓 Init 只顯示「狀態未知」。擷取來源、推定欄位與限制見 fixtures/nuc_scene_audit_sysprep/readme.md。
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/init/init_entry_library.ps1')
$script:failures=@()
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){$script:failures+=$Name}}
$scene=Get-Content -LiteralPath (Join-Path $root 'test/powershell/fixtures/nuc_scene_audit_sysprep/scene.json') -Raw -Encoding UTF8|ConvertFrom-Json
function ConvertTo-Facts($Object){$table=@{};foreach($p in $Object.PSObject.Properties){$table[$p.Name]=$p.Value};return $table}
$after=ConvertTo-Facts $scene.ModeFactsAfterClose
$after.SetupProcessNames=@();$after.OobeProcessNames=@();$after.SysprepProcessIds=@()
function New-BeforeFacts{$f=$after.Clone();$f.SetupProcessInSession=$true;$f.SetupProcessNames=@($scene.SameSessionSetupProcessesBeforeClose);$f.SysprepProcessIds=@(4242);return $f}
$sid=[string]$scene.Sid;$state=[string]$scene.ImageState
function Route($facts,[string]$Sid=$sid,[string]$State=$state,[bool]$Admin=$true,[bool]$Desktop=$true){Get-InitRoute -Sid $Sid -ImageState $State -IsAdministrator $Admin -DesktopOwned $Desktop -ModeFacts $facts}
function Try-Call([scriptblock]$Block){try{& $Block}catch [Management.Automation.CommandNotFoundException]{return $null}}

# 1. 現場重放：關閉對話框後路由為 PrepareOobe；關閉前（同工作階段只有 sysprep.exe）路由仍拒絕。
Assert ((Route $after) -ceq [string]$scene.RouteAfterClose) '現場關閉 Sysprep 對話框後的事實路由為 PrepareOobe'
Assert ((Route (New-BeforeFacts)) -ceq [string]$scene.UnfixedRoute) '同工作階段有 sysprep.exe 時路由仍為 RejectUnknownSetupState'

# 2. 拒絕原因：逐項列出實際不符條件，白話中文、不輸出 SID。
$reasons=@(Try-Call {Get-InitRouteRejectReasons -Sid $sid -ImageState $state -IsAdministrator $true -DesktopOwned $true -ModeFacts (New-BeforeFacts)})
Assert ($reasons.Count -eq 1 -and $reasons[0] -match 'sysprep\.exe' -and $reasons[0] -match '取消') '現場拒絕原因只列出同工作階段的 sysprep.exe 並提示按取消'
Assert (@(Try-Call {Get-InitRouteRejectReasons -Sid $sid -ImageState $state -IsAdministrator $true -DesktopOwned $true -ModeFacts $after}).Count -eq 0) '可準備時不回報拒絕原因'
$cases=@(
 @{Name='讀取失敗';Change={param($f) $f.ReadSucceeded=$false};Pattern='無法讀取'},
 @{Name='狀態欄位缺漏';Change={param($f) $f.Remove('ProfileMatches')};Pattern='ProfileMatches'},
 @{Name='組建過舊';Change={param($f) $f.Build=22000};Pattern='22000'},
 @{Name='非用戶端版本';Change={param($f) $f.ProductType=3};Pattern='ProductType=3'},
 @{Name='WinPE';Change={param($f) $f.IsWinPE=$true};Pattern='WinPE'},
 @{Name='OOBE API 失敗';Change={param($f) $f.OobeApiSucceeded=$false};Pattern='OOBE 是否完成'},
 @{Name='安裝程序';Change={param($f) $f.SetupProcessInSession=$true;$f.SetupProcessNames=@('setup.exe')};Pattern='setup\.exe'},
 @{Name='OOBE 程序';Change={param($f) $f.OobeProcessInSession=$true;$f.OobeProcessNames=@('msoobe.exe')};Pattern='msoobe\.exe'},
 @{Name='設定檔不符';Change={param($f) $f.ProfileMatches=$false};Pattern='設定檔'},
 @{Name='OOBE 已完成';Change={param($f) $f.OobeComplete=$true};Pattern='OOBE 已完成'},
 @{Name='非本機內建帳號';Change={param($f) $f.LocalBuiltin=$false};Pattern='內建 Administrator'}
)
$seen=@{}
foreach($case in $cases){
 $f=$after.Clone();& $case.Change $f
 $r=@(Try-Call {Get-InitRouteRejectReasons -Sid $sid -ImageState $state -IsAdministrator $true -DesktopOwned $true -ModeFacts $f})
 $text=$r -join '；'
 Assert ((Route $f) -ceq 'RejectUnknownSetupState' -and $r.Count -ge 1 -and $text -match $case.Pattern -and $text -notmatch 'S-1-5-') ('拒絕原因說明：'+$case.Name)
 if($r.Count){$seen[$text]=$true}
}
Assert ($seen.Count -eq $cases.Count) '每個不符條件的說明文字各不相同'
$r=@(Try-Call {Get-InitRouteRejectReasons -Sid $sid -ImageState $state -IsAdministrator $true -DesktopOwned $false -ModeFacts $after});Assert (($r -join '') -match '桌面') '非擁有桌面的拒絕原因'
$r=@(Try-Call {Get-InitRouteRejectReasons -Sid $sid -ImageState 'UNKNOWN_STATE' -IsAdministrator $true -DesktopOwned $true -ModeFacts $after});Assert (($r -join '') -match 'UNKNOWN_STATE') '映像狀態不在可準備清單的拒絕原因'
$r=@(Try-Call {Get-InitRouteRejectReasons -Sid $sid -ImageState $state -IsAdministrator $false -DesktopOwned $true -ModeFacts $after});Assert (($r -join '') -match '系統管理員') '未以系統管理員權限執行的拒絕原因'
$r=@(Try-Call {Get-InitRouteRejectReasons -Sid 'S-1-5-21-1-2-3-1001' -ImageState 'IMAGE_STATE_COMPLETE' -IsAdministrator $true -DesktopOwned $true -ModeFacts $after});Assert ($r.Count -ge 1 -and ($r -join '') -notmatch 'S-1-5-') '正式帳號但 OOBE 未完成的矛盾狀態有說明且不含 SID'
$r=@(Try-Call {Get-InitRouteRejectReasons -Sid 'S-1-5-21-1-2-3-1001' -ImageState 'IMAGE_STATE_COMPLETE' -IsAdministrator $true -DesktopOwned $false -ModeFacts $null});Assert (($r -join '') -match '桌面') '無狀態事實的舊路徑也說明非擁有桌面'

# 3. 自動關閉資格：只有稽核模式內建 Administrator、同工作階段只有 sysprep.exe 且其他條件都符合時才可關閉。
function Eligible($facts,[string]$Sid=$sid,[string]$State=$state,[bool]$Admin=$true){[bool](Try-Call {Test-InitSysprepDialogOnlyBlocker -Sid $Sid -ImageState $State -IsAdministrator $Admin -DesktopOwned $true -ModeFacts $facts})}
Assert (Eligible (New-BeforeFacts)) '現場（稽核模式、只有 sysprep.exe）可自動關閉'
foreach($s in @('IMAGE_STATE_GENERALIZE_RESEAL_TO_AUDIT')){Assert (Eligible (New-BeforeFacts) -State $s) ('稽核狀態可自動關閉：'+$s)}
foreach($s in @('IMAGE_STATE_UNDEPLOYABLE','IMAGE_STATE_SPECIALIZE_RESEAL_TO_OOBE','IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE','IMAGE_STATE_COMPLETE')){Assert (-not (Eligible (New-BeforeFacts) -State $s)) ('非稽核狀態不自動關閉：'+$s)}
$f=New-BeforeFacts;$f.SetupProcessNames=@('sysprep.exe','setup.exe');Assert (-not (Eligible $f)) 'sysprep.exe 與 setup.exe 並存不自動關閉'
foreach($n in @('setuphost.exe','setupprep.exe')){$f=New-BeforeFacts;$f.SetupProcessNames=@($n);Assert (-not (Eligible $f)) ('不關閉安裝程序：'+$n)}
foreach($n in @('msoobe.exe','CloudExperienceHostBroker.exe')){$f=New-BeforeFacts;$f.OobeProcessInSession=$true;$f.OobeProcessNames=@($n);Assert (-not (Eligible $f)) ('有 OOBE 程序不自動關閉：'+$n)}
$f=New-BeforeFacts;$f.ProfileMatches=$false;Assert (-not (Eligible $f)) '只有 sysprep.exe 但其他條件不符時不自動關閉'
$f=New-BeforeFacts;$f.OobeComplete=$true;Assert (-not (Eligible $f)) 'OOBE 已完成不自動關閉'
$f=New-BeforeFacts;$f.LocalBuiltin=$false;Assert (-not (Eligible $f)) '非本機內建帳號不自動關閉'
Assert (-not (Eligible (New-BeforeFacts) -Sid 'S-1-5-21-1-2-3-1001')) '非內建 Administrator 不自動關閉'
Assert (-not (Eligible (New-BeforeFacts) -Admin $false)) '未提權不自動關閉'
$f=New-BeforeFacts;$f.Remove('SetupProcessNames');Assert (-not (Eligible $f)) '缺少程序名稱的舊事實不自動關閉'
$f=New-BeforeFacts;$f.SysprepProcessIds=@();Assert (-not (Eligible $f)) '缺少程序識別碼不自動關閉'

# 3b. 實際關閉函式（尚未被模擬）：只對 sysprep 視窗送出關閉要求，不結束其他程序。
$closeEmpty=Try-Call {Close-SetupInitSysprepDialog -ProcessIds @()}
Assert ($closeEmpty -eq $false) '沒有程序識別碼時不嘗試關閉'
$closeSelf=Try-Call {Close-SetupInitSysprepDialog -ProcessIds @($PID)}
Assert ($closeSelf -eq $false -and -not (Get-Process -Id $PID -ErrorAction SilentlyContinue).HasExited) '非 sysprep 程序不關閉並回報失敗'
$closeGone=Try-Call {Close-SetupInitSysprepDialog -ProcessIds @(2147483000)}
Assert ($closeGone -eq $true) '程序已自行結束時視為已關閉，交由重新判斷確認'

# 4. Invoke-SetupInit 重放：關閉成功後重新判斷並繼續；關閉失敗明確提示；不可關閉的程序維持拒絕並說明原因。
$script:prompts=@();$script:writes=0;$script:contexts=@();$script:reads=0;$script:closeCalls=@();$script:closeResult=$true
function New-Context($facts,[string]$Sid=$sid,[string]$State=$state){[pscustomobject]@{Sid=$Sid;UserSID=$Sid;IsAdministrator=$true;Is64Bit=$true;Architecture='AMD64';ImageState=$State;DesktopOwned=$true;ModeFacts=$facts}}
function Assert-InitProvisioningAsset {param($AssetRoot);return @{PackageSHA256='fixture'}}
function Invoke-InitProvisioningEntry {return $false}
function Get-SetupInitContext {$i=[Math]::Min($script:reads,$script:contexts.Count-1);$script:reads++;return $script:contexts[$i]}
function Close-SetupInitSysprepDialog {param([int[]]$ProcessIds);$script:closeCalls+=,@($ProcessIds);return $script:closeResult}
function Get-Process {return @()}
function Get-ItemProperty {return [pscustomobject]@{SkuPolicyRequired=0;UnattendFile=$null}}
function Test-Path {param($LiteralPath,$Path,$PathType);return [bool]($LiteralPath -like '*Sysprep.exe')}
function Test-SetupInitInteractiveHost {return $true}
function Read-Host {param($Prompt,[switch]$AsSecureString);$script:prompts+=@($Prompt);return 'NO'}
function New-Item {$script:writes++;throw 'SAFE_MUTATION_SENTINEL'}
function Start-Process {$script:writes++;throw 'SAFE_NATIVE_SENTINEL'}
function New-LocalUser {$script:writes++;throw 'SAFE_ACCOUNT_SENTINEL'}
function Stop-Process {$script:writes++;throw 'SAFE_KILL_SENTINEL'}
function Get-LocalUser {throw 'credentials must not be collected before consent'}
function Invoke-Case([object[]]$Contexts,[bool]$CloseResult=$true){
 $script:prompts=@();$script:writes=0;$script:contexts=$Contexts;$script:reads=0;$script:closeCalls=@();$script:closeResult=$CloseResult
 try{Invoke-SetupInit -EntryPath (Join-Path $root 'modules/init/initialize_nuc.ps1') -ModuleRoot (Join-Path $root 'modules/init');return ''}catch{return $_.Exception.Message}
}
$m=Invoke-Case @((New-Context (New-BeforeFacts)),(New-Context $after))
Assert ($script:closeCalls.Count -eq 1 -and @($script:closeCalls[0]).Count -eq 1 -and @($script:closeCalls[0])[0] -eq 4242) '現場重放：只關閉同工作階段的 sysprep.exe 一次'
Assert ($script:reads -eq 2 -and $script:prompts.Count -eq 1 -and $script:prompts[0] -match 'YES' -and $script:writes -eq 0 -and $m -notmatch '無法確認') '現場重放：關閉後重新判斷為 PrepareOobe 並進入同意提示，未寫入任何設定'
$m=Invoke-Case @((New-Context (New-BeforeFacts))) -CloseResult $false
Assert ($script:closeCalls.Count -eq 1 -and $m -match '取消' -and $m -match 'init\.cmd' -and $script:prompts.Count -eq 0 -and $script:writes -eq 0) '關閉失敗時提示按取消關閉後重跑 init.cmd，未寫入設定'
$m=Invoke-Case @((New-Context (New-BeforeFacts)),(New-Context (New-BeforeFacts)))
Assert ($script:closeCalls.Count -eq 1 -and $m -match 'sysprep\.exe' -and $m -match '取消' -and $script:prompts.Count -eq 0 -and $script:writes -eq 0) '關閉後重讀仍有 sysprep.exe 時不重複關閉並說明原因'
$f=New-BeforeFacts;$f.SetupProcessNames=@('sysprep.exe','setup.exe')
$m=Invoke-Case @((New-Context $f))
Assert ($script:closeCalls.Count -eq 0 -and $m -match 'setup\.exe' -and $m -match [regex]::Escape($state) -and $m -notmatch 'S-1-5-' -and $script:writes -eq 0) 'setup.exe 並存時不關閉任何程序並說明原因'
$f=New-BeforeFacts;$f.OobeProcessInSession=$true;$f.OobeProcessNames=@('CloudExperienceHostBroker.exe')
$m=Invoke-Case @((New-Context $f))
Assert ($script:closeCalls.Count -eq 0 -and $m -match 'CloudExperienceHostBroker\.exe' -and $script:writes -eq 0) 'OOBE 程序並存時不關閉並說明原因'
$f=New-BeforeFacts;$f.ProfileMatches=$false
$m=Invoke-Case @((New-Context $f))
Assert ($script:closeCalls.Count -eq 0 -and $m -match '設定檔' -and $m -match 'sysprep\.exe' -and $m -notmatch 'S-1-5-') '其他條件不符時不關閉並列出全部不符條件'
$m=Invoke-Case @((New-Context (New-BeforeFacts) -State 'IMAGE_STATE_SPECIALIZE_RESEAL_TO_OOBE'))
Assert ($script:closeCalls.Count -eq 0 -and $m -match 'sysprep\.exe' -and $script:writes -eq 0) '非稽核狀態不自動關閉 sysprep.exe'

if($script:failures.Count){throw ('FAIL '+$script:failures.Count+'：'+($script:failures -join ' | '))}
Write-Host 'ALL PASS: audit-mode Sysprep dialog scene replay; process, registry and account boundaries mocked'
