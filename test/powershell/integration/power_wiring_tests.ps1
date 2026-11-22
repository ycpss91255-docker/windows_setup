#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/paths.ps1')
$entry=Resolve-NucPath 'Apply-PowerSettings.ps1'
Assert (Test-Path $entry) '電源獨立入口可解析'
Assert ((Resolve-NucPath 'power_library.ps1') -eq (Join-Path $root 'modules/power/power_library.ps1')) '電源函式庫列入工具包路徑'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0) '電源入口可由 Windows PowerShell 解析'
$sources=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.InvocationOperator -eq 'Dot' -and $n.Extent.Text.Contains('power_library.ps1')},$true))
Assert ($sources.Count -eq 1) '電源入口載入函式庫一次'
$command=Get-Command $entry
Assert ($command.Parameters.ContainsKey('VerifyOnly') -and $command.Parameters.ContainsKey('VerificationRunId')) '獨立入口具只讀驗證與本輪識別'
$results=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-SetupHibernateResult'},$true))
$verify=@($results|Where-Object {$_.Extent.Text -match '-VerifyOnly\b'})
Assert ($results.Count -eq 2 -and $verify.Count -eq 1) '套用與只讀驗證各寫一次休眠結果'
$disable=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Disable-SetupHibernate'},$true))
Assert ($disable.Count -eq 0) '套用時經結果函式停用休眠一次，不另外直接呼叫'
$powercfg=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'powercfg.exe'},$true))
$guard=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$VerifyOnly' -and $n.Extent.Text.Contains('return')},$false))
Assert ($guard.Count -eq 1 -and $guard[0].Extent.Text.Contains($verify[0].Extent.Text) -and @($powercfg|Where-Object {$_.Extent.StartOffset -lt $guard[0].Extent.StartOffset}).Count -eq 0) '只讀驗證在任何 powercfg 寫入前結束'
$report=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Join-Path' -and $n.Extent.Text.Contains('NUC8-Setup') -and $n.Extent.Text.Contains('Power-Result.json')},$true))
Assert ($report.Count -eq 1 -and $report[0].Extent.Text.Contains('$env:ProgramData')) '休眠結果寫入目前電腦 ProgramData'
$prerequisites=Get-Content (Join-Path $root 'core/test_setup_prerequisites.ps1') -Raw
Assert ($prerequisites.Contains("'power_library.ps1'")) '工具包完整性檢查包含電源函式庫'
Write-Host 'ALL PASS: power module wiring'
