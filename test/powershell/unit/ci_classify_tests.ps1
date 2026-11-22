#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$script=Join-Path $root 'script/test/ci_classify.ps1'
Assert (Test-Path -LiteralPath $script -PathType Leaf) '提供 PR 變更分類腳本'
. $script
$heavy=@('tests','powershell_coverage','coverage_aggregation','requirements_gate','docker_tests','oobe_payload')
function Test-Full($Selection,[string]$Name){
 $ok=$Selection['doc_checks'] -ceq 'false'
 foreach($key in $heavy){if($Selection[$key] -cne 'true'){$ok=$false}}
 Assert $ok $Name
}
$doc=Get-CIChangeSelection -EventName pull_request -ChangedPaths @('readme.md','doc/ci_guide.md','doc/changelog/changelog.md','.github/pull_request_template.md','license','agents.md')
$onlyDoc=$doc['doc_checks'] -ceq 'true'
foreach($key in $heavy){if($doc[$key] -cne 'false'){$onlyDoc=$false}}
Assert $onlyDoc '只改文件的 PR 只選輕量文件檢查，不選任何重型工作'
Test-Full (Get-CIChangeSelection -EventName pull_request -ChangedPaths @('modules/power/power.ps1')) '程式碼 PR 目前選完整套件'
Test-Full (Get-CIChangeSelection -EventName pull_request -ChangedPaths @('readme.md','core/common.ps1')) '文件與程式碼混合視為程式碼 PR'
Test-Full (Get-CIChangeSelection -EventName pull_request -ChangedPaths @('.github/workflows/windows_tests.yml')) 'workflow 變更不是文件'
Test-Full (Get-CIChangeSelection -EventName pull_request -ChangedPaths @('modules/debloat/win11debloat/LICENSE')) '第三方執行內容的 LICENSE 不屬於文件'
Test-Full (Get-CIChangeSelection -EventName pull_request -ChangedPaths @('doc/../core/x.ps1')) '含上層路徑的 doc 路徑拒絕為文件'
Test-Full (Get-CIChangeSelection -EventName pull_request -ChangedPaths @('doc\evil.ps1')) '反斜線路徑拒絕為文件'
Test-Full (Get-CIChangeSelection -EventName pull_request -ChangedPaths @('doc/tool.ps1')) 'doc 下非 Markdown 檔不是文件'
Test-Full (Get-CIChangeSelection -EventName pull_request -ChangedPaths @()) '取不到或沒有變更清單時 fail open 為完整套件'
Test-Full (Get-CIChangeSelection -EventName pull_request -ChangedPaths $null) '空輸入 fail open 為完整套件'
Test-Full (Get-CIChangeSelection -EventName pull_request -ChangedPaths @('readme.md','')) '含空白路徑 fail open 為完整套件'
foreach($event in @('push','merge_group','workflow_dispatch','schedule','')){
 Test-Full (Get-CIChangeSelection -EventName $event -ChangedPaths @('readme.md')) ('非 PR 事件一律完整套件：'+$event)
}
# 文件檢查清單由現有測試內容推導，不手寫路徑表。
$fixture=Join-Path $env:TEMP ('ci_classify_'+[guid]::NewGuid().ToString('N'))
try{
 foreach($dir in @('test/powershell/unit','test/powershell/integration')){[void][IO.Directory]::CreateDirectory((Join-Path $fixture $dir))}
 $utf8=[Text.UTF8Encoding]::new($true)
 function Put($Relative,$Text){[IO.File]::WriteAllText((Join-Path $fixture $Relative),$Text,$utf8)}
 Put 'test/powershell/unit/refs_guide_tests.ps1' "`$text=Get-Content (Join-Path `$root 'doc/guide.md')"
 Put 'test/powershell/unit/refs_other_tests.ps1' "`$text=Get-Content (Join-Path `$root 'doc/other.md')"
 Put 'test/powershell/unit/unrelated_tests.ps1' "'nothing here'"
 Put 'test/powershell/integration/architecture_tests.ps1' "'global contract'"
 Put 'test/powershell/integration/layout_tests.ps1' "'global contract'"
 Put 'test/powershell/integration/refs_readme_tests.ps1' "Test-Path (Join-Path `$root 'readme.md')"
 $names=@(Get-CIDocumentTestNames -Root $fixture -ChangedPaths @('doc/guide.md'))
 Assert ($names -ccontains 'Unit.refs_guide' -and $names -cnotcontains 'Unit.refs_other' -and $names -cnotcontains 'Unit.unrelated') '只選引用被改文件的測試'
 Assert ($names -ccontains 'Integration.architecture' -and $names -ccontains 'Integration.layout') '全域契約測試總是列入文件檢查'
 Assert ($names -cnotcontains 'Integration.refs_readme') '未引用被改文件的測試不列入'
 $readme=@(Get-CIDocumentTestNames -Root $fixture -ChangedPaths @('readme.md'))
 Assert ($readme -ccontains 'Integration.refs_readme' -and $readme -cnotcontains 'Unit.refs_guide') '以完整相對路徑比對引用'
 $sorted=@($names|Sort-Object)
 Assert (($names -join ',') -ceq ($sorted -join ',')) '輸出順序穩定'
 # 完整腳本：真 Git diff，失敗時 fail open。
 function Invoke-FixtureGit([string[]]$Arguments){$o=& git.exe -c core.autocrlf=false -C $fixture @Arguments 2>&1;if($LASTEXITCODE -ne 0){throw ($o|Out-String)};$o}
 Put 'readme.md' 'base'
 Put 'tool.ps1' "function Invoke-Tool { 'code that must be tested' }"
 Invoke-FixtureGit @('init','--quiet','-b','main')|Out-Null;Invoke-FixtureGit @('add','.')|Out-Null
 Invoke-FixtureGit @('-c','user.name=CI Fixture','-c','user.email=fixture@example.invalid','commit','--quiet','-m','base')|Out-Null
 Invoke-FixtureGit @('checkout','--quiet','-b','topic')|Out-Null
 Put 'readme.md' 'changed'
 Invoke-FixtureGit @('add','.')|Out-Null;Invoke-FixtureGit @('-c','user.name=CI Fixture','-c','user.email=fixture@example.invalid','commit','--quiet','-m','doc')|Out-Null
 $out=Join-Path $fixture 'out_doc.txt'
 & $script -EventName pull_request -BaseRef main -Root $fixture -OutputPath $out
 $lines=@(Get-Content -LiteralPath $out -Encoding UTF8)
 Assert ($lines -ccontains 'select_docker_tests=false' -and $lines -ccontains 'select_doc_checks=true' -and $lines -ccontains 'select_tests=false') '真 Git 文件 diff 只選輕量檢查'
 Assert (@($lines|Where-Object {$_ -clike 'doc_tests=*' -and $_ -clike '*Integration.architecture*' -and $_ -clike '*Integration.refs_readme*'}).Count -eq 1) '輸出文件檢查清單'
 Put 'core.ps1' 'code'
 Invoke-FixtureGit @('add','.')|Out-Null;Invoke-FixtureGit @('-c','user.name=CI Fixture','-c','user.email=fixture@example.invalid','commit','--quiet','-m','code')|Out-Null
 $outCode=Join-Path $fixture 'out_code.txt'
 & $script -EventName pull_request -BaseRef main -Root $fixture -OutputPath $outCode
 $codeLines=@(Get-Content -LiteralPath $outCode -Encoding UTF8)
 Assert ($codeLines -ccontains 'select_docker_tests=true' -and $codeLines -ccontains 'select_doc_checks=false') '真 Git 程式碼 diff 選完整套件'
 $outBad=Join-Path $fixture 'out_bad.txt'
 & $script -EventName pull_request -BaseRef 'no_such_ref' -Root $fixture -OutputPath $outBad
 $badLines=@(Get-Content -LiteralPath $outBad -Encoding UTF8)
 Assert ($badLines -ccontains 'select_docker_tests=true' -and $badLines -ccontains 'select_tests=true' -and $badLines -ccontains 'select_doc_checks=false') '無法取得 diff 時 fail open 為完整套件'
 $outPush=Join-Path $fixture 'out_push.txt'
 & $script -EventName push -BaseRef '' -Root $fixture -OutputPath $outPush
 Assert ((@(Get-Content -LiteralPath $outPush -Encoding UTF8)) -ccontains 'select_docker_tests=true') 'push 事件不需 diff 即完整套件'
 $outOpen=Join-Path $fixture 'out_open.txt'
 & $script -FailOpen -OutputPath $outOpen
 $openLines=@(Get-Content -LiteralPath $outOpen -Encoding UTF8)
 Assert (($openLines -ccontains 'select_docker_tests=true') -and ($openLines -ccontains 'select_tests=true') -and ($openLines -ccontains 'select_doc_checks=false') -and ($openLines -ccontains 'doc_tests=')) '明確 FailOpen 不讀 Git 也輸出完整套件'
 # 把程式碼改名成文件不可被改名偵測隱藏：舊 .ps1 的刪除與新 .md 的新增都必須列入。
 Invoke-FixtureGit @('checkout','--quiet','-b','renamed','main')|Out-Null
 Invoke-FixtureGit @('mv','tool.ps1','tool.md')|Out-Null
 Invoke-FixtureGit @('-c','user.name=CI Fixture','-c','user.email=fixture@example.invalid','commit','--quiet','-m','rename')|Out-Null
 $outRename=Join-Path $fixture 'out_rename.txt'
 & $script -EventName pull_request -BaseRef main -Root $fixture -OutputPath $outRename
 $renameLines=@(Get-Content -LiteralPath $outRename -Encoding UTF8)
 Assert (($renameLines -ccontains 'select_docker_tests=true') -and ($renameLines -ccontains 'select_tests=true') -and ($renameLines -ccontains 'select_doc_checks=false')) '程式碼改名為 Markdown 仍選完整套件'
 $changed=@(Get-CIChangedPaths -Root $fixture -BaseRef main)
 Assert (($changed -ccontains 'tool.ps1') -and ($changed -ccontains 'tool.md')) '變更清單同時列出改名前後路徑'
}finally{
 if($fixture.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
