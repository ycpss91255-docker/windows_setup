#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
. (Join-Path $root 'script/test/ci_classify.ps1')
Assert ($null -ne (Get-Command Get-CISharedPathRule -ErrorAction SilentlyContinue)) '共用路徑規則可被個別查詢'
Assert (@($script:CISharedPathRules).Count -ge 8) '共用路徑規則逐條命名，而不是單一樣式'
$fixture=Join-Path $env:TEMP ('ci_rules_'+[guid]::NewGuid().ToString('N'))
try{
 $utf8=[Text.UTF8Encoding]::new($true)
 function Put($Relative,$Text){$full=Join-Path $fixture $Relative;[void][IO.Directory]::CreateDirectory((Split-Path $full -Parent));[IO.File]::WriteAllText($full,$Text,$utf8)}
 # 每個樣本路徑都被一個 suite 引用：沒有規則時它會被判為可縮小，因此「完整」只能來自規則本身。
 $samples=@(
  @{Rule='workflow';Path='.github/workflows/windows_tests.yml'},
  @{Rule='workflow';Path='.github/actions/setup/action.yml'},
  @{Rule='go_module';Path='go.mod'},
  @{Rule='go_module';Path='go.sum'},
  @{Rule='go_module';Path='vendor/modules.txt'},
  @{Rule='version';Path='.version'},
  @{Rule='container';Path='dockerfile'},
  @{Rule='container';Path='compose.yaml'},
  @{Rule='container';Path='script/docker/container_test.ps1'},
  @{Rule='ci_tools';Path='script/test/ci_classify.ps1'},
  @{Rule='ci_tools';Path='script/test/run_ci.ps1'},
  @{Rule='ci_tools';Path='script/test/run_repo_coverage.ps1'},
  @{Rule='test_support';Path='test/powershell/helpers/run_module_fixture.ps1'},
  @{Rule='test_support';Path='test/powershell/support/runner_fixture.ps1'},
  @{Rule='test_support';Path='test/powershell/coverage/safe_suite.ps1'},
  @{Rule='test_support';Path='test/powershell/fixtures/compile_native.ps1'},
  @{Rule='path_registry';Path='core/paths.json'},
  @{Rule='path_registry';Path='core/paths.ps1'},
  @{Rule='go_source';Path='script/test/requirements_gate/main.go'},
  @{Rule='go_source';Path='test/go/unit/classify_test.go'}
 )
 Put 'test/powershell/unit/refs_all_tests.ps1' (($samples|ForEach-Object {"'"+$_.Path+"'"}) -join "`n")
 Put 'test/powershell/unit/other_tests.ps1' "'unrelated'"
 Put 'test/powershell/integration/architecture_tests.ps1' "'g'";Put 'test/powershell/integration/layout_tests.ps1' "'g'";Put 'test/powershell/integration/markdown_line_ending_tests.ps1' "'g'"
 foreach($n in 1..8){Put ('test/powershell/unit/filler'+$n+'_tests.ps1') "'unrelated'"}
 $original=$script:CISharedPathRules
 foreach($sample in $samples){
  $path=$sample.Path
  Assert ((Get-CISharedPathRule $path) -ceq $sample.Rule) ('路徑歸屬正確的規則：'+$path+' -> '+$sample.Rule)
  $withRule=Get-CIScopedTests -Root $fixture -ChangedPaths @($path)
  Assert ($withRule.Scope -ceq 'full') ('共用路徑選完整套件：'+$path)
  try{
   $script:CISharedPathRules=@($original|Where-Object {$_.Name -cne $sample.Rule})
   $without=Get-CIScopedTests -Root $fixture -ChangedPaths @($path)
   Assert ($without.Scope -ceq 'scoped' -and $without.Tests -ccontains 'Unit.refs_all') ('移除規則 '+$sample.Rule+' 後該路徑不再被擋，證明完整來自規則本身：'+$path)
  }finally{$script:CISharedPathRules=$original}
 }
 foreach($path in @('modules/power/power.ps1','core/lib.ps1','test/powershell/unit/other_tests.ps1','readme.md')){Assert ($null -eq (Get-CISharedPathRule $path)) ('一般路徑不屬於任何共用規則：'+$path)}

 # 樞紐排除：只經由登錄表／總入口出現的引用不當作依賴。
 Put 'core/target.ps1' 'function Get-Target { 1 }'
 foreach($n in 1..35){Put ('core/dummy'+$n+'.ps1') 'x'}
 Put 'core/hub.ps1' ((@(1..35|ForEach-Object {"'core/dummy$_.ps1'"})+@("'core/target.ps1'")) -join "`n")
 Put 'test/powershell/unit/direct_tests.ps1' "'core/target.ps1'"
 Put 'test/powershell/unit/viahub_tests.ps1' "'core/hub.ps1'"
 $hub=Get-CIScopedTests -Root $fixture -ChangedPaths @('core/target.ps1')
 Assert ($hub.Scope -ceq 'scoped' -and $hub.Tests -ccontains 'Unit.direct' -and $hub.Tests -cnotcontains 'Unit.viahub') '樞紐檔不當作引用鏈的中繼點'
 $savedLimit=$script:CIHubReferenceLimit
 try{
  $script:CIHubReferenceLimit=1000
  $noHub=Get-CIScopedTests -Root $fixture -ChangedPaths @('core/target.ps1')
  Assert ($noHub.Tests -ccontains 'Unit.viahub') '關閉樞紐排除後經由樞紐的 suite 會被牽入，證明排除確實生效'
 }finally{$script:CIHubReferenceLimit=$savedLimit}
 $viaHubOnly=Get-CIScopedTests -Root $fixture -ChangedPaths @('core/dummy1.ps1')
 Assert ($viaHubOnly.Scope -ceq 'full') '只被樞紐引用的檔案沒有測試引用，選完整套件'

 # 引用鏈檔案數上限。
 Put 'core/chain_target.ps1' 'x'
 foreach($n in 1..3){Put ('core/chain'+$n+'.ps1') "'core/chain_target.ps1'"}
 Put 'test/powershell/unit/chain_tests.ps1' "'core/chain1.ps1'"
 $chain=Get-CIScopedTests -Root $fixture -ChangedPaths @('core/chain_target.ps1')
 Assert ($chain.Scope -ceq 'scoped' -and $chain.Tests -ccontains 'Unit.chain') '引用鏈在上限內時縮小'
 $savedFiles=$script:CIMaxScopedFiles
 try{
  $script:CIMaxScopedFiles=2
  $capped=Get-CIScopedTests -Root $fixture -ChangedPaths @('core/chain_target.ps1')
  Assert ($capped.Scope -ceq 'full') '引用鏈檔案數超過上限時選完整套件'
 }finally{$script:CIMaxScopedFiles=$savedFiles}

 # 被刪除的測試檔不會自行加入 suite；存在的被改測試檔才會。
 $gone=Get-CIScopedTests -Root $fixture -ChangedPaths @('test/powershell/unit/gone_tests.ps1')
 Assert ($gone.Scope -ceq 'scoped' -and $gone.Tests -cnotcontains 'Unit.gone') '已刪除的測試檔不加入執行清單'
 $present=Get-CIScopedTests -Root $fixture -ChangedPaths @('test/powershell/unit/other_tests.ps1')
 Assert ($present.Tests -ccontains 'Unit.other') '仍存在的被改測試檔一定執行'
}finally{
 if($fixture.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
