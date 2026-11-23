#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
. (Join-Path $root 'script/test/ci_classify.ps1')
Assert ($null -ne (Get-Command Get-CIScopedTests -ErrorAction SilentlyContinue)) '提供依變更路徑選測的函式'
$fixture=Join-Path $env:TEMP ('ci_scope_'+[guid]::NewGuid().ToString('N'))
try{
 $utf8=[Text.UTF8Encoding]::new($true)
 function Put($Relative,$Text){$full=Join-Path $fixture $Relative;[void][IO.Directory]::CreateDirectory((Split-Path $full -Parent));[IO.File]::WriteAllText($full,$Text,$utf8)}
 Put 'core/lib.ps1' 'function Get-Lib { 1 }'
 Put 'modules/power/power.ps1' ". (Join-Path `$PSScriptRoot '../../core/lib.ps1')"
 Put 'modules/power/orphan.ps1' 'nothing references this'
 Put 'modules/power/settings.json' '{}'
 Put 'modules/power/reader.ps1' "Get-Content (Join-Path `$PSScriptRoot 'settings.json')"
 Put 'test/powershell/unit/power_tests.ps1' "`$f=Join-Path `$root 'modules/power/power.ps1'"
 Put 'test/powershell/unit/reader_tests.ps1' "`$f=Join-Path `$root 'modules/power/reader.ps1'"
 Put 'test/powershell/unit/other_tests.ps1' "'unrelated'"
 Put 'test/powershell/integration/architecture_tests.ps1' "'global contract'"
 Put 'test/powershell/integration/layout_tests.ps1' "'global contract'"
 Put 'test/powershell/integration/markdown_line_ending_tests.ps1' "'global contract'"
 Put 'doc/guide.md' 'guide'
 Put 'test/powershell/unit/guide_tests.ps1' "`$t=Join-Path `$root 'doc/guide.md'"
 Put 'core/wide.ps1' 'function Get-Wide { 1 }'
 foreach($n in 1..12){Put ('test/powershell/unit/wide'+$n+'_tests.ps1') "`$f=Join-Path `$root 'core/wide.ps1'"}
 foreach($n in 1..10){Put ('test/powershell/unit/filler'+$n+'_tests.ps1') "'unrelated'"}
 function Scope([string[]]$Paths,[int]$Max=0){Get-CIScopedTests -Root $fixture -ChangedPaths $Paths -MaxSuites $Max}
 $global=@('Integration.architecture','Integration.layout','Integration.markdown_line_ending')

 $direct=Scope @('modules/power/power.ps1')
 Assert ($direct.Scope -ceq 'scoped' -and $direct.Tests -ccontains 'Unit.power' -and $direct.Tests -cnotcontains 'Unit.other' -and $direct.Tests -cnotcontains 'Unit.reader') '只選引用被改程式的測試'
 Assert (@($global|Where-Object {$direct.Tests -cnotcontains $_}).Count -eq 0) '全域契約測試總是列入'
 $transitive=Scope @('core/lib.ps1')
 Assert ($transitive.Scope -ceq 'scoped' -and $transitive.Tests -ccontains 'Unit.power') '以引用鏈追到間接依賴的測試'
 $data=Scope @('modules/power/settings.json')
 Assert ($data.Scope -ceq 'scoped' -and $data.Tests -ccontains 'Unit.reader' -and $data.Tests -cnotcontains 'Unit.power') '資料檔經由讀取它的程式追到測試'
 $self=Scope @('test/powershell/unit/other_tests.ps1')
 Assert ($self.Scope -ceq 'scoped' -and $self.Tests -ccontains 'Unit.other') '被改的測試檔自己一定執行'
 $deleted=Scope @('modules/power/gone.ps1','modules/power/power.ps1')
 Assert ($deleted.Scope -ceq 'full') '已刪除且無任何測試引用的路徑無法判斷而選完整套件'
 Remove-Item -LiteralPath (Join-Path $fixture 'modules/power/reader.ps1')
 $deletedRef=Scope @('modules/power/reader.ps1')
 Assert ($deletedRef.Scope -ceq 'scoped' -and $deletedRef.Tests -ccontains 'Unit.reader') '刪除的檔案仍以測試中的引用選出對應測試'
 Put 'modules/power/reader.ps1' "Get-Content (Join-Path `$PSScriptRoot 'settings.json')"
 $unknown=Scope @('modules/power/orphan.ps1')
 Assert ($unknown.Scope -ceq 'full') '沒有任何測試引用的程式碼無法判斷而選完整套件'
 $mixed=Scope @('modules/power/power.ps1','modules/power/orphan.ps1')
 Assert ($mixed.Scope -ceq 'full') '只要一個路徑無法判斷整體就選完整套件'
 $renamed=Scope @('modules/power/power.ps1','modules/power/power_new.ps1')
 Assert ($renamed.Scope -ceq 'full') '改名後的新路徑沒有測試引用時選完整套件'
 foreach($shared in @('.github/workflows/windows_tests.yml','.github/actions/x.yml','go.mod','go.sum','vendor/modules.txt','.version','script/test/ci_classify.ps1','script/test/run_ci.ps1','test/powershell/helpers/run_module_fixture.ps1','test/powershell/support/runner_fixture.ps1','test/powershell/coverage/safe_suite.ps1','test/powershell/fixtures/compile_native.ps1','dockerfile','compose.yaml','script/docker/container_test.ps1','core/paths.json','core/paths.ps1')){
  $result=Scope @('modules/power/power.ps1',$shared)
  Assert ($result.Scope -ceq 'full') ('共用或全域路徑一律選完整套件：'+$shared)
 }
 foreach($bad in @('modules/../core/lib.ps1','modules\power\power.ps1','/modules/power/power.ps1','modules//power/power.ps1','')){
  Assert ((Scope @($bad)).Scope -ceq 'full') ('可疑路徑選完整套件：['+$bad+']')
 }
 foreach($empty in @($null,@())){Assert ((Get-CIScopedTests -Root $fixture -ChangedPaths $empty -MaxSuites 40).Scope -ceq 'full') '沒有變更清單時選完整套件'}
 $wide=Scope @('modules/power/power.ps1') 1
 $defaultWide=Get-CIScopedTests -Root $fixture -ChangedPaths @('core/wide.ps1')
 Assert ($defaultWide.Scope -ceq 'full') '預設上限是全部 suite 的一半，超過就選完整套件'
 $defaultNarrow=Get-CIScopedTests -Root $fixture -ChangedPaths @('modules/power/power.ps1')
 Assert ($defaultNarrow.Scope -ceq 'scoped') '低於預設上限時縮小範圍'
 Assert ($wide.Scope -ceq 'full') '受影響測試超過指定上限時選完整套件'
 foreach($goPath in @('script/test/requirements_gate/main.go','test/go/unit/x_test.go','test/go/integration/cli_test.go','script/test/repo_coverage_tool/main.go')){
  Assert ((Scope @($goPath)).Scope -ceq 'full') ('Go 變更的整合測試依賴完整 PowerShell 報告，選完整套件：'+$goPath)
  Assert ((Scope @($goPath,'modules/power/power.ps1')).Scope -ceq 'full') ('Go 與 PowerShell 同時變更選完整套件：'+$goPath)
 }
 $withDoc=Scope @('doc/guide.md','modules/power/power.ps1')
 Assert ($withDoc.Scope -ceq 'scoped' -and $withDoc.Tests -ccontains 'Unit.guide' -and $withDoc.Tests -ccontains 'Unit.power') '文件與程式碼混合時兩邊的測試都選'
 $sorted=@($withDoc.Tests|Sort-Object)
 Assert ((($withDoc.Tests) -join ',') -ceq ($sorted -join ',') -and @($withDoc.Tests|Select-Object -Unique).Count -eq @($withDoc.Tests).Count) '測試清單排序且不重複'
 foreach($name in @($withDoc.Tests)){Assert ($name -cmatch '^(Unit|Integration)\.[a-z0-9_]+$') ('清單只含合法 suite 名稱：'+$name)}

 # 選擇結果：只有 PR 事件才可縮小，其他事件一律完整。
 $heavy=@('powershell_coverage','coverage_aggregation','requirements_gate','docker_tests')
 $code=Get-CIChangeSelection -EventName pull_request -ChangedPaths @('modules/power/power.ps1') -Root $fixture
 $scopedOk=$code['tests'] -ceq 'true' -and $code['test_scope'] -ceq 'scoped' -and $code['doc_checks'] -ceq 'false' -and $code['affected_tests'] -clike '*Unit.power*'
 foreach($key in $heavy){if($code[$key] -cne 'false'){$scopedOk=$false}}
 Assert $scopedOk '程式碼 PR 只選受影響測試並略過覆蓋率、聚合、需求驗收與容器'
 Assert ($code['oobe_payload'] -ceq 'true') '設定包唯讀驗證仍在 PR 階段執行'
 foreach($event in @('push','merge_group','workflow_dispatch','schedule','')){
  $full=Get-CIChangeSelection -EventName $event -ChangedPaths @('modules/power/power.ps1') -Root $fixture
  $ok=$full['test_scope'] -ceq 'full' -and $full['affected_tests'] -ceq ''
  foreach($key in @('tests','oobe_payload')+$heavy){if($full[$key] -cne 'true'){$ok=$false}}
  Assert $ok ('非 PR 事件不縮小：'+$event)
 }
 $fallback=Get-CIChangeSelection -EventName pull_request -ChangedPaths @('modules/power/orphan.ps1') -Root $fixture
 $fullOk=$fallback['test_scope'] -ceq 'full'
 foreach($key in @('tests','oobe_payload')+$heavy){if($fallback[$key] -cne 'true'){$fullOk=$false}}
 Assert $fullOk '無法判斷的 PR 選完整套件'
 $docOnly=Get-CIChangeSelection -EventName pull_request -ChangedPaths @('doc/guide.md') -Root $fixture
 Assert ($docOnly['doc_checks'] -ceq 'true' -and $docOnly['tests'] -ceq 'false' -and $docOnly['test_scope'] -ceq 'full') '純文件 PR 仍走文件輕量檢查'
 $noRoot=Get-CIChangeSelection -EventName pull_request -ChangedPaths @('modules/power/power.ps1')
 Assert ($noRoot['test_scope'] -ceq 'full' -and $noRoot['tests'] -ceq 'true') '沒有可讀取的根目錄時選完整套件'

 # 真 Git diff 經腳本輸出。
 function Invoke-FixtureGit([string[]]$Arguments){$o=& git.exe -c core.autocrlf=false -C $fixture @Arguments 2>&1;if($LASTEXITCODE -ne 0){throw ($o|Out-String)};$o}
 function Commit([string]$Message){Invoke-FixtureGit @('add','-A')|Out-Null;Invoke-FixtureGit @('-c','user.name=CI Fixture','-c','user.email=fixture@example.invalid','commit','--quiet','-m',$Message)|Out-Null}
 Invoke-FixtureGit @('init','--quiet','-b','main')|Out-Null;Commit 'base'
 Invoke-FixtureGit @('checkout','--quiet','-b','topic')|Out-Null
 Put 'modules/power/power.ps1' "# changed`n. (Join-Path `$PSScriptRoot '../../core/lib.ps1')";Commit 'code'
 $out=Join-Path $fixture 'out_scoped.txt'
 & (Join-Path $root 'script/test/ci_classify.ps1') -EventName pull_request -BaseRef main -Root $fixture -OutputPath $out
 $lines=@(Get-Content -LiteralPath $out -Encoding UTF8)
 Assert (($lines -ccontains 'select_tests=true') -and ($lines -ccontains 'test_scope=scoped') -and ($lines -ccontains 'select_docker_tests=false') -and ($lines -ccontains 'select_powershell_coverage=false')) '真 Git diff 輸出縮小後的選擇'
 Assert (@($lines|Where-Object {$_ -clike 'affected_tests=*Unit.power*Integration*'}).Count -eq 0 -and @($lines|Where-Object {$_ -clike 'affected_tests=*Unit.power*'}).Count -eq 1) '輸出受影響測試清單'
 $outOpen=Join-Path $fixture 'out_open.txt'
 & (Join-Path $root 'script/test/ci_classify.ps1') -FailOpen -OutputPath $outOpen
 $open=@(Get-Content -LiteralPath $outOpen -Encoding UTF8)
 Assert (($open -ccontains 'test_scope=full') -and ($open -ccontains 'affected_tests=') -and ($open -ccontains 'select_docker_tests=true')) 'FailOpen 輸出完整範圍'
 $outBad=Join-Path $fixture 'out_bad.txt'
 & (Join-Path $root 'script/test/ci_classify.ps1') -EventName pull_request -BaseRef no_such_ref -Root $fixture -OutputPath $outBad
 Assert ((@(Get-Content -LiteralPath $outBad -Encoding UTF8)) -ccontains 'test_scope=full') '取不到 diff 時完整範圍'
}finally{
 if($fixture.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $fixture -Recurse -Force}
}

# workflow 契約：縮小範圍只影響受影響測試，其他事件與無法判斷時走完整步驟。
function Test-ScopedWorkflow([string]$Workflow){
 $text=$Workflow.Replace("`r`n","`n")
 $classify=[regex]::Match($text,'(?ms)^  classify:\n(?<body>.*?)^  doc-checks:').Groups['body'].Value
 $isolated=[regex]::Match($text,'(?ms)^  isolated-tests:\n(?<body>.*?)^  coverage-aggregation:').Groups['body'].Value
 $rollup=[regex]::Match($text,'(?ms)^  ci-rollup:\n(?<body>.*?)^  release:').Groups['body'].Value
 $ok=$classify.Contains('test_scope: ${{ steps.classify.outputs.test_scope || steps.fallback.outputs.test_scope }}') -and $classify.Contains('affected_tests: ${{ steps.classify.outputs.affected_tests }}')
 $ok=$ok -and $isolated.Contains("if: needs.classify.outputs.test_scope == 'scoped'") -and $isolated.Contains('-Parallelism 2 -Suite ($env:AFFECTED_TESTS -split '','')') -and $isolated.Contains('AFFECTED_TESTS: ${{ needs.classify.outputs.affected_tests }}')
 foreach($step in @('執行 Windows PowerShell 5.1 隔離測試','執行全部 Go 維護工具測試','驗證手機與桌面報表明細排版','封裝尚未完成 runtime 覆蓋率的原生證據','僅保留不可發布的同次原生中介證據七天')){
  $body=[regex]::Match($isolated,'(?ms)^      - name: '+[regex]::Escape($step)+'\n(?<body>.*?)(?=^      - name: |\z)').Groups['body'].Value
  $ok=$ok -and $body.Contains("needs.classify.outputs.test_scope != 'scoped'")
 }
 $ok=$ok -and $classify.Contains('path: base-source') -and $classify.Contains('ref: ${{ github.event.pull_request.base.sha || github.sha }}') -and $classify.Contains('& ./base-source/script/test/ci_classify.ps1') -and -not [regex]::IsMatch($classify,'(?m)&\s+\./script/test/ci_classify\.ps1')
 $fallback=[regex]::Match($classify,'(?ms)id: fallback\n(?<body>.*?)\z').Groups['body'].Value
 $ok=$ok -and $fallback.Contains("test_scope=full") -and $fallback.Contains('select_docker_tests=true') -and $fallback.Contains('select_tests=true') -and -not $fallback.Contains('ci_classify.ps1')
 $merge=[regex]::Match($isolated,'(?ms)^      - name: 核對本次新增合併提交標題\n(?<body>.*?)(?=^      - name: |\z)').Groups['body'].Value
 $ok=$ok -and -not $merge.Contains('test_scope') -and $merge.Contains('mergecheck')
 $ok=$ok -and $rollup.Contains('EVENT_NAME: ${{ github.event_name }}') -and $rollup.Contains('-EventName $env:EVENT_NAME')
 return $ok
}
$workflowText=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
Assert (Test-ScopedWorkflow $workflowText) 'workflow 只在 PR 縮小範圍：完整步驟以 test_scope 排除、合併標題核對恆執行、rollup 帶入事件名稱'
Assert (-not (Test-ScopedWorkflow $workflowText.Replace("needs.classify.outputs.test_scope != 'scoped'","true"))) '移除任一完整步驟的排除條件即被契約拒絕'
Assert (-not (Test-ScopedWorkflow $workflowText.Replace('-EventName $env:EVENT_NAME',''))) 'rollup 不帶事件名稱即被契約拒絕'

# 端到端：以分類器的實際輸出決定各工作結果，再執行 workflow 內 ci-rollup 步驟的實際腳本，逐事件核對判定。
function Get-RollupScript([string]$Workflow){
 $text=$Workflow.Replace("`r`n","`n")
 $rollup=[regex]::Match($text,'(?ms)^  ci-rollup:\n(?<body>.*?)^  release:').Groups['body'].Value
 $run=[regex]::Match($rollup,'(?ms)^        run: \|\n(?<body>.*?)(?=^\S|^      - name: |\z)').Groups['body'].Value
 return (($run -split "`n"|ForEach-Object {if($_.Length -ge 10){$_.Substring(10)}else{$_.TrimStart()}}) -join "`n")
}
function Invoke-RollupScenario([string]$Event,[string[]]$Paths,[hashtable]$Override){
 $sel=Get-CIChangeSelection -EventName $Event -ChangedPaths $Paths -Root $root
 $map=@{TEST_RESULT='tests';REQUIREMENTS_RESULT='requirements_gate';DOCKER_RESULT='docker_tests';OOBE_PAYLOAD_RESULT='oobe_payload';POWERSHELL_COVERAGE_RESULT='powershell_coverage';COVERAGE_RESULT='coverage_aggregation';DOC_CHECKS_RESULT='doc_checks'}
 $envs=@{EVENT_NAME=$Event;CLASSIFY_RESULT='success';SELECT_TESTS=$sel['tests'];SELECT_REQUIREMENTS=$sel['requirements_gate'];SELECT_DOCKER=$sel['docker_tests'];SELECT_PAYLOAD=$sel['oobe_payload'];SELECT_POWERSHELL_COVERAGE=$sel['powershell_coverage'];SELECT_COVERAGE=$sel['coverage_aggregation'];SELECT_DOC_CHECKS=$sel['doc_checks']}
 foreach($k in $map.Keys){$envs[$k]=$(if($sel[$map[$k]] -ceq 'true'){'success'}else{'skipped'})}
 if($Override){foreach($k in $Override.Keys){$envs[$k]=$Override[$k]}}
 $script=Join-Path $env:TEMP ('rollup_'+[guid]::NewGuid().ToString('N')+'.ps1');$summary=$script+'.md'
 [IO.File]::WriteAllText($script,(Get-RollupScript $workflowText),[Text.UTF8Encoding]::new($true))
 $saved=@{};$names=@($envs.Keys)+@('GITHUB_STEP_SUMMARY')
 foreach($n in $names){$saved[$n]=[Environment]::GetEnvironmentVariable($n)}
 try{
  foreach($k in $envs.Keys){[Environment]::SetEnvironmentVariable($k,[string]$envs[$k])}
  [Environment]::SetEnvironmentVariable('GITHUB_STEP_SUMMARY',$summary)
  Push-Location $root
  $previousPreference=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$null=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script 2>&1;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$previousPreference;Pop-Location}
 }finally{
  foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$saved[$n])}
  Remove-Item -LiteralPath $script,$summary -Force -ErrorAction SilentlyContinue
 }
 return [pscustomobject]@{Passed=($code -eq 0);Selection=$sel}
}
$rollupScript=Get-RollupScript $workflowText
Assert ($rollupScript.Contains('Resolve-CIRollupStates') -and $rollupScript.Contains('Assert-CIResults')) '能從 workflow 取出 ci-rollup 步驟的實際腳本'
$docPr=Invoke-RollupScenario 'pull_request' @('readme.md')
Assert ($docPr.Passed -and $docPr.Selection['doc_checks'] -ceq 'true' -and $docPr.Selection['tests'] -ceq 'false') '端到端：pull_request 純文件只跑文件檢查，rollup 通過'
$codePr=Invoke-RollupScenario 'pull_request' @('core/paths.json')
Assert ($codePr.Passed -and $codePr.Selection['doc_checks'] -ceq 'false' -and $codePr.Selection['tests'] -ceq 'true') '端到端：pull_request 程式變更（共用路徑，完整套件）rollup 通過'
foreach($event in @('merge_group','push','workflow_dispatch','tag')){
 $r=Invoke-RollupScenario $event $null
 Assert ($r.Passed -and $r.Selection['doc_checks'] -ceq 'false' -and $r.Selection['test_scope'] -ceq 'full') ('端到端：'+$event+' 完整套件、文件檢查未選取且 skipped，rollup 通過')
 $other=Invoke-RollupScenario $event $null @{DOCKER_RESULT='skipped'}
 Assert (-not $other.Passed) ('端到端：'+$event+' 其他工作 skipped，rollup 必須失敗')
 $docFail=Invoke-RollupScenario $event $null @{DOC_CHECKS_RESULT='failure'}
 Assert (-not $docFail.Passed) ('端到端：'+$event+' 文件檢查失敗，rollup 必須失敗')
}
