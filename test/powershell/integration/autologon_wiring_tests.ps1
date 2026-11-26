#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/paths.ps1')
$entry=Resolve-NucPath 'Apply-AutologonSettings.ps1'
Assert (Test-Path $entry) '自動登入獨立入口可解析'
Assert ((Get-Command $entry).Parameters.ContainsKey('Restore')) '獨立入口具停用還原參數'
$library=Resolve-NucPath 'autologon_library.ps1'
Assert ((Test-Path $library) -and [IO.Path]::GetFullPath($library) -eq [IO.Path]::GetFullPath((Join-Path $root 'modules/accounts/autologon_library.ps1'))) '自動登入函式庫由路徑對照解析'
$prerequisites=[IO.File]::ReadAllText((Join-Path $root 'core/test_setup_prerequisites.ps1'))
Assert ($prerequisites.Contains("'autologon_library.ps1'")) '前置檢查要求自動登入函式庫'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0) '獨立入口可由PowerShell 5.1解析'
$restoreBranch=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$Restore'},$true))
$prompt=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in @('Read-Host','Get-AuthenticodeSignature','Start-Process','Get-LocalUser')},$true))
Assert ($restoreBranch.Count -eq 1 -and $prompt.Count -gt 0) '入口有唯一停用分支'
$body=$restoreBranch[0].Clauses[0].Item2
Assert ($body.Extent.Text.Contains('Invoke-CurrentUserAutologonRestore') -and @($body.FindAll({param($n) $n -is [Management.Automation.Language.ReturnStatementAst]},$true)).Count -eq 1) '停用分支呼叫還原後結束'
Assert (@($prompt|Where-Object {$_.Extent.StartOffset -lt $restoreBranch[0].Extent.StartOffset}).Count -eq 0) '停用不詢問密碼、不檢查帳號也不執行Autologon'
. $library
$script:received=$null
function Invoke-SetupAutologonRestore {param($ReportPath,$UserSid,$Computer) $script:received=$PSBoundParameters}
Invoke-CurrentUserAutologonRestore
Assert ($script:received.UserSid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) '目前身分動態取得並傳遞'
Assert ($script:received.ReportPath -eq (Join-Path $env:ProgramData 'NUC8-Setup\Autologon-Result.json')) '結果使用目前機器ProgramData'
Write-Host 'ALL PASS: Autologon restore routing without host writes'
