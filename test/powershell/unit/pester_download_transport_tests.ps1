#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/pester_retry_policy.ps1')
function Assert([bool]$ok,[string]$name){Write-Host ('@@ASSERT@@'+(@{Name=$name;Passed=$ok}|ConvertTo-Json -Compress));if(-not $ok){throw $name}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('pester_retry_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
try {
 $watch=[Diagnostics.Stopwatch]::StartNew();$timeout=$false
 try{Invoke-RunnerBoundedProcess -File (Join-Path $PSHOME 'powershell.exe') -Arguments @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 10') -TimeoutMilliseconds 3000 -InitialHostedProbe $true|Out-Null}catch{$timeout=($_.Exception -is [TimeoutException] -and $_.Exception.Message -ceq 'runner-process-deadline-cleaned')}
 Assert ($timeout -and $watch.ElapsedMilliseconds -lt 5000) 'owned inert child terminated under deadline'
 function Start-Sleep {param($Milliseconds)}
 function Invoke-RunnerBoundedProcess {
  param($File,$Arguments,$TimeoutMilliseconds,$InitialHostedProbe)
  $script:calls++
  $out=$Arguments[-1];[IO.File]::WriteAllText((Join-Path (Split-Path $out) 'unfinished.partial'),'partial')
  if($script:mode -eq '502' -and $script:calls -eq 1){return @{ExitCode=1;Output="PESTER-FAILURE:HTTP 502`r`n"}}
  if($script:mode -eq 'persistent'){return @{ExitCode=1;Output="PESTER-FAILURE:HTTP 502`r`n"}}
  if($script:mode -eq '404'){return @{ExitCode=1;Output="PESTER-FAILURE:HTTP 404`r`n"}}
  [IO.File]::WriteAllText($out,'fixture');return @{ExitCode=0;Output=''}
 }
 foreach($mode in @('502','persistent','404')){
  $script:mode=$mode;$script:calls=0;$target=Join-Path $fixture ($mode+'.download');$failed=$false;$message=''
  try{Invoke-PesterBoundedDownload -OutFile $target}catch{$failed=$true;$message=$_.Exception.Message}
  $expected=if($mode -eq '502'){2}elseif($mode -eq 'persistent'){3}else{1}
  Assert ($script:calls -eq $expected -and $failed -eq ($mode -ne '502')) ('retry classification '+$mode)
  Assert ((Test-Path -LiteralPath $target) -eq ($mode -eq '502') -and @(Get-ChildItem -LiteralPath $fixture -Directory).Count -eq 0) ('owned staging cleanup '+$mode)
  if($failed){Assert ($message -ceq ('Pester download failed: HTTP '+$(if($mode -eq '404'){'404'}else{'502'}))) ('last failure retained '+$mode)}
 }
} finally {if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}}
