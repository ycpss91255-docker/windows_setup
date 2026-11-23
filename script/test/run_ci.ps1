#Requires -Version 5.1
param([ValidateSet('All','Unit','Integration')][string]$Layer='All',[string]$ReportDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('NUC-CI-'+[guid]::NewGuid().ToString('N'))),[int]$ShardIndex=0,[int]$ShardCount=1,[int]$Parallel=1)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ci_runner_library.ps1')
$extra=@{};foreach($name in @('ShardIndex','ShardCount','Parallel')){if($PSBoundParameters.ContainsKey($name)){$extra[$name]=$PSBoundParameters[$name]}}
Invoke-SetupCI -PackageRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) -ReportDirectory $ReportDirectory -Layer $Layer @extra
