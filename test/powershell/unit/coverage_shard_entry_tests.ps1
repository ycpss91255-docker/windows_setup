#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/powershell_coverage_shard.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$temp=Join-Path $env:TEMP ('shard_entry_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$source=Join-Path $temp 'source';[void][IO.Directory]::CreateDirectory($source)
$script:calls=@();$script:failAt=0
function Invoke-CINative {param($File,$Arguments) $script:calls+=@([pscustomobject]@{File=$File;Arguments=$Arguments});if($script:failAt -eq $script:calls.Count){throw 'controlled native failure'}}
function Call-Fixture([string]$Name,[string]$Tool=''){
 Invoke-PowerShellCoverageShard -SourceRoot $source -OutputDirectory (Join-Path $temp ($Name+'_public')) -PrivateDirectory (Join-Path $temp ($Name+'_private')) -ShardIndex 0 -ShardCount 2 -Commit ('a'*40) -RunUrl 'https://github.com/example/repo/actions/runs/1' -RunAttempt 2 -CoverageToolPath $Tool
}
Call-Fixture 'compile'
Assert ($script:calls.Count -eq 6 -and $script:calls[0].File -eq 'go.exe' -and $script:calls[0].Arguments[0] -eq 'build') '原生入口使用原始Go工具建置，不要求一般Windows使用者安裝維護依賴'
Assert ($script:calls[2].Arguments -contains 'powershell-shard-plan' -and $script:calls[5].Arguments -contains 'powershell-shard-pack') '完整分片先plan並於量測與安全匯出後pack'
Assert ($script:calls[3].Arguments -contains '-ThrottleLimit' -and $script:calls[4].Arguments -contains 'export-powershell') '原Pester收集器及安全匯出不被替換'
Assert (@($script:calls|Where-Object {$_.Arguments -contains '--run-attempt' -and $_.Arguments -contains '2'}).Count -eq 2) 'plan與pack保留相同attempt身分'
# 八片矩陣：每個索引都能執行完整 plan/measure/pack，超出上限仍拒絕。
foreach($wideIndex in 0..7){
 $script:calls=@();$script:failAt=0
 Invoke-PowerShellCoverageShard -SourceRoot $source -OutputDirectory (Join-Path $temp ('wide_'+$wideIndex+'_public')) -PrivateDirectory (Join-Path $temp ('wide_'+$wideIndex+'_private')) -ShardIndex $wideIndex -ShardCount 8 -Commit ('a'*40) -RunUrl 'https://github.com/example/repo/actions/runs/1' -RunAttempt 2 -CoverageToolPath controlled.exe
 Assert ($script:calls.Count -eq 5 -and @($script:calls|Where-Object {$_.Arguments -contains '--shard-count' -and $_.Arguments -contains '8' -and $_.Arguments -contains $wideIndex.ToString()}).Count -eq 2) ('八片矩陣的分片 '+$wideIndex+' 完整執行並保留相同身分')
}
$script:failAt=0;$script:calls=@();$tooWide=$false
try{Invoke-PowerShellCoverageShard -SourceRoot $source -OutputDirectory (Join-Path $temp 'wide9_public') -PrivateDirectory (Join-Path $temp 'wide9_private') -ShardIndex 0 -ShardCount 9 -Commit ('a'*40) -RunUrl 'https://github.com/example/repo/actions/runs/1' -CoverageToolPath controlled.exe}catch{$tooWide=$true}
Assert ($tooWide -and $script:calls.Count -eq 0) '超過八片的矩陣在執行任何原生階段前被拒絕'
foreach($failure in 1..5){
 $script:calls=@();$script:failAt=$failure;$refused=$false
 try{Call-Fixture ('fail_'+$failure) 'controlled.exe'}catch{$refused=$true}
 Assert ($refused -and $script:calls.Count -eq $failure) ('原生階段失敗立即停止、不執行後續發布：'+$failure)
}
$script:failAt=0
foreach($case in @('source','same','nested','existing','index')){
 $script:calls=@();$out=Join-Path $temp ('bad_'+$case+'_public');$private=Join-Path $temp ('bad_'+$case+'_private');$index=0
 switch($case){source{$out=Join-Path $source 'child'} same{$private=$out} nested{$private=Join-Path $out 'child'} existing{[void][IO.Directory]::CreateDirectory($private)} index{$index=2}}
 $refused=$false
 try{Invoke-PowerShellCoverageShard -SourceRoot $source -OutputDirectory $out -PrivateDirectory $private -ShardIndex $index -ShardCount 2 -Commit ('a'*40) -RunUrl 'https://github.com/example/repo/actions/runs/1' -CoverageToolPath controlled.exe}catch{$refused=$true}
 Assert ($refused -and $script:calls.Count -eq 0) ('來源或私有公開目錄邊界拒絕：'+$case)
}
$global:LASTEXITCODE=0
