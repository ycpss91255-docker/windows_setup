#Requires -Version 5.1
[CmdletBinding()]
param([string]$EventName,[string]$BaseRef,[string]$Root='.',[string]$OutputPath,[switch]$FailOpen)
# PR 變更分類：只決定哪些必要工作可在 PR 階段略過。非 PR 事件（main、merge_group、tag、手動）、
# 取不到 diff、路徑無法判斷時一律選完整套件（fail open），讓分類失敗只增加執行而不放行未驗證內容。
$ErrorActionPreference='Stop'
$script:CIHeavyKeys=@('tests','powershell_coverage','coverage_aggregation','requirements_gate','docker_tests','oobe_payload')
$script:CIGlobalContract='^(architecture|layout|markdown_line_ending)'

function Test-CIDocumentPath {
 param([string]$Path)
 if([string]::IsNullOrWhiteSpace($Path) -or $Path -cmatch '[\x00-\x1f\\"]' -or $Path.StartsWith('/') -or $Path.EndsWith('/')){return $false}
 foreach($segment in $Path.Split('/')){if($segment -ceq '' -or $segment -ceq '.' -or $segment -ceq '..'){return $false}}
 # 文件只限根目錄 Markdown 與 license、PR 範本，以及 doc 下的 Markdown；第三方內容與可執行檔不算文件。
 return ($Path -imatch '^[^/]+\.md$' -or $Path -imatch '^license$' -or $Path -ceq '.github/pull_request_template.md' -or $Path -imatch '^doc/.+\.md$')
}

function Get-CIChangeSelection {
 param([string]$EventName,[string[]]$ChangedPaths)
 $selection=[ordered]@{}
 $documentOnly=$false
 if($EventName -ceq 'pull_request' -and $null -ne $ChangedPaths -and @($ChangedPaths).Count -gt 0){
  $documentOnly=$true
  foreach($path in @($ChangedPaths)){if(-not(Test-CIDocumentPath $path)){$documentOnly=$false;break}}
 }
 foreach($key in $script:CIHeavyKeys){$selection[$key]=$(if($documentOnly){'false'}else{'true'})}
 $selection['doc_checks']=$(if($documentOnly){'true'}else{'false'})
 return $selection
}

function Get-CIDocumentTestNames {
 param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string[]]$ChangedPaths)
 $names=New-Object Collections.Generic.List[string]
 $needles=@(foreach($path in $ChangedPaths){
  $lower=$path.ToLowerInvariant()
  [pscustomobject]@{Path=$lower;Basename=[regex]::Escape($lower.Substring($lower.LastIndexOf('/')+1))}
 })
 foreach($kind in @('Unit','Integration')){
  $directory=Join-Path $Root ('test/powershell/'+$kind.ToLowerInvariant())
  if(-not(Test-Path -LiteralPath $directory -PathType Container)){continue}
  foreach($file in @(Get-ChildItem -LiteralPath $directory -Filter '*_tests.ps1' -File)){
   $base=$file.BaseName.Replace('_tests','')
   $selected=$base -cmatch $script:CIGlobalContract
   if(-not $selected){
    $text=([IO.File]::ReadAllText($file.FullName)).Replace('\','/').ToLowerInvariant()
    foreach($needle in $needles){
     if($text.Contains($needle.Path) -or $text -match ('[''"/]'+$needle.Basename+'[''"]')){$selected=$true;break}
    }
   }
   if($selected){$names.Add($kind+'.'+$base)}
  }
 }
 return @($names|Sort-Object)
}

function Get-CIChangedPaths {
 param([string]$Root,[string]$BaseRef)
 if([string]::IsNullOrWhiteSpace($BaseRef)){return $null}
 $lines=@(& git.exe -c core.quotepath=false -C $Root diff --name-only ($BaseRef+'...HEAD') 2>$null)
 if($LASTEXITCODE -ne 0){return $null}
 return @($lines|ForEach-Object {[string]$_})
}

function Invoke-CIClassify {
 param([string]$EventName,[string]$BaseRef,[string]$Root,[string]$OutputPath,[switch]$FailOpen)
 $paths=$null
 $selection=$null
 $documentTests=''
 try{
  if($FailOpen){throw '明確要求完整套件。'}
  if($EventName -ceq 'pull_request'){$paths=Get-CIChangedPaths -Root $Root -BaseRef $BaseRef}
  $selection=Get-CIChangeSelection -EventName $EventName -ChangedPaths $paths
  if($selection['doc_checks'] -ceq 'true'){
   $documentTests=(Get-CIDocumentTestNames -Root $Root -ChangedPaths $paths) -join ','
   if(-not $documentTests){throw '文件檢查清單為空。'}
  }
 }catch{
  Write-Host ('::warning::PR 變更分類失敗，改跑完整套件：'+$_.Exception.Message)
  $selection=Get-CIChangeSelection -EventName '' -ChangedPaths $null
  $documentTests=''
 }
 $lines=@(foreach($key in $selection.Keys){'select_'+$key+'='+$selection[$key]})
 $lines+=('doc_tests='+$documentTests)
 $lines|ForEach-Object {Write-Host $_}
 if($OutputPath){[IO.File]::AppendAllText($OutputPath,(($lines -join "`n")+"`n"),[Text.UTF8Encoding]::new($false))}
}
if($MyInvocation.InvocationName -ne '.'){Invoke-CIClassify -EventName $EventName -BaseRef $BaseRef -Root $Root -OutputPath $OutputPath -FailOpen:$FailOpen}
