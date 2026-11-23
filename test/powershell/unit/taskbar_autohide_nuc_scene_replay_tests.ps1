#Requires -Version 5.1
# NUC8 現場重放（#353）：fixture 取自實機擷取，說明見 fixtures/nuc_scene_taskbar_autohide/README.md。
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fx=Join-Path $root 'test/powershell/fixtures/nuc_scene_taskbar_autohide'
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'modules/taskbar/taskbar_settings_library.ps1')
$applyScene=Get-Content -LiteralPath (Join-Path $fx 'taskbar_apply_scene.json') -Raw -Encoding UTF8|ConvertFrom-Json
$verifyScene=Get-Content -LiteralPath (Join-Path $fx 'taskbar_verify_scene.json') -Raw -Encoding UTF8|ConvertFrom-Json
$hex=([regex]::Match((Get-Content -LiteralPath (Join-Path $fx 'StuckRects3.reg.txt') -Raw),'REG_BINARY\s+([0-9A-Fa-f]+)')).Groups[1].Value
[byte[]]$sceneBytes=for($i=0;$i -lt $hex.Length;$i+=2){[Convert]::ToByte($hex.Substring($i,2),16)}
Assert ($sceneBytes.Count -eq 48 -and $sceneBytes[8] -eq 2) 'fixture StuckRects3 byte 9 is 0x02 (auto-hide bit absent), as captured'
Assert ($applyScene.Status -ceq 'Applied' -and $applyScene.AutoHide -eq $true -and $applyScene.AppBarState -eq 1) 'fixture records the Apply report: Applied, AutoHide=true, AppBarState=1'
Assert ($verifyScene.Status -ceq 'Failed' -and $verifyScene.AutoHide -eq $false -and $verifyScene.AppBarState -eq 0 -and $verifyScene.VerifyOnly -eq $true) 'fixture records the later VerifyOnly read-back: Failed, AutoHide=false, AppBarState=0'
# 以固定 fixture 位元組模擬登錄；原生層只改執行中狀態（ABM_SETSTATE），Explorer 重新載入時由登錄位元 0 決定（模型假設）。
$script:reg=[byte[]]$sceneBytes.Clone();$script:running=[uint32]0
function Get-ItemProperty {param($Path,$Name,$ErrorAction) if($Path -like '*StuckRects3'){return [pscustomobject]@{Settings=[byte[]]$script:reg.Clone()}};throw "unexpected read $Path"}
function Set-ItemProperty {param($Path,$Name,$Value,$Type,$ErrorAction) if($Path -notlike '*StuckRects3' -or $Name -ne 'Settings'){throw "unexpected write $Path"};$script:reg=[byte[]]$Value}
function Invoke-SetupTaskbarNativeAutoHide {param([string]$ModuleRoot,[bool]$Apply) if($Apply){$script:running=$script:running -bor 1};return $script:running}
$mod=Join-Path $root 'modules/taskbar'
$apply=Invoke-SetupTaskbarAutoHide -ModuleRoot $mod
Assert ($apply.AutoHide -eq $applyScene.AutoHide -and $apply.AppBarState -eq $applyScene.AppBarState) 'replayed Apply reports the same fields as the captured Apply (AutoHide=true, AppBarState=1)'
# Explorer 重新載入：執行中狀態改由登錄位元 0 決定，之後以 VerifyOnly 讀回。
$script:running=[uint32]($script:reg[8] -band 1)
$verify=Invoke-SetupTaskbarAutoHide -ModuleRoot $mod -VerifyOnly
Write-Host ('replay VerifyOnly: AutoHide='+$verify.AutoHide+' AppBarState='+$verify.AppBarState+' StuckRects3[8]=0x'+$script:reg[8].ToString('X2'))
Assert ($verify.AutoHide -eq $true) 'after an Apply that reported success, the read-back still shows auto-hide enabled (scene symptom: captured read-back was false)'
$expected=[byte[]]$sceneBytes.Clone();$expected[8]=[byte]($expected[8] -bor 1)
Assert (-not (Compare-Object $script:reg $expected)) 'only the auto-hide bit of StuckRects3 changes; all other captured bytes are preserved'
