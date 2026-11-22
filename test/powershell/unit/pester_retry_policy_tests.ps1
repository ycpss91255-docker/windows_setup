#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/pester_retry_policy.ps1')
function Assert([bool]$ok,[string]$name){Write-Host ('@@ASSERT@@'+(@{Name=$name;Passed=$ok}|ConvertTo-Json -Compress));if(-not $ok){throw $name}}
class RetryResponse : System.Net.WebResponse { [int]$StatusCode; RetryResponse([int]$n){$this.StatusCode=$n} }
foreach($case in @('502-success','502-persistent','404','429','timeout','budget')){
 $script:now=0;$script:calls=0;$script:timeouts=@();$script:sleeps=@()
 $clock={return $script:now};$pause={param($ms) $script:sleeps+=@($ms);$script:now+=$ms}
 $transport={param($ms) $script:calls++;$script:timeouts+=@($ms);if($case -eq 'budget'){$script:now+=$ms;throw [Net.WebException]::new('timeout',$null,[Net.WebExceptionStatus]::Timeout,$null)};if($case -eq 'timeout' -and $script:calls -eq 1){throw [Net.WebException]::new('timeout',$null,[Net.WebExceptionStatus]::Timeout,$null)};$status=switch($case){'502-success'{if($script:calls -eq 1){502}else{0}} '502-persistent'{502} '404'{404} '429'{if($script:calls -eq 1){429}else{0}} default{0}};if($status){throw [Net.WebException]::new('fixture',$null,[Net.WebExceptionStatus]::ProtocolError,[RetryResponse]::new($status))};return 'ok'}
 $result='';try{$result=Invoke-PesterRetryPolicy -Transport $transport -Clock $clock -Pause $pause -AttemptMilliseconds 1000 -TotalMilliseconds 2500}catch{}
 $expected=switch($case){'502-success'{2} '502-persistent'{2} '404'{1} '429'{2} 'timeout'{2} 'budget'{2}}
 Assert ($script:calls -eq $expected) ('bounded attempts '+$case)
 Assert (($result -ceq 'ok') -eq ($case -in @('502-success','429','timeout'))) ('only transient failure retries '+$case)
 Assert ($script:now -le 2500 -and @($script:timeouts|Where-Object {$_ -lt 1 -or $_ -gt 1000}).Count -eq 0) ('bounded clock and request allowance '+$case)
}
