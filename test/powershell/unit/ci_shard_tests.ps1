#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Name}
$library=Join-Path $root 'script/test/ci_shard_library.ps1'
Assert (Test-Path -LiteralPath $library -PathType Leaf) '提供 PR 分片選取程式庫'
. $library
$weights=@{'Unit.big'=100;'Unit.mid'=40;'Integration.mid2'=40;'Unit.small'=5}
$cases=@('Unit.big','Unit.mid','Integration.mid2','Unit.small','Unit.unknown_new','Integration.unknown_two')|ForEach-Object {@{Name=$_}}
foreach($count in 1..6){
 $names=@(foreach($index in 0..($count-1)){Select-CISuiteShard -Cases $cases -ShardIndex $index -ShardCount $count -Weights $weights -DefaultWeight 10|ForEach-Object {$_.Name}})
 Assert ($names.Count -eq $cases.Count -and @($names|Select-Object -Unique).Count -eq $cases.Count) ("分片數 $count：各片互不重疊且聯集等於完整清單")
}
$first=@(Select-CISuiteShard -Cases $cases -ShardIndex 0 -ShardCount 2 -Weights $weights -DefaultWeight 10|ForEach-Object Name)
$again=@(Select-CISuiteShard -Cases ($cases|Sort-Object {$_.Name} -Descending) -ShardIndex 0 -ShardCount 2 -Weights $weights -DefaultWeight 10|ForEach-Object Name)
Assert (($first -join ',') -ceq ($again -join ',')) '分派不受輸入順序影響而可重現'
$load=@(foreach($index in 0..1){$sum=0;foreach($case in @(Select-CISuiteShard -Cases $cases -ShardIndex $index -ShardCount 2 -Weights $weights -DefaultWeight 10)){$sum+=$(if($weights.ContainsKey($case.Name)){$weights[$case.Name]}else{10})};$sum})
Assert ([math]::Abs($load[0]-$load[1]) -le 40) '依權重貪婪平衡兩片負載'
$single=@(Select-CISuiteShard -Cases $cases -ShardIndex 0 -ShardCount 1 -Weights $weights -DefaultWeight 10)
Assert ($single.Count -eq $cases.Count) '單一分片等於完整清單'
Assert ('Unit.unknown_new' -in @(1..2|ForEach-Object {Select-CISuiteShard -Cases $cases -ShardIndex ($_-1) -ShardCount 2 -Weights $weights -DefaultWeight 10|ForEach-Object Name})) '沒有權重的新 suite 取預設權重而不會漏掉'
Reject {Select-CISuiteShard -Cases $cases -ShardIndex 2 -ShardCount 2 -Weights $weights -DefaultWeight 10} '分片索引超出範圍必須拒絕'
Reject {Select-CISuiteShard -Cases $cases -ShardIndex -1 -ShardCount 2 -Weights $weights -DefaultWeight 10} '負分片索引必須拒絕'
Reject {Select-CISuiteShard -Cases $cases -ShardIndex 0 -ShardCount 0 -Weights $weights -DefaultWeight 10} '零分片數必須拒絕'
Reject {Select-CISuiteShard -Cases @(@{Name='Unit.a'},@{Name='Unit.a'}) -ShardIndex 0 -ShardCount 2 -Weights @{} -DefaultWeight 10} '重複 suite 名稱必須拒絕以免靜默漏跑'
Reject {Select-CISuiteShard -Cases @() -ShardIndex 0 -ShardCount 1 -Weights @{} -DefaultWeight 10} '空清單不得回報分片成功'
$file=Join-Path $root 'script/test/ci_suite_weights.json'
Assert (Test-Path -LiteralPath $file -PathType Leaf) '提供實測權重檔'
$table=Get-CISuiteWeights -Path $file
Assert ($table.Count -gt 100 -and $table.ContainsKey('Integration.layout_source_alias') -and $table['Integration.layout_source_alias'] -gt 60) '權重檔含實測的慢 suite'
Reject {Get-CISuiteWeights -Path (Join-Path $root 'script/test/__missing_weights__.json')} '缺少權重檔必須失敗'
$bad=Join-Path $env:TEMP ('ci_weights_'+[guid]::NewGuid().ToString('N')+'.json')
try{[IO.File]::WriteAllText($bad,'{"Unit.x":-1}');Reject {Get-CISuiteWeights -Path $bad} '負權重必須拒絕'}finally{Remove-Item -LiteralPath $bad -Force -ErrorAction SilentlyContinue}
