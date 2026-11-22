#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_catalog_contract.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function New-Fixture {
 $component=@{SchemaVersion=1;Id='device';Version='1.2';OfficialRaw=@{SizeBytes=[long]4294967297;SHA256=('a'*64);SourceUrl='https://example.invalid/raw'};Prepared=@{SizeBytes=[long]2147483649;SHA256=('b'*64);DerivedFromSHA256=('a'*64);Preparation='fixture';License='fixture'}}
 return @{SchemaVersion=1;Release=@{Tag='v1.2.3';Commit=('a'*40)};Components=@($component);Profiles=@(@{Id='synthetic';Components=@('device')});Models=@(@{Id='model-a';Boards=@('board-a');HardwareIds=@('PCI\VEN_1234');ProfileId='synthetic';Status='Verified';VerifiedVersion='1.2';OfficialLatest='Unknown'},@{Id='model-b';Boards=@('board-a');HardwareIds=@('PCI\VEN_1234');ProfileId='synthetic';Status='Unverified';VerifiedVersion='';OfficialLatest='Unknown'})}
}
function Check($catalog,$tag='v1.2.3',$sha=('a'*40)){Test-SetupDriverCatalog -Catalog $catalog -ExpectedTag $tag -ExpectedCommit $sha}
function Reject($catalog,$tag='v1.2.3',$sha=('a'*40)){try{Check $catalog $tag $sha|Out-Null;return $false}catch{return $true}}
$c=New-Fixture;$result=Check $c
Assert ($result.Release.Tag -ceq 'v1.2.3' -and $result.Components[0].OfficialRaw.SizeBytes -is [long] -and $result.Components[0].OfficialRaw.SizeBytes -eq 4294967297) 'valid fixed release and large component preserved'
Assert ($result.Models.Count -eq 2 -and $result.Models[0].Boards[0] -ceq $result.Models[1].Boards[0] -and $result.Models[0].HardwareIds[0] -ceq $result.Models[1].HardwareIds[0]) 'shared board and hardware accepted with explicit distinct model identity'
# Targeted cases: unambiguous automatic selection, OS identity case and valid future enumerators.
$targetedFailures=@()
$c=New-Fixture;$c.Models[1].Boards=@('board-b')
try{$auto=Select-SetupDriverCatalogModel -Catalog $c -ExpectedTag 'v1.2.3' -ExpectedCommit ('a'*40) -Board 'BOARD-B' -HardwareId 'pci\ven_1234';if($auto.Id -cne 'model-b'){$targetedFailures+='unique automatic selection'}}catch{$targetedFailures+='unique automatic selection'}
$c=New-Fixture
try{$x=Select-SetupDriverCatalogModel -Catalog $c -ExpectedTag 'v1.2.3' -ExpectedCommit ('a'*40) -ModelId 'model-a' -Board 'BOARD-A' -HardwareId 'pci\ven_1234';if($x.Id -cne 'model-a'){$targetedFailures+='OS identity case'}}catch{$targetedFailures+='OS identity case'}
$c=New-Fixture;$c.Models[0].Boards=@('Board With Space');$c.Models[0].HardwareIds=@('HID\VID_1234')
try{Check $c|Out-Null}catch{$targetedFailures+='future PnP and board spaces'}
$c=New-Fixture;$c.Models[0].ProfileId='SYNTHETIC';if(-not (Reject $c)){$targetedFailures+='canonical profile reference'}
$c=New-Fixture;$c.Profiles[0].Components=@('DEVICE');if(-not (Reject $c)){$targetedFailures+='canonical component reference'}
Assert ($targetedFailures.Count -eq 0) ('targeted catalog compatibility: '+($targetedFailures -join ', '))
$c=New-Fixture;$c.Models[0].HardwareIds=@('INTELAUDIO\FUNC_01')
Assert (-not (Reject $c)) 'Intel audio enumerator accepted as valid hardware syntax'
$c=New-Fixture;$c.Models[0].Boards=@('Board A','board a')
Assert (Reject $c) 'board duplicates use case-insensitive OS identity'
$c=New-Fixture;$c.Models[0].HardwareIds=@('HID\VID_1234','hid\vid_1234')
Assert (Reject $c) 'hardware duplicates use case-insensitive OS identity'
$c=New-Fixture;$c.Models[0].Boards=@(' board-a')
Assert (Reject $c) 'board leading whitespace rejected'
$c=New-Fixture
$selected=Select-SetupDriverCatalogModel -Catalog $c -ExpectedTag 'v1.2.3' -ExpectedCommit ('a'*40) -ModelId 'model-b' -Board 'board-a' -HardwareId 'PCI\VEN_1234'
Assert ($selected.Id -ceq 'model-b' -and $selected.Status -ceq 'Unverified') 'explicit model selects distinct sibling without promoting status'
foreach($selection in @(@{ModelId='';Board='board-a';HardwareId='PCI\VEN_1234'},@{ModelId='unknown';Board='board-a';HardwareId='PCI\VEN_1234'},@{ModelId='model-a';Board='other';HardwareId='PCI\VEN_1234'},@{ModelId='model-a';Board='board-a';HardwareId='PCI\VEN_9999'})){
 $rejected=$false;try{Select-SetupDriverCatalogModel -Catalog $c -ExpectedTag 'v1.2.3' -ExpectedCommit ('a'*40) @selection|Out-Null}catch{$rejected=$true}
 Assert $rejected 'missing or mismatched explicit selection rejected'
}
$c=New-Fixture;$roundtrip=$c|ConvertTo-Json -Depth 10|ConvertFrom-Json;$result=Check $roundtrip
Assert ($result.Components[0].OfficialRaw.SizeBytes -is [long]) 'JSON integer size retains 64-bit normalization'
Assert (Reject (New-Fixture) 'v1.2.4') 'different expected release tag rejected'
Assert (Reject (New-Fixture) 'v1.2.3' ('b'*40)) 'different expected commit rejected'
$c=New-Fixture;$c.Release.Tag='v1.2.4';$c.Release.Commit=('b'*40);$other=Check $c 'v1.2.4' ('b'*40)
Assert ($other.Release.Tag -ceq 'v1.2.4' -and (Reject $c 'v1.2.3' ('a'*40))) 'separate releases remain bound to their explicit identities'
foreach($case in @('schema','release','badsha','empty-models','duplicate-model','missing-board','duplicate-board','missing-hardware','duplicate-hardware','bad-hardware','unknown-profile','duplicate-profile','missing-component','unknown-component','duplicate-reference','duplicate-component','bad-digest','bad-source','bad-size','bad-status','missing-verified','unverified-version','latest-claim')){
 $c=New-Fixture
 switch($case){
  schema{$c.SchemaVersion=2} release{$c.Release.Tag=''} badsha{$c.Release.Commit='bad'} 'empty-models'{$c.Models=@()} 'duplicate-model'{$c.Models[1].Id=$c.Models[0].Id} 'missing-board'{$c.Models[0].Boards=@()} 'duplicate-board'{$c.Models[0].Boards=@('board-a','board-a')} 'missing-hardware'{$c.Models[0].HardwareIds=@()} 'duplicate-hardware'{$c.Models[0].HardwareIds=@('PCI\VEN_1234','PCI\VEN_1234')} 'bad-hardware'{$c.Models[0].HardwareIds=@('bad')} 'unknown-profile'{$c.Models[0].ProfileId='missing'} 'duplicate-profile'{$c.Profiles+=@{Id='synthetic';Components=@('device')}} 'missing-component'{$c.Profiles[0].Components=@()} 'unknown-component'{$c.Profiles[0].Components=@('missing')} 'duplicate-reference'{$c.Profiles[0].Components=@('device','device')} 'duplicate-component'{$c.Components+= $c.Components[0]} 'bad-digest'{$c.Components[0].Prepared.SHA256='bad'} 'bad-source'{$c.Components[0].OfficialRaw.SourceUrl='http://example.invalid'} 'bad-size'{$c.Components[0].OfficialRaw.SizeBytes=0} 'bad-status'{$c.Models[0].Status='Unknown'} 'missing-verified'{$c.Models[0].VerifiedVersion=''} 'unverified-version'{$c.Models[1].VerifiedVersion='1.2'} 'latest-claim'{$c.Models[0].OfficialLatest='1.3'}
 }
 Assert (Reject $c) ('reject '+$case)
}