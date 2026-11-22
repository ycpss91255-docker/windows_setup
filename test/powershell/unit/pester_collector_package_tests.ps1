#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$ok,[string]$name){Write-Host ('@@ASSERT@@'+(@{Name=$name;Passed=$ok}|ConvertTo-Json -Compress));if(-not $ok){throw $name}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('pester_package_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$oldTemp=$env:TEMP;$oldTmp=$env:TMP;$oldPackage=$env:WINDOWS_SETUP_PESTER_PACKAGE_PATH
try {
 $env:TEMP=$fixture;$env:TMP=$fixture
 $good=Join-Path $fixture 'good.zip';$bad=Join-Path $fixture 'bad.zip'
 [IO.File]::WriteAllText($good,'trusted fixture');[IO.File]::WriteAllText($bad,'bad fixture')
 $packageHash=[Convert]::ToBase64String([Security.Cryptography.SHA512]::Create().ComputeHash([IO.File]::ReadAllBytes($good)))
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'script/test/powershell_coverage.ps1'),[ref]$tokens,[ref]$errors)
 $definition=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-PinnedPester'},$true))[0]
 . ([scriptblock]::Create($definition.Extent.Text))
 function Invoke-PesterBoundedDownload {param($OutFile) $script:calls++;[IO.File]::Copy($script:source,$OutFile)}
 function Expand-Archive {param($LiteralPath,$DestinationPath) $script:expands++;[void][IO.Directory]::CreateDirectory($DestinationPath)}
 $script:calls=0;$script:expands=0;$env:WINDOWS_SETUP_PESTER_PACKAGE_PATH=$good
 $null=Get-PinnedPester
 Assert ($script:calls -eq 0 -and $script:expands -eq 1) 'prepared valid package makes no request'
 foreach($path in @($bad,(Join-Path $fixture 'missing.zip'))){$env:WINDOWS_SETUP_PESTER_PACKAGE_PATH=$path;$script:calls=0;$script:expands=0;$failed=$false;try{Get-PinnedPester|Out-Null}catch{$failed=$true};Assert ($failed -and $script:calls -eq 0 -and $script:expands -eq 0) 'prepared missing or bad hash fails without request or extraction'}
 $env:WINDOWS_SETUP_PESTER_PACKAGE_PATH='';$script:source=$bad;$script:calls=0;$script:expands=0;$failed=$false
 try{Get-PinnedPester|Out-Null}catch{$failed=$true}
 $cache=Join-Path $fixture 'windows_setup_pester_6_0_0'
 Assert ($failed -and $script:calls -eq 1 -and $script:expands -eq 0 -and -not(Test-Path (Join-Path $cache 'pester.zip')) -and @(Get-ChildItem $cache -Filter '*.download').Count -eq 0) 'bad downloaded hash is not cached, extracted or retained'
 $script:source=$good;$script:calls=0;$script:expands=0;$null=Get-PinnedPester
 Assert ($script:calls -eq 1 -and $script:expands -eq 1 -and (Test-Path (Join-Path $cache 'pester.zip'))) 'valid downloaded bytes verified before cache and extraction'
} finally {$env:TEMP=$oldTemp;$env:TMP=$oldTmp;$env:WINDOWS_SETUP_PESTER_PACKAGE_PATH=$oldPackage;if(Test-Path $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}}
