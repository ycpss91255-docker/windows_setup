#Requires -Version 5.1
param([ValidateSet('All','Unit','Integration')][string]$Layer='All',[string]$ReportDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('NUC-CI-'+[guid]::NewGuid().ToString('N'))),[ValidateRange(1,4)][int]$Parallelism=1,[string[]]$Suite=@(),[int]$ShardIndex=0,[int]$ShardCount=1)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ci_runner_library.ps1')
$suiteArguments=@{};if($PSBoundParameters.ContainsKey('Suite')){$suiteArguments['Suite']=$Suite}
foreach($name in @('ShardIndex','ShardCount')){if($PSBoundParameters.ContainsKey($name)){$suiteArguments[$name]=$PSBoundParameters[$name]}}
Invoke-SetupCI -PackageRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) -ReportDirectory $ReportDirectory -Layer $Layer -Parallelism $Parallelism @suiteArguments
