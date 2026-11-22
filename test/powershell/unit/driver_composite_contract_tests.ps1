#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/drivers/driver_composite_contract.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Reject($record,$tag,$commit,$asset){try{Test-SetupDriverComposite -Record $record -ExpectedTag $tag -ExpectedCommit $commit -ExpectedAsset $asset|Out-Null;return $false}catch{return $true}}
$tag='v0.2.5';$commit='3129b9cbc3a5f5a96c29b761e146cd17408eed14'
$asset=@{Name='windows_driver_nuc8_v0.2.5.zip';Size=1757949457;SHA256='57e8efb38486ae05d8fdbde2f87392949606d10db605c8b4541833821e687ca3';ProfileId='nuc8i7hvk_hnk';ManifestSHA256='62f6bb64988eb60c3fcfcf5a7d9ba3a9670ff2cd50770422af3dd6b6a02fcc20'}
$taggedAsset=Get-Content (Join-Path $root 'script/release/driver_release_assets.json') -Raw -Encoding UTF8|ConvertFrom-Json
$actual=@($taggedAsset.Releases|Where-Object Version -CEQ $tag)[0].Assets[0]
foreach($key in @('Name','Size','SHA256','ProfileId','ManifestSHA256')){Assert ($actual.$key -ceq $asset.$key) ('release metadata '+$key)}
$path=Join-Path $root 'drivers/catalog_v0.2.5_nuc8_composite.json'
function ReadRecord {Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json}
$record=ReadRecord;$result=Test-SetupDriverComposite -Record $record -ExpectedTag $tag -ExpectedCommit $commit -ExpectedAsset $asset
Assert ($result.Source -ceq 'ProjectRelease' -and $result.Latest -ceq 'Unknown' -and $result.Applicability -ceq 'Unverified') 'historical artifact never claims latest or applicability'
Assert (Reject (ReadRecord) 'v0.2.4' $commit $asset) 'different tag rejected'
Assert (Reject (ReadRecord) $tag ('b'*40) $asset) 'different commit rejected'
foreach($field in @('Name','Size','SHA256','ProfileId','ManifestSHA256')){$wrong=@{};foreach($key in $asset.Keys){$wrong[$key]=$asset[$key]};if($field -eq 'Size'){$wrong[$field]=1}else{$wrong[$field]='wrong'};Assert (Reject (ReadRecord) $tag $commit $wrong) ('trusted asset mismatch '+$field)}
foreach($field in @('SchemaVersion','Kind','Source','Latest','Applicability','Tag','Commit','Name','Size','SHA256','ProfileId','ManifestSHA256')){$bad=ReadRecord;$bad.$field=$null;Assert (Reject $bad $tag $commit $asset) ('missing '+$field)}
foreach($field in @('Kind','Source','Latest','Applicability')){$bad=ReadRecord;$bad.$field='Other';Assert (Reject $bad $tag $commit $asset) ('invalid '+$field)}
$bad=ReadRecord;$bad.Size='1757949457';Assert (Reject $bad $tag $commit $asset) 'size coercion rejected'
$bad=ReadRecord;$bad|Add-Member -NotePropertyName OfficialLatest -NotePropertyValue '1.0';Assert (Reject $bad $tag $commit $asset) 'unknown claim rejected'
$bad=ReadRecord;$bad.Source=@('ProjectRelease');Assert (Reject $bad $tag $commit $asset) 'array classification rejected'
Write-Host 'PASS: fixed project release composite; no applicability or latest claim.'
