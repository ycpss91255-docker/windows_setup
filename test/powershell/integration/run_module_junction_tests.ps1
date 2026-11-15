$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../helpers/run_module_fixture.ps1')
$base=Join-Path $env:TEMP ('issue289_'+[guid]::NewGuid().ToString('N'))
$target=Join-Path $base 'target'; [void][IO.Directory]::CreateDirectory((Join-Path $target 'source/core'))
[IO.File]::WriteAllText((Join-Path $target 'sample.txt'),'data')
[IO.File]::WriteAllText((Join-Path $target 'source/core/run_module.ps1'),'# data only')
$link=Join-Path $base 'link'; New-Item -ItemType Junction -Path $link -Target $target | Out-Null
Assert-RunModuleSafePath $target
Assert-RunModuleSafePath (Join-Path $target 'sample.txt')
Write-Output 'PASS: ordinary directory and file accepted'
$failed=@()
try { Assert-RunModuleSafePath (Join-Path $link 'sample.txt'); $failed+='file through junction accepted' } catch { Write-Output 'PASS: file through junction rejected' }
try { New-RunModuleFixture -SourceRoot (Join-Path $link 'source') | Out-Null; $failed+='source through junction accepted' } catch { Write-Output 'PASS: source through junction rejected' }
if($failed.Count){$failed | ForEach-Object { Write-Output "FAIL: $_" }; exit 1}
Write-Output 'ALL PASS: junction ancestor guard'
