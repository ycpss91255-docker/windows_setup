#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};Write-Host ('PASS: '+$Name)}
$fixtureRoot=Join-Path $root 'test/powershell/fixtures/nuc_scene_taskbar_acceptance'
function Read-SceneFixture([string]$Name){$parsed=ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $fixtureRoot $Name) -Raw -Encoding UTF8);@($parsed)}
$unfixedChecks=Read-SceneFixture 'taskbar_checks_unfixed_scene.json'
$fixedChecks=Read-SceneFixture 'taskbar_checks_fixed_scene.json'
$restartEvidence=(Get-Content -LiteralPath (Join-Path $fixtureRoot 'taskbar_evidence_v5_restart_scene.json') -Raw -Encoding UTF8|ConvertFrom-Json)
$claim='釘選登入後套用'

# 現場：未修版在畫面未觀察時仍把受保護 XML 與登錄讀回寫成「釘選登入後套用」通過。
$sceneClaim=@($unfixedChecks|Where-Object {$_.Name -ceq $claim})
Assert ($sceneClaim.Count -eq 1 -and $sceneClaim[0].Passed -eq $true) '現場未修版寫出釘選登入後套用通過'

# 修正：總驗收彙整原始碼不得再產生該項目。
$library=Join-Path $root 'core/verification_library.ps1'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($library,[ref]$tokens,[ref]$parseErrors)
$literals=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -ceq $claim},$true))
Assert ($parseErrors.Count -eq 0 -and $literals.Count -eq 0) '總驗收彙整不再含釘選登入後套用項目'

# 重放：以現場重開後的讀回值走修正版，名稱、結果與說明須與現場修正版逐字相同。
. $library
$script:checks=@()
function Add-Check([string]$Name,[bool]$Passed,[string]$Detail){$script:checks+=@([pscustomobject]@{Name=$Name;Passed=$Passed;Detail=$Detail})}
function Invoke-SetupGuiFreshVerification {param($PackageRoot,$Role) [pscustomobject]@{Schema=1;Role=$Role;Success=$true;Configured=$true;BindingMatches=$true;RequiresNextSignIn=$false;Status='Confirmed'}}
Assert ($null -ne (Get-Command Add-SetupTaskbarVerificationChecks -ErrorAction SilentlyContinue)) '工作列驗收項目由具名函式產生'
Add-SetupTaskbarVerificationChecks -PackageRoot 'scene'
Assert ($script:checks.Count -eq $fixedChecks.Count) '重放項目數與現場修正版相同'
for($i=0;$i -lt $fixedChecks.Count;$i++){
 Assert ($script:checks[$i].Name -ceq $fixedChecks[$i].Name -and $script:checks[$i].Passed -eq $fixedChecks[$i].Passed -and $script:checks[$i].Detail -ceq $fixedChecks[$i].Detail) ('重放與現場修正版逐項相同：'+$fixedChecks[$i].Name)
}
Assert (@($script:checks|Where-Object {$_.Name -ceq $claim}).Count -eq 0) '重放不含釘選登入後套用'

# 重開後驗收：Acceptance-Result.json 的 TaskbarEvidence 保留讀回並標示畫面未知。
. (Join-Path $root 'core/after_restart_library.ps1')
$caseDir=Join-Path ([IO.Path]::GetTempPath()) ('taskbar_acceptance_scene_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($caseDir)
function Resolve-NucPath([string]$Name){Join-Path $caseDir $Name}
$verifier=@'
param([string]$VerificationRunId)
$parsed=ConvertFrom-Json -InputObject (Get-Content -LiteralPath $env:SCENE_FIXED_CHECKS -Raw -Encoding UTF8);$checks=@($parsed)
$record=@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Passed=$true;Checks=$checks}
$record|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot 'Verification-Result.json') -Encoding UTF8
'@
[IO.File]::WriteAllText((Join-Path $caseDir 'verify_only.ps1'),$verifier,[Text.UTF8Encoding]::new($true))
$oldChecks=$env:SCENE_FIXED_CHECKS
try{
 $env:SCENE_FIXED_CHECKS=Join-Path $fixtureRoot 'taskbar_checks_fixed_scene.json'
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $threw=$false
 try{Complete-SetupAfterRestartAcceptance -Hardware ([pscustomobject]@{Name='Scene'}) -Errors @() -Previous $null -ResultPath (Join-Path $caseDir 'Setup-Result.json') -Sid $sid}catch{$threw=$true}
 Assert (-not $threw) '現場讀回全數通過時驗收成功'
 $report=Get-Content (Join-Path $caseDir 'Acceptance-Result.json') -Raw|ConvertFrom-Json
}finally{$env:SCENE_FIXED_CHECKS=$oldChecks}
Assert ($report.TaskbarEvidence.VisualStatus -ceq $restartEvidence.VisualStatus -and $restartEvidence.VisualStatus -ceq 'Unknown') '驗收結果標示實際畫面未知'
$persisted=@($report.TaskbarEvidence.PolicyChecks);$real=@($restartEvidence.PolicyChecks)
Assert ($persisted.Count -eq $real.Count -and $real.Count -eq 2) '驗收結果保留兩項政策讀回'
for($i=0;$i -lt $real.Count;$i++){
 Assert ($persisted[$i].Name -ceq $real[$i].Name -and $persisted[$i].Passed -eq $real[$i].Passed -and $persisted[$i].Detail -ceq $real[$i].Detail) ('驗收結果與重開後現場證據逐項相同：'+$real[$i].Name)
}
Remove-Item -LiteralPath $caseDir -Recurse -Force
Write-Host 'ALL PASS: taskbar acceptance NUC scene replay'
