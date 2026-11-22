#Requires -Version 5.1
# Pure catalog contract: callers supply trusted expected release identity and observations.
. (Join-Path $PSScriptRoot 'driver_component_contract.ps1')
function Test-SetupDriverCatalog {
 param($Catalog,$ExpectedTag,$ExpectedCommit)
 if(-not (Test-SetupDriverRecord $Catalog) -or $Catalog.SchemaVersion -isnot [int] -or $Catalog.SchemaVersion -ne 1){throw 'Invalid catalog schema.'}
 if(-not (Test-SetupDriverRecord $Catalog.Release)){throw 'Invalid release identity.'}
 foreach($tag in @($ExpectedTag,$Catalog.Release.Tag)){
  if($tag -isnot [string] -or $tag -cnotmatch '\Av[0-9]+\.[0-9]+\.[0-9]+\z'){throw 'Invalid release tag.'}
 }
 foreach($commit in @($ExpectedCommit,$Catalog.Release.Commit)){
  if($commit -isnot [string] -or $commit -cnotmatch '\A[a-f0-9]{40}\z'){throw 'Invalid release commit.'}
 }
 if($Catalog.Release.Tag -cne $ExpectedTag -or $Catalog.Release.Commit -cne $ExpectedCommit){throw 'Release identity mismatch.'}
 foreach($name in @('Components','Profiles','Models')){
  if($Catalog.$name -isnot [array] -or $Catalog.$name.Count -eq 0){throw 'Missing catalog entries.'}
 }
 $components=@{};$normalizedComponents=@()
 foreach($component in $Catalog.Components){
  $entry=Test-SetupDriverComponentManifest $component
  if($entry.Id -cnotmatch '\A[a-z0-9][a-z0-9_-]{0,63}\z' -or $components.ContainsKey($entry.Id)){throw 'Duplicate or invalid component ID.'}
  $components[$entry.Id]=$true;$normalizedComponents+=@($entry)
 }
 $profiles=@{}
 foreach($profile in $Catalog.Profiles){
  if(-not (Test-SetupDriverRecord $profile) -or $profile.Id -isnot [string] -or $profile.Id -cnotmatch '\A[a-z0-9][a-z0-9_-]{0,63}\z' -or $profiles.ContainsKey($profile.Id)){throw 'Duplicate or invalid profile ID.'}
  if($profile.Components -isnot [array] -or $profile.Components.Count -eq 0){throw 'Missing component references.'}
  $seen=@{}
  foreach($id in $profile.Components){
   if($id -isnot [string] -or $id -cnotmatch '\A[a-z0-9][a-z0-9_-]{0,63}\z' -or -not $components.ContainsKey($id) -or $seen.ContainsKey($id)){throw 'Invalid component reference.'}
   $seen[$id]=$true
  }
  $profiles[$profile.Id]=$true
 }
 $models=@{}
 foreach($model in $Catalog.Models){
  if(-not (Test-SetupDriverRecord $model) -or $model.Id -isnot [string] -or $model.Id -cnotmatch '\A[a-z0-9][a-z0-9_-]{0,63}\z' -or $models.ContainsKey($model.Id)){throw 'Duplicate or invalid model ID.'}
  if($model.ProfileId -isnot [string] -or $model.ProfileId -cnotmatch '\A[a-z0-9][a-z0-9_-]{0,63}\z' -or -not $profiles.ContainsKey($model.ProfileId)){throw 'Unknown profile.'}
  foreach($field in @('Boards','HardwareIds')){
   $values=$model.$field
   if($values -isnot [array] -or $values.Count -eq 0){throw 'Missing model mapping.'}
   $seen=@{}
   foreach($value in $values){
    if($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value -cne $value.Trim() -or $value -match '[\p{C}]' -or $seen.ContainsKey($value)){throw 'Invalid or duplicate model mapping.'}
    if($field -eq 'HardwareIds' -and $value -notmatch '\A[A-Z0-9_]+\\[A-Z0-9_&.\-]+\z'){throw 'Invalid hardware ID.'}
    $seen[$value]=$true
   }
  }
  if($model.Status -cnotin @('Verified','Unverified') -or $model.VerifiedVersion -isnot [string] -or $model.OfficialLatest -cne 'Unknown'){throw 'Invalid evidence status.'}
  if(($model.Status -ceq 'Verified' -and [string]::IsNullOrWhiteSpace($model.VerifiedVersion)) -or ($model.Status -ceq 'Unverified' -and $model.VerifiedVersion -cne '') -or $model.VerifiedVersion -match '[\p{C}]'){throw 'Invalid verified version.'}
  $models[$model.Id]=$true
 }
 return [pscustomobject]@{SchemaVersion=1;Release=[pscustomobject]@{Tag=$Catalog.Release.Tag;Commit=$Catalog.Release.Commit};Components=$normalizedComponents;Profiles=@($Catalog.Profiles);Models=@($Catalog.Models)}
}
# An explicit model disambiguates siblings; board and hardware alone must identify exactly one.
function Select-SetupDriverCatalogModel {
 param($Catalog,$ExpectedTag,$ExpectedCommit,$ModelId='',$Board,$HardwareId)
 $checked=Test-SetupDriverCatalog -Catalog $Catalog -ExpectedTag $ExpectedTag -ExpectedCommit $ExpectedCommit
 if($ModelId -isnot [string] -or ($ModelId -cne '' -and $ModelId -cnotmatch '\A[a-z0-9][a-z0-9_-]{0,63}\z')){throw 'Invalid model selection.'}
 foreach($value in @($Board,$HardwareId)){
  if($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value -cne $value.Trim() -or $value -match '[\p{C}]'){throw 'Missing or invalid model selection.'}
 }
 $match=@($checked.Models|Where-Object {($ModelId -ceq '' -or $_.Id -ceq $ModelId) -and $Board -in $_.Boards -and $HardwareId -in $_.HardwareIds})
 if($match.Count -ne 1){throw 'Unknown or ambiguous model selection.'}
 return $match[0]
}
