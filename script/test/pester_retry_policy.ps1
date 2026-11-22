#Requires -Version 5.1
# The transport MUST stop all work and return or throw within its supplied millisecond
# allowance. This function cannot cancel a blocked transport; it is not yet a downloader.
. (Join-Path $PSScriptRoot '../docker/download_library.ps1')
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
   if($attempt -eq 3 -or -not (Test-ContainerTransientDownload -Exception $_.Exception)){throw}
   $remaining=$TotalMilliseconds-([long](& $Clock)-$start)
   $delay=1000*$attempt
   if($remaining -le $delay){throw 'Pester download budget exceeded.'}
   & $Pause $delay
  }
 }
}
