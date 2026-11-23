#Requires -Version 5.1
[CmdletBinding()]
param([string]$EventName,[string]$BaseRef,[string]$Root='.',[string]$OutputPath,[switch]$FailOpen)
# PR 變更分類：只決定哪些必要工作可在 PR 階段略過。非 PR 事件（main、merge_group、tag、手動）、
# 取不到 diff、路徑無法判斷時一律選完整套件（fail open），讓分類失敗只增加執行而不放行未驗證內容。
$ErrorActionPreference='Stop'
$script:CIHeavyKeys=@('tests','powershell_coverage','coverage_aggregation','requirements_gate','docker_tests','oobe_payload')
$script:CIGlobalContract='^(architecture|layout|markdown_line_ending)'
$script:CIMaxScopedFiles=300
$script:CIHubReferenceLimit=30
# 這些路徑改動會影響所有測試或工作流程本身，PR 階段不縮小範圍；逐條命名以便個別驗證。
$script:CISharedPathRules=@(
 @{Name='workflow';Pattern='^\.github/'},
 @{Name='go_module';Pattern='^(go\.(mod|sum)$|vendor/)'},
 @{Name='version';Pattern='^\.version$'},
 @{Name='container';Pattern='^(dockerfile$|compose\.yaml$|script/docker/)'},
 @{Name='ci_tools';Pattern='^script/test/(ci_|run_ci\.ps1|test_report|powershell_coverage|run_repo_coverage|repo_coverage)'},
 @{Name='test_support';Pattern='^(test/powershell/(helpers|support|coverage)/|test/powershell/fixtures/[^/]+\.(ps1|psm1|psd1|cmd|bat)$)'},
 @{Name='path_registry';Pattern='^core/paths\.'},
 @{Name='go_source';Pattern='(\.go$|^test/go/)'}
)
$script:CIReferenceExtensions=@('.ps1','.psm1','.psd1','.cmd','.bat','.json','.xml')
$script:CIPlainOutputs=@('test_scope','affected_tests','doc_tests')

function Test-CIDocumentPath {
 param([string]$Path)
 if([string]::IsNullOrWhiteSpace($Path) -or $Path -cmatch '[\x00-\x1f\\"]' -or $Path.StartsWith('/') -or $Path.EndsWith('/')){return $false}
 foreach($segment in $Path.Split('/')){if($segment -ceq '' -or $segment -ceq '.' -or $segment -ceq '..'){return $false}}
 # 文件只限根目錄 Markdown 與 license、PR 範本，以及 doc 下的 Markdown；第三方內容與可執行檔不算文件。
 return ($Path -imatch '^[^/]+\.md$' -or $Path -imatch '^license$' -or $Path -ceq '.github/pull_request_template.md' -or $Path -imatch '^doc/.+\.md$')
}

function Test-CISafePath {
 param([string]$Path)
 if([string]::IsNullOrWhiteSpace($Path) -or $Path -cmatch '[\x00-\x1f\\"]' -or $Path.StartsWith('/') -or $Path.EndsWith('/')){return $false}
 foreach($segment in $Path.Split('/')){if($segment -ceq '' -or $segment -ceq '.' -or $segment -ceq '..'){return $false}}
 return $true
}

function Get-CIFullScope {
 param([string]$Reason)
 return [pscustomobject]@{Scope='full';Tests=@();Reason=$Reason}
}

function Get-CIReferenceIndex {
 param([string]$Root)
 $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
 $files=New-Object Collections.Generic.List[object]
 foreach($directory in @('core','modules','script','test','drivers')){
  $base=Join-Path $rootFull $directory
  if(-not(Test-Path -LiteralPath $base -PathType Container)){continue}
  foreach($file in @(Get-ChildItem -LiteralPath $base -File -Recurse -ErrorAction Stop)){
   if($script:CIReferenceExtensions -cnotcontains $file.Extension.ToLowerInvariant()){continue}
   $relative=$file.FullName.Substring($rootFull.Length+1).Replace('\','/')
   if($relative -imatch '^(vendor|\.git)/' -or $relative -imatch '/vendor/'){continue}
   $files.Add([pscustomobject]@{Path=$relative;Lower=$relative.ToLowerInvariant();Text=([IO.File]::ReadAllText($file.FullName)).Replace('\','/').ToLowerInvariant()})
  }
 }
 foreach($file in @(Get-ChildItem -LiteralPath $rootFull -File -ErrorAction Stop)){
  if($script:CIReferenceExtensions -cnotcontains $file.Extension.ToLowerInvariant()){continue}
  $files.Add([pscustomobject]@{Path=$file.Name;Lower=$file.Name.ToLowerInvariant();Text=([IO.File]::ReadAllText($file.FullName)).Replace('\','/').ToLowerInvariant()})
 }
 return ,$files.ToArray()
}

function Test-CIReferenceHub {
 # 登錄表或總入口會提到大量檔案（例如 core/paths.json）；只經由它們出現的引用不代表依賴，不當作引用鏈的中繼點。
 param($File,$CodeFiles)
 $count=0
 foreach($other in $CodeFiles){
  if($other.Lower -ceq $File.Lower){continue}
  $basename=[regex]::Escape($other.Lower.Substring($other.Lower.LastIndexOf('/')+1))
  if($File.Text.Contains($other.Lower) -or $File.Text -match ('(?<![a-z0-9_.-])'+$basename+'(?![a-z0-9_])')){
   $count++
   if($count -gt $script:CIHubReferenceLimit){return $true}
  }
 }
 return $false
}

function Get-CISuiteName {
 param([string]$Path)
 if($Path -cmatch '^test/powershell/(unit|integration)/([a-z0-9_]+)_tests\.ps1$'){
  return ($(if($Matches[1] -ceq 'unit'){'Unit'}else{'Integration'})+'.'+$Matches[2])
 }
 return $null
}

function Get-CIAllSuiteNames {
 param([string]$Root)
 $names=New-Object Collections.Generic.List[string]
 foreach($kind in @('Unit','Integration')){
  $directory=Join-Path $Root ('test/powershell/'+$kind.ToLowerInvariant())
  if(-not(Test-Path -LiteralPath $directory -PathType Container)){continue}
  foreach($file in @(Get-ChildItem -LiteralPath $directory -Filter '*_tests.ps1' -File)){$names.Add($kind+'.'+$file.BaseName.Replace('_tests',''))}
 }
 return @($names|Sort-Object)
}

function Get-CIGlobalContractTests {
 param([string]$Root)
 $names=New-Object Collections.Generic.List[string]
 foreach($kind in @('Unit','Integration')){
  $directory=Join-Path $Root ('test/powershell/'+$kind.ToLowerInvariant())
  if(-not(Test-Path -LiteralPath $directory -PathType Container)){continue}
  foreach($file in @(Get-ChildItem -LiteralPath $directory -Filter '*_tests.ps1' -File)){
   $base=$file.BaseName.Replace('_tests','')
   if($base -cmatch $script:CIGlobalContract){$names.Add($kind+'.'+$base)}
  }
 }
 return @($names|Sort-Object)
}

function Get-CISharedPathRule {
 param([string]$Path)
 foreach($rule in @($script:CISharedPathRules)){if($Path -imatch $rule.Pattern){return $rule.Name}}
 return $null
}

function Get-CIFixtureDirectory {
 # test/powershell/fixtures/<目錄>/<檔案>：現場重放資料，回傳目錄名；fixtures 根目錄的散檔屬於共用輔助，不在此列。
 param([string]$Path)
 if($Path -cmatch '^test/powershell/fixtures/([A-Za-z0-9_][A-Za-z0-9_.-]*)/.+'){return $Matches[1]}
 return $null
}

function Get-CIFixtureSuites {
 # suite 以目錄名組路徑讀取 fixture，所以用「fixtures/<目錄>」比對；非 suite 檔（輔助程式）也引用同一目錄時無法確定影響範圍，回傳 $null 由呼叫端選完整套件。
 param([object[]]$Index,[string]$Directory)
 $needle='fixtures/'+$Directory.ToLowerInvariant()
 $pattern='(?<![a-z0-9_.-])'+[regex]::Escape($needle)+'(?![a-z0-9_.-])'
 $found=New-Object Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
 foreach($file in $Index){
  if($file.Lower.StartsWith('test/powershell/fixtures/'+$Directory.ToLowerInvariant()+'/')){continue}
  if(-not($file.Text -match $pattern)){continue}
  # 正式程式碼不得引用測試資料（只可能是註解），不是載入者。
  if($file.Lower -match '^(core|modules|drivers)/'){continue}
  $suite=Get-CISuiteName $file.Path
  if(-not $suite){return $null}
  [void]$found.Add($suite)
 }
 return ,@($found|Sort-Object)
}
function Get-CIScopedTests {
 # 只在每個變更路徑都能經由測試內容的引用鏈對應到 suite 時縮小；任何無法判斷的情況回傳完整範圍。
 param([string]$Root,[string[]]$ChangedPaths,[int]$MaxSuites=0)
 if([string]::IsNullOrWhiteSpace($Root) -or -not(Test-Path -LiteralPath $Root -PathType Container)){return Get-CIFullScope '沒有可讀取的根目錄。'}
 if($null -eq $ChangedPaths -or @($ChangedPaths).Count -eq 0){return Get-CIFullScope '沒有變更清單。'}
 $paths=@($ChangedPaths|ForEach-Object {[string]$_})
 foreach($path in $paths){
  if(-not(Test-CISafePath $path)){return Get-CIFullScope ('可疑路徑：'+$path)}
  $rule=Get-CISharedPathRule $path
  if($rule){return Get-CIFullScope ('共用或全域路徑（'+$rule+'）：'+$path)}
 }
 $documents=@($paths|Where-Object {Test-CIDocumentPath $_})
 $code=@($paths|Where-Object {-not(Test-CIDocumentPath $_)})
 $suites=New-Object Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
 $needIndex=@()
 $fixtureDirectories=New-Object Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
 foreach($path in $code){
  $own=Get-CISuiteName $path
  if($own){
   if(Test-Path -LiteralPath (Join-Path $Root $path) -PathType Leaf){[void]$suites.Add($own)}
   continue
  }
  $fixtureDirectory=Get-CIFixtureDirectory $path
  if($fixtureDirectory){[void]$fixtureDirectories.Add($fixtureDirectory);continue}
  $needIndex+=$path
 }
 if($needIndex.Count -gt 0 -or $fixtureDirectories.Count -gt 0){
  $index=Get-CIReferenceIndex -Root $Root
  foreach($directory in $fixtureDirectories){
   $fixtureSuites=Get-CIFixtureSuites -Index $index -Directory $directory
   if($null -eq $fixtureSuites -or @($fixtureSuites).Count -eq 0){return Get-CIFullScope ('fixture 目錄沒有單純的測試引用：'+$directory)}
   foreach($name in $fixtureSuites){[void]$suites.Add($name)}
  }
  $codeFiles=@($index|Where-Object {-not(Get-CISuiteName $_.Path)})
  $hubs=@{}
  foreach($path in $needIndex){
   $found=New-Object Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
   $visited=New-Object Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
   $queue=New-Object Collections.Generic.Queue[string]
   $queue.Enqueue($path.ToLowerInvariant());[void]$visited.Add($path.ToLowerInvariant())
   while($queue.Count -gt 0){
    $current=$queue.Dequeue()
    $basename=[regex]::Escape($current.Substring($current.LastIndexOf('/')+1))
    $pattern='(?<![a-z0-9_.-])'+$basename+'(?![a-z0-9_])'
    foreach($file in $index){
     if($visited.Contains($file.Lower)){continue}
     if(-not($file.Text.Contains($current) -or $file.Text -match $pattern)){continue}
     $suite=Get-CISuiteName $file.Path
     if($suite){[void]$found.Add($suite);[void]$visited.Add($file.Lower);continue}
     [void]$visited.Add($file.Lower)
     if(-not $hubs.ContainsKey($file.Lower)){$hubs[$file.Lower]=Test-CIReferenceHub -File $file -CodeFiles $codeFiles}
     if(-not $hubs[$file.Lower]){$queue.Enqueue($file.Lower)}
    }
    if($visited.Count -gt $script:CIMaxScopedFiles){return Get-CIFullScope ('影響範圍過大：'+$path)}
   }
   if($found.Count -eq 0){return Get-CIFullScope ('沒有任何測試引用：'+$path)}
   foreach($name in $found){[void]$suites.Add($name)}
  }
 }
 if($documents.Count -gt 0){foreach($name in @(Get-CIDocumentTestNames -Root $Root -ChangedPaths $documents)){[void]$suites.Add($name)}}
 foreach($name in @(Get-CIGlobalContractTests -Root $Root)){[void]$suites.Add($name)}
 $tests=@($suites|Sort-Object)
 # 預設上限是全部 suite 的一半：超過就表示縮小的收益有限，直接跑完整套件。
 if($MaxSuites -le 0){$MaxSuites=[int][math]::Floor(@(Get-CIAllSuiteNames -Root $Root).Count/2)}
 if($tests.Count -gt $MaxSuites){return Get-CIFullScope ('受影響測試超過上限：'+$tests.Count+'／'+$MaxSuites)}
 return [pscustomobject]@{Scope='scoped';Tests=$tests;Reason=''}
}

function Get-CIChangeSelection {
 param([string]$EventName,[string[]]$ChangedPaths,[string]$Root)
 $selection=[ordered]@{}
 $documentOnly=$false
 $scope=$null
 if($EventName -ceq 'pull_request' -and $null -ne $ChangedPaths -and @($ChangedPaths).Count -gt 0){
  $documentOnly=$true
  foreach($path in @($ChangedPaths)){if(-not(Test-CIDocumentPath $path)){$documentOnly=$false;break}}
  if(-not $documentOnly -and $Root){
   try{$scope=Get-CIScopedTests -Root $Root -ChangedPaths $ChangedPaths}catch{$scope=$null}
  }
 }
 $scoped=($null -ne $scope -and $scope.Scope -ceq 'scoped')
 foreach($key in $script:CIHeavyKeys){
  $selection[$key]=$(if($documentOnly){'false'}elseif($scoped -and $key -cne 'tests' -and $key -cne 'oobe_payload'){'false'}else{'true'})
 }
 $selection['doc_checks']=$(if($documentOnly){'true'}else{'false'})
 $selection['test_scope']=$(if($scoped){'scoped'}else{'full'})
 $selection['affected_tests']=$(if($scoped){@($scope.Tests) -join ','}else{''})
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
 $lines=@(& git.exe -c core.quotepath=false -C $Root diff --no-renames --no-ext-diff --name-only ($BaseRef+'...HEAD') 2>$null)
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
  $selection=Get-CIChangeSelection -EventName $EventName -ChangedPaths $paths -Root $Root
  if($selection['doc_checks'] -ceq 'true'){
   $documentTests=(Get-CIDocumentTestNames -Root $Root -ChangedPaths $paths) -join ','
   if(-not $documentTests){throw '文件檢查清單為空。'}
  }
 }catch{
  Write-Host ('::warning::PR 變更分類失敗，改跑完整套件：'+$_.Exception.Message)
  $selection=Get-CIChangeSelection -EventName '' -ChangedPaths $null
  $documentTests=''
 }
 $lines=@(foreach($key in $selection.Keys){$(if($script:CIPlainOutputs -ccontains $key){$key}else{'select_'+$key})+'='+$selection[$key]})
 $lines+=('doc_tests='+$documentTests)
 $lines|ForEach-Object {Write-Host $_}
 if($OutputPath){[IO.File]::AppendAllText($OutputPath,(($lines -join "`n")+"`n"),[Text.UTF8Encoding]::new($false))}
}
if($MyInvocation.InvocationName -ne '.'){Invoke-CIClassify -EventName $EventName -BaseRef $BaseRef -Root $Root -OutputPath $OutputPath -FailOpen:$FailOpen}
