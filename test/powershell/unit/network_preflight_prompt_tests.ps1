#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/network_preflight_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$script:states=@();$script:answers=@();$script:prompts=0;$script:reads=0
function Get-SetupNetworkObservation {$script:reads++;$s=if($script:states.Count -ge $script:reads){$script:states[$script:reads-1]}else{$script:states[-1]};[pscustomobject]@{Status=$s}}
function Read-Host {param($Prompt);$script:prompts++;if($script:answers.Count -lt $script:prompts){throw '不應再詢問'};$a=$script:answers[$script:prompts-1];if($a -is [scriptblock]){return (& $a)};return $a}
function Run([string[]]$States,[object[]]$Answers,[bool]$Interactive=$true){$script:states=$States;$script:answers=$Answers;$script:prompts=0;$script:reads=0;$out=@(Show-SetupNetworkPreflight -Interactive:$Interactive 6>&1|ForEach-Object{[string]$_});$out}
# 四種狀態的畫面文字
$o=Run @('Internet') @() $true;$t=$o -join "`n"
Assert ($o.Count -eq 1 -and $t -match '已連線' -and $t -match '繼續') '有網路只顯示一行白話'
Assert ($script:prompts -eq 0) '有網路不呼叫 Read-Host'
Assert ($t -notmatch 'SSH' -and $t -notmatch '一定') '有網路不宣稱 SSH 或來源一定可用'
foreach($case in @(@{s='Local';m='區域網路'},@{s='Offline';m='沒有偵測到'},@{s='Unknown';m='無法判斷'})){
 $o=Run @($case.s) @('') $true;$t=$o -join "`n"
 Assert ($t -match $case.m) ('顯示現況 '+$case.s)
 Assert ($t -match 'Windows 更新' -and $t -match 'OpenSSH' -and $t -match '其他設定' -and $t -match '繼續') ('說明影響與可繼續 '+$case.s)
 Assert ($o.Count -le 4) ('提示行數精簡 '+$case.s)
 Assert ($t -notmatch '0x8024402C' -and $t -notmatch 'DNS' -and $t -notmatch '\.cmd') ('不夾帶疑難排解 '+$case.s)
}
$t=(Run @('Unknown') @('') $true) -join "`n";Assert ($t -notmatch '已連線' -and $t -notmatch '離線' -and $t -notmatch '沒有偵測到') '未知如實寫無法判斷'
$script:promptText='';function Read-Host {param($Prompt);$script:promptText=$Prompt;$script:prompts++;return ''}
[void](Run @('Offline') @('') $true);Assert ($script:promptText -match 'R' -and $script:promptText -match '重新檢查' -and $script:promptText -match 'Enter' -and $script:promptText -match '不接網路') '提示說明 R 與 Enter 的意思'
function Read-Host {param($Prompt);$script:prompts++;if($script:answers.Count -lt $script:prompts){throw '不應再詢問'};$a=$script:answers[$script:prompts-1];if($a -is [scriptblock]){return (& $a)};return $a}
# R 流程
$o=Run @('Offline','Internet') @('R') $true;Assert ($script:prompts -eq 1 -and $script:reads -eq 2 -and ($o -join "`n") -match '已連線') 'R 重檢後連上就直接繼續'
$o=Run @('Offline','Internet') @('r') $true;Assert ($script:reads -eq 2 -and $script:prompts -eq 1) 'R 不分大小寫'
$o=Run @('Offline','Local','Internet') @('R','R') $true;Assert ($script:prompts -eq 2 -and $script:reads -eq 3) 'R 可重複檢查直到連上'
$o=Run @('Offline','Offline') @('R','') $true;Assert ($script:prompts -eq 2 -and $script:reads -eq 2) 'R 後仍離線再按 Enter 繼續'
$o=Run @('Local') @('x','') $true;Assert ($script:prompts -eq 2 -and $script:reads -eq 1 -and ($o -join "`n") -match '請輸入 R') '無效輸入重新詢問並說明'
$o=Run @('Local','Internet') @('go','R') $true;Assert ($script:prompts -eq 2 -and $script:reads -eq 2) '無效輸入後仍可用 R 重檢'
$o=Run @('Offline') @({throw 'stdin'}) $true;Assert ($script:prompts -eq 1 -and $script:reads -eq 1) '讀取輸入丟例外照常繼續'
$o=Run @('Offline') @($null) $true;Assert ($script:prompts -eq 1) '讀取到空值視為繼續'
# 非互動
$o=Run @('Offline') @() $false;Assert ($script:prompts -eq 0 -and $script:reads -eq 1 -and ($o -join "`n") -match '沒有偵測到') '非互動只顯示不詢問'
