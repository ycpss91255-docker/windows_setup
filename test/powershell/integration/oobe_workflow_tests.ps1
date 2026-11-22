#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
function Test-RollupFailure([string]$Message,[string]$Name){return $Message -ceq ('必要工作失敗、取消或跳過：'+$Name)}
$rollup=[regex]::Match($workflow,'(?ms)^  ci-rollup:\r?\n(?<body>.*?)^  release:').Groups['body'].Value
$scriptText=([regex]::Match($rollup,'(?ms)        run: \|\r?\n(?<body>.*)$').Groups['body'].Value -replace '(?m)^          ','').Trim()
$priorCoverageResult=$env:COVERAGE_RESULT
$priorSummaryPath=$env:GITHUB_STEP_SUMMARY
$summaryPath=Join-Path ([IO.Path]::GetTempPath()) ('oobe_rollup_summary_'+[guid]::NewGuid().ToString('N')+'.md')
$env:GITHUB_STEP_SUMMARY=$summaryPath
try {
$classifyKeys=@('CLASSIFY_RESULT','DOC_CHECKS_RESULT','SELECT_TESTS','SELECT_REQUIREMENTS','SELECT_DOCKER','SELECT_PAYLOAD','SELECT_POWERSHELL_COVERAGE','SELECT_COVERAGE','SELECT_DOC_CHECKS')
$env:CLASSIFY_RESULT='success';$env:DOC_CHECKS_RESULT='skipped';$env:SELECT_DOC_CHECKS='false'
foreach($selectKey in @('SELECT_TESTS','SELECT_REQUIREMENTS','SELECT_DOCKER','SELECT_PAYLOAD','SELECT_POWERSHELL_COVERAGE','SELECT_COVERAGE')){[Environment]::SetEnvironmentVariable($selectKey,'true','Process')}
$env:TEST_RESULT='success';$env:REQUIREMENTS_RESULT='success';$env:DOCKER_RESULT='success';$env:POWERSHELL_COVERAGE_RESULT='success';$env:OOBE_PAYLOAD_RESULT='failure';$env:COVERAGE_RESULT='success'
$rejected=$false;try{& ([scriptblock]::Create($scriptText))}catch{$rejected=Test-RollupFailure $_.Exception.Message 'Payload'}
Assert $rejected 'actual ci-rollup rejects failed OOBE package content inspection'
$env:OOBE_PAYLOAD_RESULT='success'
& ([scriptblock]::Create($scriptText))
Assert $true 'actual ci-rollup accepts all required jobs succeeding'
$env:POWERSHELL_COVERAGE_RESULT='failure'
$rejected=$false;try{& ([scriptblock]::Create($scriptText))}catch{$rejected=Test-RollupFailure $_.Exception.Message 'PowerShellCoverage'}
Assert $rejected 'actual ci-rollup rejects failed or incomplete PowerShell shard matrix'
$env:POWERSHELL_COVERAGE_RESULT='success'
foreach($state in @('failure','cancelled','skipped','')){
 $env:COVERAGE_RESULT=$state;$rejected=$false
 try{& ([scriptblock]::Create($scriptText))}catch{$rejected=Test-RollupFailure $_.Exception.Message 'Coverage'}
 Assert $rejected ('actual ci-rollup rejects incomplete final coverage aggregation: '+$state)
}
$env:COVERAGE_RESULT='failure'
$wrongScript=$scriptText.Replace('$env:POWERSHELL_COVERAGE_RESULT','$env:COVERAGE_RESULT')
$wrongMessage='';try{& ([scriptblock]::Create($wrongScript))}catch{$wrongMessage=$_.Exception.Message}
Assert ((Test-RollupFailure $wrongMessage 'PowerShellCoverage') -and -not (Test-RollupFailure $wrongMessage 'Coverage')) 'wrong PowerShellCoverage failure cannot satisfy Coverage check'
$env:COVERAGE_RESULT='success'
# 純文件 PR：分類成功、重型工作 skipped 且選擇為 false 時 actual ci-rollup 通過；被選中的工作 skipped 仍拒絕。
foreach($resultKey in @('TEST_RESULT','REQUIREMENTS_RESULT','DOCKER_RESULT','POWERSHELL_COVERAGE_RESULT','OOBE_PAYLOAD_RESULT','COVERAGE_RESULT')){[Environment]::SetEnvironmentVariable($resultKey,'skipped','Process')}
foreach($selectKey in @('SELECT_TESTS','SELECT_REQUIREMENTS','SELECT_DOCKER','SELECT_PAYLOAD','SELECT_POWERSHELL_COVERAGE','SELECT_COVERAGE')){[Environment]::SetEnvironmentVariable($selectKey,'false','Process')}
$env:DOC_CHECKS_RESULT='success';$env:SELECT_DOC_CHECKS='true'
$docAccepted=$true;try{& ([scriptblock]::Create($scriptText))}catch{$docAccepted=$false}
Assert $docAccepted 'actual ci-rollup accepts document-only PR when classify excused every skipped heavy job'
$env:SELECT_DOCKER='true'
$selectedSkipped=$false;try{& ([scriptblock]::Create($scriptText))}catch{$selectedSkipped=Test-RollupFailure $_.Exception.Message 'Docker'}
Assert $selectedSkipped 'actual ci-rollup rejects a skipped job that classify selected'
$env:SELECT_DOCKER='false';$env:CLASSIFY_RESULT='failure'
$classifyFailed=$false;try{& ([scriptblock]::Create($scriptText))}catch{$classifyFailed=$true}
Assert $classifyFailed 'actual ci-rollup trusts no skipped job when classify failed'
}finally{foreach($resultKey in @('TEST_RESULT','REQUIREMENTS_RESULT','DOCKER_RESULT','POWERSHELL_COVERAGE_RESULT','OOBE_PAYLOAD_RESULT')+$classifyKeys){[Environment]::SetEnvironmentVariable($resultKey,$null,'Process')};$env:COVERAGE_RESULT=$priorCoverageResult;$env:GITHUB_STEP_SUMMARY=$priorSummaryPath;if(Test-Path -LiteralPath $summaryPath){[IO.File]::Delete($summaryPath)}}
$job=[regex]::Match($workflow,'(?ms)^  oobe_payload_inspection:\r?\n(?<body>.*?)(?=^  [a-z][a-z_-]+:)').Groups['body'].Value
function Test-PayloadJobDependencies([string]$Job){return $Job -match '(?m)^    runs-on: windows-2022\s*$' -and [regex]::Matches($Job,'(?m)^    needs:').Count -eq 1 -and $Job -match '(?m)^    needs: \[source-preflight, classify\]\s*$'}
Assert (Test-PayloadJobDependencies $job) 'payload inspection runs on Windows after source preflight only'
foreach($expensive in @('isolated-tests','docker-tests','powershell-coverage','coverage-aggregation')){
 $wrongJob=$job.Replace('needs: [source-preflight, classify]',('needs: [source-preflight, classify, '+$expensive+']'))
 Assert (-not (Test-PayloadJobDependencies $wrongJob)) ('payload inspection rejects extra expensive dependency: '+$expensive)
}
Assert ($job.Contains('verify_oobe_payload.ps1') -and $job.Contains('payload_baseline.json') -and $job.Contains('if: always()') -and $job.Contains('retention-days: 7')) 'CI invokes real reader with reviewed baseline and preserves failure evidence seven days'
Assert ($job -match '(?s)name:.*?三檔來源與實際雜湊\r?\n\s+shell: powershell\r?\n\s+run: \|\r?\n\s+.*provisioning_source_tests\.ps1' -and $job -match '(?s)id: payload\r?\n\s+if: always\(\)') 'CI names real source verification accurately and preserves independent native WIM inspection'
Assert ($rollup.Contains('oobe_payload_inspection') -and $rollup.Contains('needs.oobe_payload_inspection.result')) 'rollup dependency and result refer to real payload job'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('oobe_workflow_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'script/test') -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $fixture 'script/test/verify_oobe_payload.ps1'),'param($PackagePath,$EvidenceDirectory,$BaselinePath); [IO.File]::WriteAllText((Join-Path $PWD "capture.json"),(@{EvidenceDirectory=$EvidenceDirectory;OutputBeforeRead=[IO.File]::ReadAllText($env:GITHUB_OUTPUT)}|ConvertTo-Json))')
$run=([regex]::Match($job.Substring($job.IndexOf('id: payload')),'(?ms)        run: \|\r?\n(?<body>.*?)(?=^      - name:)').Groups['body'].Value -replace '(?m)^          ','').Trim()
$oldRunner=$env:RUNNER_TEMP;$oldOutput=$env:GITHUB_OUTPUT
try{
 $env:RUNNER_TEMP=Join-Path $fixture 'different_runner_temp';$env:GITHUB_OUTPUT=Join-Path $fixture 'github_output'
 [IO.File]::WriteAllText($env:GITHUB_OUTPUT,'')
 Push-Location $fixture
 try{& ([scriptblock]::Create($run))}finally{Pop-Location}
 $capture=[IO.File]::ReadAllText((Join-Path $fixture 'capture.json'))|ConvertFrom-Json
 Assert ((Split-Path $capture.EvidenceDirectory -Parent).TrimEnd('\') -eq ([IO.Path]::GetTempPath()).TrimEnd('\')) 'real workflow selects native TEMP when RUNNER_TEMP differs'
 Assert ($capture.OutputBeforeRead.Contains('evidence='+$capture.EvidenceDirectory)) 'workflow publishes evidence output before invoking reader'
 Assert ($job.Contains('id: payload') -and $job.Contains('path: ${{ steps.payload.outputs.evidence }}')) 'artifact upload uses the exact reader output path'
}finally{$env:RUNNER_TEMP=$oldRunner;$env:GITHUB_OUTPUT=$oldOutput}
Write-Host ('ALL PASS: '+$script:count+' workflow contract assertions')
