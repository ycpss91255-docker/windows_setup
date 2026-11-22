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
$disable=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Disable-SetupHibernate'},$true))
Assert ($disable.Count -eq 1) '套用時停用休眠一次'
$prerequisites=Get-Content (Join-Path $root 'core/test_setup_prerequisites.ps1') -Raw
Assert ($prerequisites.Contains("'power_library.ps1'")) '工具包完整性檢查包含電源函式庫'
Write-Host 'ALL PASS: power module wiring'
