#Requires -Version 5.1
# Pure contract only: the caller establishes path validity and authenticates official observations.
function Test-SetupDriverComponentManifest {
 param([Parameter(Mandatory=$true)]$Manifest)
 if($Manifest.SchemaVersion -isnot [int] -or $Manifest.SchemaVersion -ne 1){throw 'Invalid component schema.'}
 foreach($value in @($Manifest.Id,$Manifest.Version)){
  if($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)){throw 'Invalid component identity.'}
 }
 foreach($part in @($Manifest.OfficialRaw,$Manifest.Prepared)){
  if($null -eq $part){throw 'Missing component artifact.'}
  if(($part.SizeBytes -isnot [long] -and $part.SizeBytes -isnot [int]) -or $part.SizeBytes -le 0){throw 'Invalid component artifact size.'}
  if($part.SHA256 -isnot [string] -or $part.SHA256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid component artifact digest.'}
 }
 $prepared=$Manifest.Prepared
 if($prepared.DerivedFromSHA256 -isnot [string] -or $prepared.DerivedFromSHA256 -notmatch '^[a-fA-F0-9]{64}$' -or $prepared.DerivedFromSHA256 -ine $Manifest.OfficialRaw.SHA256){throw 'Invalid derivation digest.'}
 foreach($value in @($prepared.Preparation,$prepared.License)){
  if($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)){throw 'Missing prepared provenance.'}
 }
 return [pscustomobject]@{SchemaVersion=1;Id=$Manifest.Id;Version=$Manifest.Version;OfficialRaw=[pscustomobject]@{SizeBytes=[long]$Manifest.OfficialRaw.SizeBytes;SHA256=$Manifest.OfficialRaw.SHA256};Prepared=[pscustomobject]@{SizeBytes=[long]$prepared.SizeBytes;SHA256=$prepared.SHA256;DerivedFromSHA256=$prepared.DerivedFromSHA256;Preparation=$prepared.Preparation;License=$prepared.License}}
}
function Select-SetupDriverComponentSource {
 param($LocalSpecified,$LocalPath,$LocalValid,$OfficialObservation,$FallbackUrl)
 if($LocalSpecified -isnot [bool] -or $LocalValid -isnot [bool] -or $LocalPath -isnot [string] -or $OfficialObservation -isnot [string] -or $FallbackUrl -isnot [string]){return @{Source='Stop'}}
 if($LocalSpecified){
  if($LocalValid -and -not [string]::IsNullOrWhiteSpace($LocalPath)){return @{Source='Local'}}
  return @{Source='Stop'}
 }
 if($OfficialObservation -ceq 'NotChecked'){return @{Source='Official'}}
 if($OfficialObservation -cne 'NotFound404' -and $OfficialObservation -cne 'EOL'){return @{Source='Stop'}}
 $uri=$null
 if([string]::IsNullOrWhiteSpace($FallbackUrl) -or $FallbackUrl -notmatch '^https://' -or $FallbackUrl -match '[\p{C}\s]' -or -not [Uri]::TryCreate($FallbackUrl,[UriKind]::Absolute,[ref]$uri)){return @{Source='Stop'}}
 if($uri.Scheme -cne 'https' -or [string]::IsNullOrEmpty($uri.Host) -or -not [string]::IsNullOrEmpty($uri.UserInfo)){return @{Source='Stop'}}
 return @{Source='Fallback'}
}
