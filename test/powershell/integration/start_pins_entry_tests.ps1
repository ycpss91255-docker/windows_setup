#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Parse($File){$t=$null;$e=$null;[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $File),[ref]$t,[ref]$e)}
. (Join-Path $repo 'test/powershell/helpers/run_module_fixture.ps1')
$ast=Parse 'core/run_module.ps1'
Assert ($ast.ParamBlock.Parameters.Name.VariablePath.UserPath -contains 'ApplyPolicy') 'standalone accepts explicit policy confirmation mode'
$runFixture=New-RunModuleFixture -SourceRoot $repo
$arguments=@{Module='Apply-StartMenuSettings';ApplyPolicy=$true;NonInteractive=$true}
Invoke-RunModuleFixture $runFixture $arguments
$r=Read-RunModuleCapturedCommand $runFixture
Assert ($r.ApplyPolicy -and $r.NonInteractive) 'real UAC command preserves explicit apply and noninteractive'
Invoke-RunModuleFixture $runFixture $arguments -Admin $true
$r=Get-Content (Join-Path $runFixture.Root 'dummy.json') -Raw|ConvertFrom-Json
Assert ($r.ApplyPolicy.IsPresent -and $r.NonInteractive.IsPresent) 'real direct dispatch preserves Start flags'
$arguments.VerifyOnly=$true;Invoke-RunModuleFixture $runFixture $arguments -Admin $true
$r=Get-Content (Join-Path $runFixture.Root 'dummy.json') -Raw|ConvertFrom-Json
Assert ($r.VerifyOnly.IsPresent -and -not $r.ApplyPolicy.IsPresent) 'verification dispatch never forwards policy installation'
$fixture=$runFixture.Root;$NonInteractive=$true
$start=Parse 'core/start_windows.ps1';$request=[pscustomobject]@{DriverPackagePath='';ConfirmedBoard='';ConfirmationComputer=''}
$call=$start.FindAll({param($a) $a -is [Management.Automation.Language.CommandAst] -and $a.Extent.Text -like '*-DriverPackagePath $request.DriverPackagePath*'},$true)|Select-Object -Last 1
$fake=Join-Path $fixture 'configure.ps1';[IO.File]::WriteAllText($fake,'param($DriverPackagePath,$ConfirmedBoard,$ConfirmationComputer,[switch]$NonInteractive);$NonInteractive.IsPresent');$entry='configure.ps1'
$r=& ([scriptblock]::Create($call.Extent.Text.Replace('$PSScriptRoot','$fixture')))
Assert $r 'Windows entry forwards noninteractive to late policy gate'
. (Join-Path $repo 'core/paths.ps1')
foreach($name in @('start_pins_policy_library.ps1','start_pins_asset_library.ps1')){Assert (Test-Path -LiteralPath (Resolve-NucPath $name)) ('runtime dependency resolves '+$name)}
$pre=[IO.File]::ReadAllText((Join-Path $repo 'core/test_setup_prerequisites.ps1'))
Assert ($pre.Contains('Assert-StartPinsAssetSource')) 'offline preflight checks actual Start asset source without client native API'
