#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$scene=Join-Path $root 'test/powershell/fixtures/nuc_scene_autologon'
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('autologon_apply_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
# The shipped entry refuses non-administrators, so run its own text without that single line; every OS boundary is faked below.
$entry=Join-Path $dir 'apply_autologon_settings.ps1'
$text=[IO.File]::ReadAllText((Join-Path $root 'modules/accounts/apply_autologon_settings.ps1'))
$elevation='#Requires -RunAs'+'Administrator'
Assert (([regex]::Matches($text,[regex]::Escape($elevation))).Count -eq 1) '套用入口仍要求系統管理員'
[IO.File]::WriteAllText($entry,$text.Replace($elevation,''),(New-Object Text.UTF8Encoding($true)))
Copy-Item -LiteralPath (Join-Path $root 'modules/accounts/autologon_library.ps1') -Destination $dir
$global:ApplyCase=@{};$global:ApplyCase.exitCode=0;$global:ApplyCase.started=0;$global:ApplyCase.auto='1';$global:ApplyCase.signature='Valid';$global:ApplyCase.during=$null
function Get-LocalUser {param($Name,$ErrorAction) [pscustomobject]@{Name=$Name}}
function Get-AuthenticodeSignature {param($FilePath) [pscustomobject]@{Status=$global:ApplyCase.signature;SignerCertificate=[pscustomobject]@{Subject='O=Microsoft Corporation'}}}
function Start-Process {param($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru) $global:ApplyCase.started++;$global:ApplyCase.during=[IO.File]::ReadAllText($report)|ConvertFrom-Json;[pscustomobject]@{ExitCode=$global:ApplyCase.exitCode}}
function Get-ItemProperty {param($Path) [pscustomobject]@{AutoAdminLogon=$global:ApplyCase.auto;DefaultUserName=$env:USERNAME}}
$savedData=$env:ProgramData
try{
 $env:ProgramData=$dir;$report=Join-Path $dir 'NUC8-Setup\Autologon-Result.json';[void][IO.Directory]::CreateDirectory((Split-Path $report))
 $captured=[IO.File]::ReadAllText((Join-Path $scene 'stage_after_restore_report.json'))
 function Reset-Case {[IO.File]::WriteAllText($report,$captured,(New-Object Text.UTF8Encoding($true)));$global:ApplyCase.exitCode=0;$global:ApplyCase.started=0;$global:ApplyCase.auto='1';$global:ApplyCase.signature='Valid';$global:ApplyCase.during=$null}
 function Invoke-Case {$failure='';try{& $entry -UserName $env:USERNAME -AutoLogonPassword 'fixture-apply-secret'|Out-Null}catch{$failure=$_.Exception.Message};$raw=[IO.File]::ReadAllText($report);[pscustomobject]@{Failure=$failure;Raw=$raw;Report=($raw|ConvertFrom-Json)}}
 Reset-Case;$case=Invoke-Case
 Assert ($case.Failure -eq '' -and $global:ApplyCase.started -eq 1) '實機停用後重新套用可完成'
 Assert ($case.Report.Mode -ceq 'Apply' -and $case.Report.Success -eq $true) ('重新啟用後結果檔不再是最後一次停用；Mode='+$case.Report.Mode)
 Assert ($case.Report.UserSID -ceq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -and $case.Report.Computer -ceq $env:COMPUTERNAME) '套用結果記錄目前身分與電腦'
 Assert (-not $case.Raw.Contains('fixture-apply-secret')) '套用結果不含密碼'
 Assert ($global:ApplyCase.during.Mode -ceq 'Apply' -and $global:ApplyCase.during.Success -eq $false) '執行Autologon前已使舊停用結果失效'
 Reset-Case;$global:ApplyCase.exitCode=5;$case=Invoke-Case
 Assert ($case.Failure.Contains('Autologon 結束代碼') -and $case.Report.Mode -ceq 'Apply' -and $case.Report.Success -eq $false) 'Autologon失敗不留下可略過的停用結果'
 Reset-Case;$global:ApplyCase.auto='0';$case=Invoke-Case
 Assert ($case.Failure.Contains('自動登入設定驗證失敗') -and $case.Report.Mode -ceq 'Apply' -and $case.Report.Success -eq $false) '讀回失敗不留下可略過的停用結果'
 Reset-Case;$global:ApplyCase.signature='NotSigned';$case=Invoke-Case
 Assert ($case.Failure.Contains('數位簽章') -and $global:ApplyCase.started -eq 0 -and $case.Raw -ceq $captured) '簽章拒絕時尚未變更任何狀態，保留原停用結果'
}finally{$env:ProgramData=$savedData;Remove-Variable ApplyCase -Scope Global -ErrorAction SilentlyContinue;Microsoft.PowerShell.Management\Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'ALL PASS: Autologon apply result lifecycle; OS boundaries mocked'
