#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
# 並行的 suite 可能同時發現 Pester 快取不存在並各自下載；其中一個先發布後，另一個不可因覆寫失敗而假失敗。
$source=Join-Path $root 'script/test/powershell_coverage.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
$function=$ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-PinnedPester'},$true)|Select-Object -First 1
Assert ($null -ne $function) '覆蓋率腳本提供固定版本 Pester 的取得函式'
$work=Join-Path $env:TEMP ('pester_race_'+[guid]::NewGuid().ToString('N'))
$savedTemp=$env:TEMP;$savedTmp=$env:TMP;$savedPackage=$env:WINDOWS_SETUP_PESTER_PACKAGE_PATH
try{
 [void][IO.Directory]::CreateDirectory($work)
 # 以真正的 zip 當作官方套件，雜湊由測試自己計算，不連網。
 $zipPath=Join-Path $work 'official.zip'
 Add-Type -AssemblyName System.IO.Compression
 $stream=[IO.File]::Open($zipPath,'Create')
 $archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create)
 $entry=$archive.CreateEntry('Pester.psd1');$writer=New-Object IO.StreamWriter($entry.Open());$writer.Write("@{ModuleVersion='6.0.0'}");$writer.Dispose()
 $archive.Dispose();$stream.Dispose()
 $bytes=[IO.File]::ReadAllBytes($zipPath)
 $packageHash=[Convert]::ToBase64String([Security.Cryptography.SHA512]::Create().ComputeHash($bytes))
 $tempRoot=Join-Path $work 'temp';[void][IO.Directory]::CreateDirectory($tempRoot)
 $env:TEMP=$tempRoot;$env:TMP=$tempRoot;Remove-Item Env:\WINDOWS_SETUP_PESTER_PACKAGE_PATH -ErrorAction SilentlyContinue
 $cacheZip=Join-Path $tempRoot 'windows_setup_pester_6_0_0/pester.zip'
 $script:holder=$null
 # 模擬競爭：下載期間，另一個行程已發布同一個快取檔，而且正在讀取它（不允許寫入或刪除）。
 function Invoke-WebRequest{param($Uri,$OutFile,[switch]$UseBasicParsing)
  [IO.File]::WriteAllBytes($OutFile,$bytes)
  [void][IO.Directory]::CreateDirectory((Split-Path $cacheZip -Parent))
  [IO.File]::WriteAllBytes($cacheZip,$bytes)
  $script:holder=[IO.File]::Open($cacheZip,'Open','Read','Read')
 }
 . ([scriptblock]::Create($function.Extent.Text))
 $failure='';$result=$null
 try{$result=Get-PinnedPester}catch{$failure=$_.Exception.Message}
 Assert ($failure -eq '') ('另一行程已發布並讀取快取時，不因覆寫失敗而中止：'+$failure)
 Assert ($null -ne $result -and (Test-Path -LiteralPath $result -PathType Leaf)) '競爭後仍回傳可載入的 Pester 清單檔'
 if($script:holder){$script:holder.Dispose()}
 Assert (@(Get-ChildItem -LiteralPath (Split-Path $cacheZip -Parent) -Filter '*.download' -ErrorAction SilentlyContinue).Count -eq 0) '競爭後不留下下載暫存檔'
 # 快取內容被竄改時仍拒絕載入。
 [IO.File]::WriteAllBytes($cacheZip,[byte[]](1,2,3))
 $rejected=$false;try{[void](Get-PinnedPester)}catch{$rejected=$_.Exception.Message -like '*SHA512*'}
 Assert $rejected '快取雜湊不符時仍拒絕載入'
 # 目標不存在、卻因別的原因無法發布（下載暫存檔被鎖住）時，仍要中止，不可假裝成功。
 Remove-Item -LiteralPath $cacheZip -Force
 $script:lockedDownload=$null
 function Invoke-WebRequest{param($Uri,$OutFile,[switch]$UseBasicParsing)
  [IO.File]::WriteAllBytes($OutFile,$bytes)
  $script:lockedDownload=[IO.File]::Open($OutFile,'Open','Read','None')
 }
 $aborted='';try{[void](Get-PinnedPester)}catch{$aborted=$_.Exception.Message}
 if($script:lockedDownload){$script:lockedDownload.Dispose()}
 Assert ($aborted -ne '' -and -not (Test-Path -LiteralPath $cacheZip)) '目標不存在且發布失敗時仍中止，不產生快取檔'
}finally{
 if($script:holder){$script:holder.Dispose()}
 $env:TEMP=$savedTemp;$env:TMP=$savedTmp
 if($null -ne $savedPackage){$env:WINDOWS_SETUP_PESTER_PACKAGE_PATH=$savedPackage}
 if($work.StartsWith([IO.Path]::GetFullPath($savedTemp),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
}
