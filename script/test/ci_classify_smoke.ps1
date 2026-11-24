#Requires -Version 5.1
# 在 Linux 與 Windows 都能執行的分類器 smoke：不呼叫 .exe，以暫時 git 倉庫真實執行分類器。
function Invoke-CIClassifierSmoke {
 param([Parameter(Mandatory=$true)][string]$ClassifierPath)
 $ErrorActionPreference='Stop'
 $work=Join-Path ([IO.Path]::GetTempPath()) ('ci_classify_smoke_'+[guid]::NewGuid().ToString('N'))
 [void][IO.Directory]::CreateDirectory($work)
 try{
  $git={param([string[]]$GitArguments);& git -C $work -c user.name=smoke -c user.email=smoke@example.invalid -c commit.gpgsign=false -c core.autocrlf=false -c core.safecrlf=false @GitArguments|Out-Null;if($LASTEXITCODE -ne 0){throw ('git '+$GitArguments[0]+' 失敗，退出碼 '+$LASTEXITCODE)}}
  $utf8=[Text.UTF8Encoding]::new($false)
  & $git @('init','--quiet','-b','main')
  [void][IO.Directory]::CreateDirectory((Join-Path $work 'test/powershell/unit'))
  [IO.File]::WriteAllText((Join-Path $work 'readme.md'),'base'+[char]10,$utf8)
  [IO.File]::WriteAllText((Join-Path $work 'test/powershell/unit/architecture_tests.ps1'),"'global contract'"+[char]10,$utf8)
  [IO.File]::WriteAllText((Join-Path $work 'test/powershell/unit/readme_tests.ps1'),"Test-Path 'readme.md'"+[char]10,$utf8)
  & $git @('add','.')
  & $git @('commit','--quiet','-m','base')
  & $git @('update-ref','refs/remotes/origin/main','HEAD')
  & $git @('switch','--quiet','-c','pull')
  [IO.File]::WriteAllText((Join-Path $work 'readme.md'),'changed'+[char]10,$utf8)
  & $git @('commit','--quiet','-am','doc')
  $output=Join-Path $work 'classify_output.txt'
  [IO.File]::WriteAllText($output,'',$utf8)
  & $ClassifierPath -EventName pull_request -BaseRef 'origin/main' -Root $work -OutputPath $output 6>$null
  $result=@{}
  foreach($line in [IO.File]::ReadAllLines($output)){$index=$line.IndexOf('=');if($index -gt 0){$result[$line.Substring(0,$index)]=$line.Substring($index+1)}}
  if($result['classify_fallback'] -cne 'false'){throw ('分類器在暫時倉庫退回完整套件：'+$result['classify_fallback_reason'])}
  if($result['select_doc_checks'] -cne 'true' -or $result['select_tests'] -cne 'false'){throw '分類器對只改文件的變更沒有選出輕量文件檢查。'}
  return $result
 }finally{
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
 }
}
