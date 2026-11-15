#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$mapping=Get-Content -LiteralPath (Join-Path $root 'core/paths.json') -Raw|ConvertFrom-Json
foreach($case in @(@{Role='Desktop';Entry='apply_desktop_settings.ps1';Leaf='desktop_settings_library.ps1'},@{Role='Icons';Entry='desktop_icon_layout.ps1';Leaf='icons_settings_library.ps1'})){
 $path=Join-Path $root ('modules/desktop/'+$case.Entry);$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
 $command=if($case.Role -eq 'Icons'){'Invoke-SetupGuiPublicDispatch'}else{'Invoke-SetupGuiRole'}
 $calls=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $command},$true))
 Assert ($errors.Count -eq 0 -and $calls.Count -eq 1 -and $calls[0].Extent.Text.Contains('-Role '+$case.Role) -and $calls[0].Extent.Text.Contains('-Worker:$Worker')) ('public '+$case.Role+' entry uses only approved private role with Worker identity contract')
 Assert ([IO.File]::ReadAllText($path) -notmatch 'Copy-Item|New-ScheduledTask|NUC8-Setup|Set-Content') ('public '+$case.Role+' removes old public stage and result authority')
 Assert ($mapping.($case.Leaf) -ceq ('modules/desktop/'+$case.Leaf) -and [IO.File]::ReadAllText((Join-Path $root 'core/test_setup_prerequisites.ps1')).Contains("'"+$case.Leaf+"'")) ('portable preflight requires '+$case.Leaf)
}
$tokens=$null;$errors=$null
$library=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/gui_stage_library.ps1'),[ref]$tokens,[ref]$errors)
$dispatch=$library.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-SetupGuiPublicDispatch'},$true)
$forward=@($dispatch.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-SetupGuiRole' -and $n.Extent.Text.Contains('-IconMode $IconMode')},$true))
Assert ($errors.Count -eq 0 -and $forward.Count -eq 1 -and $forward[0].Extent.Text.Contains('-Role $Role') -and $forward[0].Extent.Text.Contains('-Worker:$Worker') -and $forward[0].Extent.Text.Contains('-VerifyOnly:$VerifyOnly') -and $forward[0].Extent.Text.Contains('-VerificationRunId $VerificationRunId')) 'Icons named dispatch forwards its mode and identity to the fixed controller'
$tokens=$null;$errors=$null;$aggregate=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/verification_library.ps1'),[ref]$tokens,[ref]$errors)
$fresh=@($aggregate.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-SetupGuiFreshVerification' -and $n.Extent.Text.Contains('-Role Icons')},$true))
Assert ($fresh.Count -eq 1) 'core Icons acceptance consumes current private result directly'
Assert ([IO.File]::ReadAllText((Join-Path $root 'core/verification_library.ps1')) -notmatch 'NUC8-Setup\\IconLayout-Result.json') 'core Icons never trusts old public result path'