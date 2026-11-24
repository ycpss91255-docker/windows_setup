#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
. (Join-Path $root 'script/test/ci_classify.ps1')
# 現場重放 fixture 放在 test/powershell/fixtures/<目錄>/，由 suite 以目錄名組路徑讀取；
# 只要引用鏈確定且單純，就只選引用它的 suite，其餘一律維持完整套件。
$fixture=Join-Path $env:TEMP ('ci_fixture_scope_'+[guid]::NewGuid().ToString('N'))
try{
 $utf8=[Text.UTF8Encoding]::new($true)
 function Put($Relative,$Text){$full=Join-Path $fixture $Relative;[void][IO.Directory]::CreateDirectory((Split-Path $full -Parent));[IO.File]::WriteAllText($full,$Text,$utf8)}
 # 一個全域契約 suite 與 11 個無關 suite，讓縮小後的清單不超過全部的一半。
 Put 'test/powershell/integration/architecture_tests.ps1' "'global'"
 foreach($index in 1..11){Put ('test/powershell/unit/filler'+$index+'_tests.ps1') "'filler'"}
 Put 'test/powershell/unit/icons_replay_tests.ps1' "`$f=Join-Path `$root 'test/powershell/fixtures/nuc_icons_scene/'+`$name"
 Put 'test/powershell/unit/shared_a_tests.ps1' "`$f=Join-Path `$root 'test/powershell/fixtures/shared_scene'"
 Put 'test/powershell/unit/shared_b_tests.ps1' "`$f=Join-Path `$root `"test\powershell\fixtures\shared_scene\x.json`""
 Put 'test/powershell/unit/prefix_tests.ps1' "`$f=Join-Path `$root 'test/powershell/fixtures/nuc_icons_scene_extra/a.json'"
 Put 'test/powershell/unit/helper_user_tests.ps1' "`$f=Join-Path `$root 'test/powershell/fixtures/helper_scene/a.json'"
 Put 'test/powershell/helpers/scene_loader.ps1' "`$f=Join-Path `$root 'test/powershell/fixtures/helper_scene/a.json'"
 Put 'modules/doc/commented_library.ps1' "# 實機證據見 fixtures/helper_scene2"
 Put 'test/powershell/unit/comment_scene_tests.ps1' "$f=Join-Path $root 'test/powershell/fixtures/helper_scene2/a.json'"
 Put 'test/powershell/fixtures/loose_listing_20261122.txt' 'data'
 Put 'test/powershell/unit/loose_data_tests.ps1' "$f=Join-Path $root 'test/powershell/fixtures/loose_listing_20261122.txt'"
 foreach($path in @('helper_scene2/a.json','nuc_icons_scene/a.json','nuc_icons_scene_extra/a.json','shared_scene/x.json','helper_scene/a.json','orphan_scene/a.json')){Put ('test/powershell/fixtures/'+$path) '{}'}
 Put 'test/powershell/fixtures/loose_helper.ps1' "'loose'"
 function Scope([string[]]$Paths){Get-CIScopedTests -Root $fixture -ChangedPaths $Paths}

 $one=Scope @('test/powershell/fixtures/nuc_icons_scene/a.json','test/powershell/fixtures/nuc_icons_scene/readme.md')
 Assert ($one.Scope -ceq 'scoped' -and $one.Tests -ccontains 'Unit.icons_replay') 'fixture 目錄只被一個 suite 以目錄名引用時縮小為該 suite'
 Assert ($one.Tests -ccontains 'Integration.architecture' -and @($one.Tests).Count -eq 2) '縮小結果只含引用者與全域契約 suite，不含目錄名只是前綴的其他 suite'
 $many=Scope @('test/powershell/fixtures/shared_scene/x.json')
 Assert ($many.Scope -ceq 'scoped' -and $many.Tests -ccontains 'Unit.shared_a' -and $many.Tests -ccontains 'Unit.shared_b') '少數 suite 共用的 fixture 目錄選取全部引用者（含反斜線寫法）'
 $orphan=Scope @('test/powershell/fixtures/orphan_scene/a.json')
 Assert ($orphan.Scope -ceq 'full' -and $orphan.Reason -clike '*fixture*') '沒有任何 suite 引用的 fixture 目錄維持完整套件並說明原因'
 $helper=Scope @('test/powershell/fixtures/helper_scene/a.json')
 Assert ($helper.Scope -ceq 'full') '被非 suite 檔（輔助程式）引用的 fixture 目錄維持完整套件'
 $comment=Scope @('test/powershell/fixtures/helper_scene2/a.json')
 Assert ($comment.Scope -ceq 'scoped' -and $comment.Tests -ccontains 'Unit.comment_scene') '正式程式碼註解提到 fixture 目錄不構成載入者，仍可縮小'
 $looseData=Scope @('test/powershell/fixtures/loose_listing_20261122.txt')
 Assert ($looseData.Scope -ceq 'scoped' -and $looseData.Tests -ccontains 'Unit.loose_data') 'fixtures 根目錄的資料檔（非腳本）依引用鏈縮小'
 $loose=Scope @('test/powershell/fixtures/loose_helper.ps1')
 Assert ($loose.Scope -ceq 'full' -and $loose.Reason -clike '*test_support*') 'fixtures 根目錄的散檔仍是共用路徑'
 $mixed=Scope @('test/powershell/fixtures/nuc_icons_scene/a.json','test/powershell/helpers/scene_loader.ps1')
 Assert ($mixed.Scope -ceq 'full') 'fixture 與共用輔助程式一起變更仍是完整套件'
 $dots=Scope @('test/powershell/fixtures/../unit/filler1_tests.ps1','test/powershell/fixtures/nuc_icons_scene/a.json')
 Assert ($dots.Scope -ceq 'full' -and $dots.Reason -clike '*可疑*') '含上層路徑的 fixture 路徑不被當作 fixture 目錄'
 $selection=Get-CIChangeSelection -EventName pull_request -ChangedPaths @('test/powershell/fixtures/nuc_icons_scene/a.json') -Root $fixture
 Assert ($selection['test_scope'] -ceq 'scoped' -and $selection['tests'] -ceq 'true' -and $selection['docker_tests'] -ceq 'false' -and $selection['affected_tests'] -clike '*Unit.icons_replay*') 'PR 選取結果：只跑受影響 suite，略過 docker 與覆蓋率'
 foreach($event in @('push','merge_group','workflow_dispatch')){
  $full=Get-CIChangeSelection -EventName $event -ChangedPaths @('test/powershell/fixtures/nuc_icons_scene/a.json') -Root $fixture
  Assert ($full['test_scope'] -ceq 'full' -and $full['docker_tests'] -ceq 'true' -and $full['powershell_coverage'] -ceq 'true') ('非 PR 事件不因 fixture 縮小：'+$event)
 }
 # 實際倉庫：fixture 目錄真的存在時，引用鏈能找到其重放 suite。
 $real=Get-CIScopedTests -Root $root -ChangedPaths @('test/powershell/fixtures/nuc_scene_391/fixture_notes.md')
 Assert ($real.Scope -ceq 'full' -or $real.Tests.Count -ge 1) '實際倉庫的 fixture 目錄回傳可判定的結果'
}finally{
 if($fixture.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
