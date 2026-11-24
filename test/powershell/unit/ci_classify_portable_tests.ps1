#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$classifier=Join-Path $root 'script/test/ci_classify.ps1'
$smokeScript=Join-Path $root 'script/test/ci_classify_smoke.ps1'
$summaryScript=Join-Path $root 'script/test/ci_quality_summary.ps1'
$utf8=[Text.UTF8Encoding]::new($false)
# 分類工作在 ubuntu 上執行：它載入的腳本不得呼叫只存在於 Windows 的 .exe。
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml')).Replace("`r`n","`n")
$classifyJob=[regex]::Match($workflow,'(?ms)^  classify:\n.*?(?=^  [a-z][a-z0-9_-]*:\n)').Value
Assert ($classifyJob -match 'runs-on: ubuntu') '分類工作在 Linux 執行'
$linuxScripts=@([regex]::Matches($classifyJob,'script/test/[A-Za-z0-9_]+\.ps1')|ForEach-Object {$_.Value}|Sort-Object -Unique)
Assert ($linuxScripts -contains 'script/test/ci_classify.ps1') '分類工作使用分類器'
Assert ($linuxScripts -contains 'script/test/ci_classify_smoke.ps1') '分類工作執行分類器 smoke'
foreach($relative in $linuxScripts){
 $text=[IO.File]::ReadAllText((Join-Path $root $relative))
 Assert (-not [regex]::IsMatch($text,'(?i)\b[a-z0-9_-]+\.exe\b')) ('Linux 分類工作載入的腳本不呼叫 .exe：'+$relative)
}
. $classifier
. $smokeScript
. $summaryScript
# 變更路徑以 git 取得，不綁 git.exe：以同名函式替身觀察實際呼叫。
$script:gitCalls=@()
function git {$script:gitCalls+=,@($args);$global:LASTEXITCODE=0;'readme.md';'doc/ci_guide.md'}
$paths=Get-CIChangedPaths -Root 'fixture-root' -BaseRef 'origin/main'
Assert ($script:gitCalls.Count -eq 1 -and $script:gitCalls[0] -contains 'diff' -and $script:gitCalls[0] -contains 'fixture-root' -and $script:gitCalls[0] -contains 'origin/main...HEAD') '變更路徑呼叫 git diff 且不指定 .exe'
Assert (($paths -join ',') -ceq 'readme.md,doc/ci_guide.md') '變更路徑逐行回傳'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ci_classify_portable_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$oldSummary=$env:GITHUB_STEP_SUMMARY
try{
 $env:GITHUB_STEP_SUMMARY=Join-Path $temp 'summary.md'
 # 正常分類：輸出 classify_fallback=false，不寫退回完整套件的摘要。
 $ok=Join-Path $temp 'ok.txt'
 Invoke-CIClassify -EventName pull_request -BaseRef 'origin/main' -Root $root -OutputPath $ok 6>$null
 $okText=[IO.File]::ReadAllText($ok)
 Assert ($okText -match '(?m)^classify_fallback=false$' -and $okText -match '(?m)^select_doc_checks=true$') '分類成功時標示未退回且只選文件檢查'
 Assert (-not (Test-Path -LiteralPath $env:GITHUB_STEP_SUMMARY)) '分類成功時不寫退回摘要'
 # 分類失敗：退回完整套件，輸出與 step summary 都明確標示並含原因。
 function git {$global:LASTEXITCODE=128;$null}
 $bad=Join-Path $temp 'bad.txt'
 Invoke-CIClassify -EventName pull_request -BaseRef 'origin/main' -Root $root -OutputPath $bad 6>$null 3>$null
 $badText=[IO.File]::ReadAllText($bad)
 Assert ($badText -match '(?m)^classify_fallback=true$' -and $badText -match '(?m)^test_scope=full$') '分類失敗時輸出標示退回並選完整套件'
 Assert ($badText -match '(?m)^classify_fallback_reason=.+$' -and ($badText -split "`n"|Where-Object {$_ -like 'classify_fallback_reason=*'}).Count -eq 1) '退回原因為單行輸出'
 $summary=[IO.File]::ReadAllText($env:GITHUB_STEP_SUMMARY)
 Assert ($summary -match '改跑完整套件' -and $summary -match '分類') 'step summary 明確標示分類失敗改跑完整套件'
 # ci-rollup 的標示：只在退回時寫入。
 $rollup=Join-Path $temp 'rollup.md'
 Write-CIClassifyFallbackNotice -Fallback 'false' -SummaryPath $rollup
 Assert (-not (Test-Path -LiteralPath $rollup)) 'rollup 在未退回時不寫標示'
 Write-CIClassifyFallbackNotice -Fallback 'true' -SummaryPath $rollup
 Assert ([IO.File]::ReadAllText($rollup) -match '改跑完整套件') 'rollup 在退回時明顯標示'
}finally{
 Remove-Item Function:\git -ErrorAction SilentlyContinue
 $env:GITHUB_STEP_SUMMARY=$oldSummary
}
# smoke：在暫時 git 倉庫上真實執行分類器，只改文件必須得到輕量範圍；退回完整套件即失敗。
$result=Invoke-CIClassifierSmoke -ClassifierPath $classifier 6>$null
Assert ($result -and $result['select_doc_checks'] -ceq 'true' -and $result['classify_fallback'] -ceq 'false') 'smoke 在暫時倉庫得到文件輕量範圍且未退回'
$fake=Join-Path $temp 'fake_classifier.ps1'
[IO.File]::WriteAllText($fake,"param([string]`$EventName,[string]`$BaseRef,[string]`$Root,[string]`$OutputPath)`n[IO.File]::AppendAllText(`$OutputPath,'classify_fallback=true'+[char]10+'select_doc_checks=false'+[char]10)",$utf8)
$rejected=$false
try{Invoke-CIClassifierSmoke -ClassifierPath $fake 6>$null|Out-Null}catch{$rejected=$true}
Assert $rejected 'smoke 遇到退回完整套件的分類器即失敗'
Remove-Item -LiteralPath $temp -Recurse -Force
Write-Host 'ALL PASS: classify uses portable git, smoke, and visible fallback'
