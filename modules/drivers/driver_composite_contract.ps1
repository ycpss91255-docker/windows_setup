#Requires -Version 5.1
# Validates a historical project composite against caller-supplied trusted release evidence.
# It does not authenticate that evidence, verify files, select hardware, or prove applicability.
. (Join-Path $PSScriptRoot 'driver_component_contract.ps1')
function Test-SetupDriverComposite {
 param($Record,$ExpectedTag,$ExpectedCommit,$ExpectedAsset)
 if(-not (Test-SetupDriverRecord $Record) -or -not (Test-SetupDriverRecord $ExpectedAsset)){throw 'Invalid composite record.'}
 $fields=@('SchemaVersion','Kind','Source','Latest','Applicability','Tag','Commit','Name','Size','SHA256','ProfileId','ManifestSHA256')
 $names=if($Record -is [System.Collections.IDictionary]){@($Record.Keys)}else{@($Record.PSObject.Properties.Name)}
 if($names.Count -ne $fields.Count -or @($names|Where-Object {$_ -cnotin $fields}).Count -ne 0){throw 'Invalid composite fields.'}
 foreach($field in @('Kind','Source','Latest','Applicability')){if($Record.$field -isnot [string]){throw 'Invalid composite classification.'}}
 if($Record.SchemaVersion -isnot [int] -or $Record.SchemaVersion -ne 1 -or $Record.Kind -cne 'PreparedComposite' -or $Record.Source -cne 'ProjectRelease' -or $Record.Latest -cne 'Unknown' -or $Record.Applicability -cne 'Unverified'){throw 'Invalid composite classification.'}
 foreach($tag in @($Record.Tag,$ExpectedTag)){if($tag -isnot [string] -or $tag -cnotmatch '\Av[0-9]+\.[0-9]+\.[0-9]+\z'){throw 'Invalid release tag.'}}
 foreach($commit in @($Record.Commit,$ExpectedCommit)){if($commit -isnot [string] -or $commit -cnotmatch '\A[a-f0-9]{40}\z'){throw 'Invalid release commit.'}}
 if($Record.Tag -cne $ExpectedTag -or $Record.Commit -cne $ExpectedCommit){throw 'Release identity mismatch.'}
 foreach($value in @($Record.Name,$ExpectedAsset.Name)){if($value -isnot [string] -or $value -cnotmatch '\A[a-z0-9_]+_v[0-9]+\.[0-9]+\.[0-9]+\.zip\z'){throw 'Invalid asset name.'}}
 foreach($value in @($Record.ProfileId,$ExpectedAsset.ProfileId)){if($value -isnot [string] -or $value -cnotmatch '\A[a-z0-9][a-z0-9_-]{0,63}\z'){throw 'Invalid profile.'}}
 foreach($value in @($Record.SHA256,$ExpectedAsset.SHA256,$Record.ManifestSHA256,$ExpectedAsset.ManifestSHA256)){if($value -isnot [string] -or $value -cnotmatch '\A[a-f0-9]{64}\z'){throw 'Invalid digest.'}}
 foreach($value in @($Record.Size,$ExpectedAsset.Size)){if(($value -isnot [long] -and $value -isnot [int]) -or $value -le 0){throw 'Invalid size.'}}
 foreach($field in @('Name','Size','SHA256','ProfileId','ManifestSHA256')){if($Record.$field -cne $ExpectedAsset.$field){throw 'Asset identity mismatch.'}}
 return [pscustomobject]@{SchemaVersion=1;Kind='PreparedComposite';Source='ProjectRelease';Latest='Unknown';Applicability='Unverified';Tag=$Record.Tag;Commit=$Record.Commit;Name=$Record.Name;Size=[long]$Record.Size;SHA256=$Record.SHA256;ProfileId=$Record.ProfileId;ManifestSHA256=$Record.ManifestSHA256}
}
