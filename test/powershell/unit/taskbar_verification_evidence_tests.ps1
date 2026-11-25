#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/verification_library.ps1')
function Assert([bool]$v,[string]$n){Write-Host ('@@ASSERT@@'+(@{Name=$n;Passed=$v}|ConvertTo-Json -Compress));if(-not $v){throw $n}}
function Add-Check([string]$Name,[bool]$Passed,[string]$Detail){$script:checks+=@([pscustomobject]@{Name=$Name;Passed=$Passed;Detail=$Detail})}
function Invoke-SetupGuiFreshVerification {param($PackageRoot,$Role) if($script:readFailure){throw 'fixture'};return $script:result}
foreach($case in @('Pending','Cleared','ReadFailure')){
 $script:checks=@();$script:readFailure=($case -eq 'ReadFailure')
 $script:result=[pscustomobject]@{Configured=$true;BindingMatches=$true;Success=($case -eq 'Cleared');RequiresNextSignIn=($case -eq 'Pending');Status=$(if($case -eq 'Pending'){'PendingSignIn'}else{'Confirmed'})}
 Add-SetupTaskbarVerificationChecks -PackageRoot 'fixture'
 Assert ($script:checks.Count -eq 2 -and @($script:checks|Where-Object Name -eq '釘選登入後套用').Count -eq 0) ('不聲稱實際釘選 '+$case)
 Assert (($script:checks.Detail -join ' ') -match '畫面.*未知') ('畫面未觀察明示未知 '+$case)
 if($case -eq 'Pending'){Assert (-not $script:checks[1].Passed) '尚待處理不稱清除'}
 if($case -eq 'Cleared'){Assert ($script:checks[1].Passed -and $script:checks[1].Detail -match '不證明.*登入') '無待處理不推斷已登入'}
 if($case -eq 'ReadFailure'){Assert (-not $script:checks[0].Passed -and -not $script:checks[1].Passed) '讀取失敗不視為通過'}
}
