#Requires -Version 5.1
# Pure contract only: the caller establishes path validity and authenticates official observations.
# Version identifies both artifact roles; Prepared is derived from the pinned raw digest.
# HTTPS validation is syntactic; callers must avoid secrets and authenticate content and redirects.
function Test-SetupDriverHttpsSource {
 param($Value)
 if($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^https://' -or $Value -match '[\p{C}\s]'){return $false}
 $uri=$null
 if(-not [Uri]::TryCreate($Value,[UriKind]::Absolute,[ref]$uri)){return $false}
 return ($uri.Scheme -ceq 'https' -and -not [string]::IsNullOrEmpty($uri.Host) -and [string]::IsNullOrEmpty($uri.UserInfo))
}
function Test-SetupDriverRecord {
 param($Value)
 return ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject])
}
function Test-SetupDriverComponentManifest {
 param([Parameter(Mandatory=$true)]$Manifest)
 if(-not (Test-SetupDriverRecord $Manifest)){throw 'Invalid component record.'}
 if($Manifest.SchemaVersion -isnot [int] -or $Manifest.SchemaVersion -ne 1){throw 'Invalid component schema.'}
 foreach($value in @($Manifest.Id,$Manifest.Version)){
  if($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value -match '[\p{C}]'){throw 'Invalid component identity.'}
 }
 foreach($part in @($Manifest.OfficialRaw,$Manifest.Prepared)){
  if(-not (Test-SetupDriverRecord $part)){throw 'Invalid component artifact.'}
  if(($part.SizeBytes -isnot [long] -and $part.SizeBytes -isnot [int]) -or $part.SizeBytes -le 0){throw 'Invalid component artifact size.'}
  if($part.SHA256 -isnot [string] -or $part.SHA256 -notmatch '\A[a-fA-F0-9]{64}\z'){throw 'Invalid component artifact digest.'}
 }
 if(-not (Test-SetupDriverHttpsSource $Manifest.OfficialRaw.SourceUrl)){throw 'Invalid official source.'}
 $prepared=$Manifest.Prepared
 if($prepared.DerivedFromSHA256 -isnot [string] -or $prepared.DerivedFromSHA256 -notmatch '\A[a-fA-F0-9]{64}\z' -or $prepared.DerivedFromSHA256 -ine $Manifest.OfficialRaw.SHA256){throw 'Invalid derivation digest.'}
 foreach($value in @($prepared.Preparation,$prepared.License)){
  if($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value -match '[\p{C}]'){throw 'Missing prepared provenance.'}
 }
 return [pscustomobject]@{SchemaVersion=1;Id=$Manifest.Id;Version=$Manifest.Version;OfficialRaw=[pscustomobject]@{SizeBytes=[long]$Manifest.OfficialRaw.SizeBytes;SHA256=$Manifest.OfficialRaw.SHA256;SourceUrl=$Manifest.OfficialRaw.SourceUrl};Prepared=[pscustomobject]@{SizeBytes=[long]$prepared.SizeBytes;SHA256=$prepared.SHA256;DerivedFromSHA256=$prepared.DerivedFromSHA256;Preparation=$prepared.Preparation;License=$prepared.License}}
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
 if(-not (Test-SetupDriverHttpsSource $FallbackUrl)){return @{Source='Stop'}}
 return @{Source='Fallback'}
}
