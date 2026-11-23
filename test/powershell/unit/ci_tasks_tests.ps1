#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/ci_tasks.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Name}
$oldProgramFiles=$env:ProgramFiles
try{$env:ProgramFiles=Join-Path $env:TEMP ('absent_browser_'+[guid]::NewGuid().ToString('N'));Reject {Invoke-CIReportLayout} '缺少瀏覽器不得略過排版驗證'}finally{$env:ProgramFiles=$oldProgramFiles}
Invoke-CINative -File cmd.exe -Arguments @('/d','/c','exit 0')
Assert $true '原生成功返回保留'
Reject {Invoke-CINative -File cmd.exe -Arguments @('/d','/c','exit 7')} '原生非零返回拒絕'
Reject {Invoke-CINative -File '__missing_ci_executable__.exe'} '不存在的工具不能冒稱成功'
$passing=@{Tests='success';Requirements='success';Docker='success';Payload='success';PowerShellCoverage='success';Coverage='success'}
Assert-CIResults $passing
Assert $true '六個必要工作成功才通過'
foreach($name in @('Tests','Requirements','Docker','Payload','PowerShellCoverage','Coverage')){foreach($state in @('failure','cancelled','skipped','')){$copy=$passing.Clone();$copy[$name]=$state;Reject {Assert-CIResults $copy} ('必要工作拒絕 '+$name+' '+$state)}}
$copy=$passing.Clone();$copy.Remove('PowerShellCoverage');Reject {Assert-CIResults $copy} '完整PowerShell矩陣結果不可遺漏'
$copy=$passing.Clone();$copy.Remove('Payload');Reject {Assert-CIResults $copy} '設定包工作不可遺漏'
$copy=$passing.Clone();$copy.Remove('Coverage');Reject {Assert-CIResults $copy} '完整覆蓋率彙整結果不可遺漏'
$main=Get-CIPortalParameters -Repository 'example/repo' -OutputDirectory 'out' -EventRef 'refs/heads/main' -RunId '42'
Assert ($main.MainRunId -eq '42' -and $main.Repository -eq 'example/repo') 'main明確指定同次執行'
$tag=Get-CIPortalParameters -Repository 'example/repo' -OutputDirectory 'out' -EventRef 'refs/tags/v1.0.0' -RunId '42'
Assert (-not $tag.ContainsKey('MainRunId')) 'tag不得冒用main執行'
function Invoke-CINative {param($File,$Arguments) $script:lastCommand=@($File)+$Arguments;if($script:probeCode -ne 0){$e=[Exception]::new('fixture');$e.Data['ExitCode']=$script:probeCode;throw $e}}
$script:probeCode=0;$script:resolved=@()
function Get-Command {param($Name,$CommandType,$ErrorAction) $script:resolved+=@($Name);[pscustomobject]@{Name=$Name}}
Assert-CIRequiredTools
Assert (($script:resolved -join '|') -eq 'powershell.exe|cmd.exe|git.exe|go.exe' -and ($script:lastCommand -join '|') -eq 'go.exe|version') '必要工具清單與版本命令完整傳遞'
Remove-Item Function:/Get-Command
$script:probeCode=23
Assert-CIDockerFailure -Image 'example:test'
Assert ($script:lastCommand[0] -eq 'docker.exe' -and ($script:lastCommand -contains '--network') -and $script:lastCommand[-1] -eq 'exit 23') '容器退出probe不開啟網路'
foreach($code in @(0,1,24)){$script:probeCode=$code;Reject {Assert-CIDockerFailure -Image 'example:test'} ('真實返回碼必須23 '+$code)}
function Invoke-CINative {throw 'missing executable'}
Reject {Assert-CIDockerFailure -Image 'example:test'} '未啟動Docker不得當成正確失敗'
$temp=Join-Path $env:TEMP ('ci_tasks_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
try{
 [IO.File]::WriteAllText((Join-Path $temp 'summary.json'),'{"Environment":"Windows container / fixture"}')
 Assert-CIContainerReport $temp
 Assert $true '真container標示可接受'
 [IO.File]::WriteAllText((Join-Path $temp 'summary.json'),'{"Environment":"Windows host"}')
 Reject {Assert-CIContainerReport $temp} 'host報表不可充當container'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
# PR 分類：只有對應選擇值明確為 false 且工作確實 skipped，才視為通過。
$required=@('Tests','Requirements','Docker','Payload','PowerShellCoverage','Coverage')
$allSelected=@{};$noneSelected=@{};$allSkipped=@{Classify='success';DocChecks='success'};$allSuccess=@{Classify='success';DocChecks='success'}
foreach($name in $required){$allSelected[$name]='true';$noneSelected[$name]='false';$allSkipped[$name]='skipped';$allSuccess[$name]='success'}
$allSelected['DocChecks']='false';$noneSelected['DocChecks']='true'
Assert-CIResults (Resolve-CIRollupStates -Results $allSuccess -Selection $allSelected)
Assert $true '完整套件全部成功仍通過'
$docOnlyResults=$allSkipped.Clone();$docOnlyResults['DocChecks']='success'
Assert-CIResults (Resolve-CIRollupStates -Results $docOnlyResults -Selection $noneSelected)
Assert $true '只改文件時重型工作 skipped 且對應選擇為 false 才通過'
Reject {Assert-CIResults (Resolve-CIRollupStates -Results $allSkipped -Selection $allSelected)} '被選中的工作 skipped 不得通過'
foreach($name in $required){
 foreach($value in @('true','','True','FALSE',$null,'unknown')){
  $selection=$noneSelected.Clone();if($null -eq $value){[void]$selection.Remove($name)}else{$selection[$name]=$value}
  Reject {Assert-CIResults (Resolve-CIRollupStates -Results $docOnlyResults -Selection $selection)} ($name+' 選擇值不是明確 false（'+$value+'）時 skipped 不得通過')
 }
 foreach($state in @('failure','cancelled')){
  $results=$docOnlyResults.Clone();$results[$name]=$state
  Reject {Assert-CIResults (Resolve-CIRollupStates -Results $results -Selection $noneSelected)} ($name+' 失敗或取消即使選擇為 false 也不得通過')
 }
}
$badDoc=$docOnlyResults.Clone();$badDoc['DocChecks']='failure'
Reject {Assert-CIResults (Resolve-CIRollupStates -Results $badDoc -Selection $noneSelected)} '被選中的文件檢查失敗不得通過'
$skippedDoc=$docOnlyResults.Clone();$skippedDoc['DocChecks']='skipped'
Reject {Assert-CIResults (Resolve-CIRollupStates -Results $skippedDoc -Selection $noneSelected)} '被選中的文件檢查 skipped 不得通過'
$notNeeded=$allSuccess.Clone();$notNeeded['DocChecks']='skipped'
Assert-CIResults (Resolve-CIRollupStates -Results $notNeeded -Selection $allSelected)
Assert $true '完整套件時文件檢查依分類不執行仍通過'
foreach($state in @('failure','cancelled','skipped','')){
 $badClassify=$docOnlyResults.Clone();$badClassify['Classify']=$state
 Reject {Assert-CIResults (Resolve-CIRollupStates -Results $badClassify -Selection $noneSelected)} ('分類工作未成功（'+$state+'）時不採信任何跳過')
}
$missingClassify=$docOnlyResults.Clone();[void]$missingClassify.Remove('Classify')
Reject {Assert-CIResults (Resolve-CIRollupStates -Results $missingClassify -Selection $noneSelected)} '缺少分類結果不採信任何跳過'
# 程式碼 PR 只選受影響測試：覆蓋率、聚合、需求驗收與容器依分類略過。
$scopedSelection=$allSelected.Clone()
foreach($name in @('Requirements','Docker','PowerShellCoverage','Coverage')){$scopedSelection[$name]='false'}
$scopedResults=$allSuccess.Clone()
foreach($name in @('Requirements','Docker','PowerShellCoverage','Coverage')){$scopedResults[$name]='skipped'}
$scopedResults['DocChecks']='skipped'
Assert-CIResults (Resolve-CIRollupStates -Results $scopedResults -Selection $scopedSelection -EventName pull_request)
Assert $true '程式碼 PR 縮小範圍時，依分類略過的重型工作計為通過'
foreach($state in @('failure','cancelled','skipped')){
 $badTests=$scopedResults.Clone();$badTests['Tests']=$state
 Reject {Assert-CIResults (Resolve-CIRollupStates -Results $badTests -Selection $scopedSelection -EventName pull_request)} ('縮小範圍時被選中的受影響測試 '+$state+' 不得通過')
 $badPayload=$scopedResults.Clone();$badPayload['Payload']=$state
 Reject {Assert-CIResults (Resolve-CIRollupStates -Results $badPayload -Selection $scopedSelection -EventName pull_request)} ('縮小範圍時被選中的設定包驗證 '+$state+' 不得通過')
}
foreach($name in @('Requirements','Docker','PowerShellCoverage','Coverage')){
 foreach($state in @('failure','cancelled')){
  $bad=$scopedResults.Clone();$bad[$name]=$state
  Reject {Assert-CIResults (Resolve-CIRollupStates -Results $bad -Selection $scopedSelection -EventName pull_request)} ($name+' 已執行卻 '+$state+'，即使分類略過也不得通過')
 }
}
# 非 PR 事件不接受任何分類略過，即使分類輸出被竄改為 false。
foreach($event in @('push','merge_group','workflow_dispatch','schedule','release','')){
 foreach($name in $required){
  $results=$allSuccess.Clone();$results[$name]='skipped'
  $selection=$allSelected.Clone();$selection[$name]='false'
  Reject {Assert-CIResults (Resolve-CIRollupStates -Results $results -Selection $selection -EventName $event)} ('非 PR 事件（'+$event+'）的 '+$name+' 略過不得通過')
 }
 Assert-CIResults (Resolve-CIRollupStates -Results $allSuccess -Selection $allSelected -EventName $event)
 Assert $true ('非 PR 事件（'+$event+'）全部成功仍通過')
}
