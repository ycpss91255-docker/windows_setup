#Requires -Version 5.1
# The transport MUST stop all work and return or throw within its supplied millisecond
# allowance. This function cannot cancel a blocked transport; it is not yet a downloader.
. (Join-Path $PSScriptRoot '../docker/download_library.ps1')
. (Join-Path $PSScriptRoot '../docker/runner_daemon_library.ps1')
function Invoke-PesterRetryPolicy {
 param([Parameter(Mandatory=$true)][scriptblock]$Transport,[Parameter(Mandatory=$true)][scriptblock]$Clock,[Parameter(Mandatory=$true)][scriptblock]$Pause,[ValidateRange(1,120000)][int]$AttemptMilliseconds=30000,[ValidateRange(1,360000)][int]$TotalMilliseconds=90000)
 $start=[long](& $Clock)
 for($attempt=1;$attempt -le 3;$attempt++){
  $remaining=$TotalMilliseconds-([long](& $Clock)-$start)
  if($remaining -le 0){throw 'Pester download budget exceeded.'}
  $allowance=[int][Math]::Min($AttemptMilliseconds,$remaining)
  try{
   $result=& $Transport $allowance
   if(([long](& $Clock)-$start) -gt $TotalMilliseconds){throw 'Pester download budget exceeded.'}
   return $result
  }catch{
   $kind=$_.Exception.Data['PesterFailureKind']
   $transient=(Test-ContainerTransientDownload -Exception $_.Exception) -or $kind -cmatch '\A(?:Timeout|HTTP (?:408|429|5[0-9][0-9]))\z'
   if($attempt -eq 3 -or -not $transient){throw}
   $remaining=$TotalMilliseconds-([long](& $Clock)-$start)
   $delay=1000*$attempt
   if($remaining -le $delay){throw 'Pester download budget exceeded.'}
   & $Pause $delay
  }
 }
}
function Invoke-PesterBoundedDownload {
 param([Parameter(Mandatory=$true)][string]$OutFile)
 $clock=[Diagnostics.Stopwatch]::StartNew()
 $transport={param($milliseconds)
  $stage=Join-Path ([IO.Path]::GetDirectoryName($OutFile)) ([guid]::NewGuid().ToString('N')+'.pester-stage')
  [void][IO.Directory]::CreateDirectory($stage)
  $temporary=Join-Path $stage 'package.download'
  $safeToCleanup=$false
  try {
   try {
    $result=Invoke-RunnerBoundedProcess -File (Join-Path $PSHOME 'powershell.exe') -Arguments @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'pester_download_worker.ps1'),'-OutFile',$temporary) -TimeoutMilliseconds $milliseconds -InitialHostedProbe $true
   } catch {
    if($_.Exception -is [TimeoutException] -and $_.Exception.Message -ceq 'runner-process-deadline-cleaned'){$safeToCleanup=$true;throw [Net.WebException]::new('Pester download timed out.',$null,[Net.WebExceptionStatus]::Timeout,$null)}
    throw
   }
   $safeToCleanup=$true
   if($result.ExitCode -ne 0){
    $kind='Other';if($result.Output -cmatch '(?m)^PESTER-FAILURE:(Timeout|HTTP [1-5][0-9][0-9]|Other)\r?$'){$kind=$Matches[1]}
    $failure=[Exception]::new('Pester download failed: '+$kind);$failure.Data['PesterFailureKind']=$kind;throw $failure
   }
   if(-not (Test-Path -LiteralPath $temporary -PathType Leaf)){throw 'Pester download produced no file.'}
   [IO.File]::Move($temporary,$OutFile)
  } finally {
   if($safeToCleanup -and (Test-Path -LiteralPath $stage)){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop}
  }
 }
 Invoke-PesterRetryPolicy -Transport $transport -Clock {return $clock.ElapsedMilliseconds} -Pause {param($ms) Start-Sleep -Milliseconds $ms}
}
