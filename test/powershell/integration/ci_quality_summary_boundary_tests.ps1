#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Get-AssertionEvents([object[]]$Lines){
 $events=@(foreach($line in $Lines){
  $text=[string]$line
  if($text.StartsWith('@@ASSERT@@')){
   $event=$text.Substring(10)|ConvertFrom-Json
   if($event.Name -isnot [string] -or -not $event.Name -or $event.Passed -isnot [bool] -or -not $event.Passed){throw 'invalid or failed typed assertion event'}
   [pscustomobject]@{Name=$event.Name;Passed=$event.Passed}
  }
 })
 if($events.Count -eq 0){throw 'missing typed assertion events'}
 return $events
}
function Test-AssertionSequence([object[]]$Expected,[object[]]$Actual){
 if($Expected.Count -ne $Actual.Count){return $false}
 for($i=0;$i -lt $Expected.Count;$i++){if($Expected[$i].Name -cne $Actual[$i].Name -or $Expected[$i].Passed -cne $Actual[$i].Passed){return $false}}
 return $true
}
$temp=Join-Path $env:TEMP ('rollup_boundary_'+[guid]::NewGuid().ToString('N'))
foreach($dir in @('.github/workflows','test/powershell/integration','script/test')){[void][IO.Directory]::CreateDirectory((Join-Path $temp $dir))}
try {
 $source=[IO.File]::ReadAllText((Join-Path $root 'test/powershell/integration/ci_quality_summary_workflow_tests.ps1'))
 $anchor='$step=[regex]::Match'
 Assert ($source.Contains($anchor)) '實際 workflow 測試擷取入口存在'
 Copy-Item -LiteralPath (Join-Path $root 'script/test/ci_quality_summary.ps1') -Destination (Join-Path $temp 'script/test/ci_quality_summary.ps1')
 Copy-Item -LiteralPath (Join-Path $root 'script/test/ci_tasks.ps1') -Destination (Join-Path $temp 'script/test/ci_tasks.ps1')
 $workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
 $oobe=[IO.File]::ReadAllText((Join-Path $root 'test/powershell/integration/oobe_workflow_tests.ps1'))
 $oobeAnchor='$scriptText='
 Assert ($oobe.Contains($oobeAnchor)) '實際 OOBE workflow 測試擷取入口存在'
 $oobePath=Join-Path $temp 'test/powershell/integration/oobe_workflow_tests.ps1'
 [IO.File]::WriteAllText((Join-Path $temp '.github/workflows/windows_tests.yml'),$workflow,[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText($oobePath,$oobe,[Text.UTF8Encoding]::new($true))
 $previous=$ErrorActionPreference
 try{$ErrorActionPreference='Continue';$baselineResult=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $oobePath 2>&1);$baselineCode=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
 Assert ($baselineCode -eq 0) '原始 workflow 的 OOBE 控制測試成功'
 $baselineEvents=@(Get-AssertionEvents $baselineResult)
 Assert (-not (Test-AssertionSequence $baselineEvents @($baselineEvents|Select-Object -SkipLast 1))) '不可漏掉原始控制測試的最後事件'
 foreach($id in @('_Next_job','Next_Job')){
  $fixture=$workflow.Replace('cache-diagnostic-prime',$id)
  Assert ($fixture -cne $workflow) '樣本實際更改緊接 rollup 的 job ID'
  [IO.File]::WriteAllText((Join-Path $temp '.github/workflows/windows_tests.yml'),$fixture,[Text.UTF8Encoding]::new($false))
  $probe="if (`$rollup -match '(?m)^  $($id):') {throw 'rollup included next job'}`n"
  $script=$source.Replace($anchor,$probe+$anchor)
  $path=Join-Path $temp 'test/powershell/integration/ci_quality_summary_workflow_tests.ps1'
  [IO.File]::WriteAllText($path,$script,[Text.UTF8Encoding]::new($true))
  $previous=$ErrorActionPreference
  try{$ErrorActionPreference='Continue';$result=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path 2>&1);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
  if($code -ne 0 -and ($result -join "`n") -match 'rollup included next job'){Write-Host 'fixture detected rollup included next job'}
  if($code -ne 0){$result | Select-Object -Last 8 | ForEach-Object {Write-Host $_}}
  Assert ($code -eq 0 -and ($result -join "`n") -match '實際 rollup 失敗時明示未完整量測且保留失敗') ('合法後續 job ID 不可進入 rollup，且原測試完整通過：'+$id)
  $oobeFixture=$oobe.Replace($oobeAnchor,$probe+$oobeAnchor)
  [IO.File]::WriteAllText($oobePath,$oobeFixture,[Text.UTF8Encoding]::new($true))
  $previous=$ErrorActionPreference
  try{$ErrorActionPreference='Continue';$oobeResult=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $oobePath 2>&1);$oobeCode=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
  if($oobeCode -ne 0){$oobeResult | Select-Object -Last 8 | ForEach-Object {Write-Host $_}}
  Assert ($oobeCode -eq 0) ('合法後續 job ID 的 OOBE 測試成功：'+$id)
  $oobeEvents=@(Get-AssertionEvents $oobeResult)
  Assert (Test-AssertionSequence $baselineEvents $oobeEvents) ('合法後續 job ID 保留全部原始 typed 事件順序與結果：'+$id)
 }
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
$global:LASTEXITCODE=0
