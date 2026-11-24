#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$parent=Join-Path $env:TEMP ('issue410_superseded_'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $parent|Out-Null
$oldSha='b'*40;$newSha='a'*40
function gh {
 $a=@($args);$global:LASTEXITCODE=0
 if($a[0] -ceq 'api' -and $a -contains '--paginate'){return}
 if($a[0] -ceq 'api' -and $a[1] -like '*/commits/main'){return $newSha}
 if($a[0] -ceq 'api' -and $a[1] -like '*/compare/*'){
  if($global:compareMode -eq 'error'){$global:LASTEXITCODE=1;return}
  if($a[1] -notlike ('*/compare/'+$oldSha+'...'+$newSha)){throw ('unexpected compare range '+$a[1])}
  return (@{status=$global:compareMode;behind_by=$global:behindBy}|ConvertTo-Json -Compress)
 }
 if($a[0] -ceq 'api' -and $a[1] -like '*/actions/runs/42'){return (@{id=42;head_sha=$oldSha;head_branch=$global:runBranch;event=$global:runEvent;run_attempt=$global:runAttempt}|ConvertTo-Json -Compress)}
 throw ('unexpected mock gh request '+($a -join ' '))
}
function Invoke-Inputs([string]$name){
 $global:LASTEXITCODE=0
 try{$result=& (Join-Path $root 'script/report/get_portal_inputs.ps1') -Repository example/repo -OutputDirectory (Join-Path $parent $name) -MainRunId 42 -ExpectedMainEvent push -ExpectedMainAttempt 1;return @{Result=$result;Error=$null}}catch{return @{Result=$null;Error=$_.Exception.Message}}
}
function Reset-Mock {$global:compareMode='ahead';$global:behindBy=0;$global:runBranch='main';$global:runEvent='push';$global:runAttempt=1}
function Assert-Case([string]$name,[bool]$ok,[string]$detail){
 if(-not $ok){throw ('superseded main run case failed: '+$name+' '+$detail)}
 Write-Host ('@@ASSERT@@'+(@{Name=$name;Passed=$true}|ConvertTo-Json -Compress))
}
Reset-Mock;$r=Invoke-Inputs 'superseded'
Assert-Case 'main advanced past an ancestor run is skipped' ($null -eq $r.Error -and $r.Result.Superseded -eq $true -and $r.Result.RunSha -ceq $oldSha -and $r.Result.MainSha -ceq $newSha) ([string]$r.Error)
Reset-Mock;$global:compareMode='diverged';$r=Invoke-Inputs 'diverged'
Assert-Case 'diverged run fails with both SHAs' ($r.Error -and $r.Error.Contains($oldSha) -and $r.Error.Contains($newSha)) ([string]$r.Error)
Reset-Mock;$global:compareMode='behind';$global:behindBy=3;$r=Invoke-Inputs 'behind'
Assert-Case 'run newer than main fails' ($r.Error -and $r.Error.Contains($oldSha)) ([string]$r.Error)
Reset-Mock;$global:compareMode='error';$r=Invoke-Inputs 'compareerror'
Assert-Case 'unverifiable ancestry fails closed' ($null -ne $r.Error -and $null -eq $r.Result) ([string]$r.Error)
Reset-Mock;$global:runBranch='feature';$r=Invoke-Inputs 'branch'
Assert-Case 'branch mismatch is reported with values and never skipped' ($r.Error -and $r.Error.Contains('head_branch') -and $r.Error.Contains('feature')) ([string]$r.Error)
Reset-Mock;$global:runEvent='pull_request';$r=Invoke-Inputs 'event'
Assert-Case 'event mismatch is reported with values and never skipped' ($r.Error -and $r.Error.Contains('event') -and $r.Error.Contains('pull_request')) ([string]$r.Error)
Reset-Mock;$global:runAttempt=2;$r=Invoke-Inputs 'attempt'
Assert-Case 'attempt mismatch is reported with values and never skipped' ($r.Error -and $r.Error.Contains('run_attempt')) ([string]$r.Error)
. (Join-Path $root 'script/test/ci_tasks.ps1')
$outFile=Join-Path $parent 'github_output.txt';$summaryFile=Join-Path $parent 'summary.txt'
$stub=Join-Path $parent 'build_stub.ps1'
[IO.File]::WriteAllText($stub,'param($CatalogPath,$MainSnapshotPath,$ContainerSnapshotPath,$OutputDirectory) Set-Content -LiteralPath (Join-Path $env:TEMP "issue410_build_called.txt") -Value $CatalogPath',[Text.UTF8Encoding]::new($false))
$called=Join-Path $env:TEMP 'issue410_build_called.txt';if(Test-Path -LiteralPath $called){Remove-Item -LiteralPath $called -Force}
Invoke-CIPortalBuild -Inputs ([pscustomobject]@{Superseded=$true;RunSha=$oldSha;MainSha=$newSha}) -OutputDirectory (Join-Path $parent 'portal') -OutputPath $outFile -SummaryPath $summaryFile -BuildScript $stub|Out-Null
Assert-Case 'superseded portal records the decision with both SHAs and does not build' ((Get-Content -LiteralPath $outFile -Raw).Trim() -ceq 'superseded=true' -and (Get-Content -LiteralPath $summaryFile -Raw).Contains($oldSha) -and (Get-Content -LiteralPath $summaryFile -Raw).Contains($newSha) -and -not (Test-Path -LiteralPath $called)) ''
Remove-Item -LiteralPath $outFile -Force
Invoke-CIPortalBuild -Inputs ([pscustomobject]@{Superseded=$false;CatalogPath='c';MainSnapshotPath='m';ContainerSnapshotPath='k'}) -OutputDirectory (Join-Path $parent 'portal') -OutputPath $outFile -BuildScript $stub|Out-Null
Assert-Case 'current portal builds and records superseded=false' ((Get-Content -LiteralPath $outFile -Raw).Trim() -ceq 'superseded=false' -and (Get-Content -LiteralPath $called -Raw).Trim() -ceq 'c') ''
function Get-Freshness([string]$ref,[string]$mode){
 $global:compareMode=$mode;$global:behindBy=0;if(Test-Path -LiteralPath $outFile){Remove-Item -LiteralPath $outFile -Force}
 try{Set-CIMainFreshness -Repository example/repo -Ref $ref -RunSha $oldSha -OutputPath $outFile;return @{Error=$null;Output=(Get-Content -LiteralPath $outFile -Raw).Trim()}}catch{return @{Error=$_.Exception.Message;Output=''}}
}
$f=Get-Freshness 'refs/tags/v1.0.0' 'ahead'
Assert-Case 'tag runs are always current' ($null -eq $f.Error -and $f.Output -ceq 'current=true') ([string]$f.Error)
$f=Get-Freshness 'refs/heads/main' 'ahead'
Assert-Case 'main ahead of the run is not current and does not fail' ($null -eq $f.Error -and $f.Output -ceq 'current=false') ([string]$f.Error)
$f=Get-Freshness 'refs/heads/main' 'diverged'
Assert-Case 'main diverged from the run fails with both SHAs' ($f.Error -and $f.Error.Contains($oldSha) -and $f.Error.Contains($newSha)) ([string]$f.Error)
$f=Get-Freshness 'refs/heads/main' 'error'
Assert-Case 'unverifiable freshness fails closed' ($null -ne $f.Error) ''
$newSha2=$newSha
$oldSha,$newSha=$newSha,$newSha
$f=Get-Freshness 'refs/heads/main' 'ahead'
Assert-Case 'run equal to main is current' ($null -eq $f.Error -and $f.Output -ceq 'current=true') ([string]$f.Error)
Remove-Item Function:\gh
Remove-Item -LiteralPath $parent -Recurse -Force
