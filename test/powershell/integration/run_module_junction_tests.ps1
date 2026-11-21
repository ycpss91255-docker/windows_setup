$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../helpers/run_module_fixture.ps1')
$base=Join-Path $env:TEMP ('issue289_'+[guid]::NewGuid().ToString('N'))
$target=Join-Path $base 'target'; [void][IO.Directory]::CreateDirectory((Join-Path $target 'source/core'))
[IO.File]::WriteAllText((Join-Path $target 'sample.txt'),'data')
[IO.File]::WriteAllText((Join-Path $target 'source/core/run_module.ps1'),'# data only')
$link=Join-Path $base 'link'; New-Item -ItemType Junction -Path $link -Target $target | Out-Null
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
Assert-RunModuleSafePath $target
Assert $true '普通目錄通過路徑檢查'
Assert-RunModuleSafePath (Join-Path $target 'sample.txt')
Assert $true '普通檔案通過路徑檢查'
$rejected=$false
try { Assert-RunModuleSafePath (Join-Path $link 'sample.txt') } catch { if($_.Exception.Message -cne 'reparse point in fixture path'){throw}; $rejected=$true }
Assert $rejected '拒絕檔案祖先的 junction'
$rejected=$false
try { New-RunModuleFixture -SourceRoot (Join-Path $link 'source') | Out-Null } catch { if($_.Exception.Message -cne 'reparse point in fixture path'){throw}; $rejected=$true }
Assert $rejected '拒絕資料來源祖先的 junction'
