#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'script/test/powershell_coverage.ps1'),[ref]$tokens,[ref]$errors)
$getter=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-PinnedPester'},$true))
if($errors.Count -or $getter.Count -ne 1){throw 'collector structure is invalid'}
$calls=@($getter[0].FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-PesterBoundedDownload'},$true))
if($calls.Count -ne 1){throw 'Pester collector must use bounded official download helper'}
Write-Output 'PASS: Pester collector uses official download helper'
