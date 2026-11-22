#Requires -Version 5.1
# Standalone transfer primitive. Source selection, cache publication and resume are caller concerns.
function Test-SetupDriverStreamCapacity {
 param([long]$SizeBytes,[long]$AvailableBytes,[string]$FileSystem)
 if($SizeBytes -le 0 -or $AvailableBytes -lt 0 -or $AvailableBytes -lt $SizeBytes -or @('NTFS','ReFS','FAT32','exFAT') -inotcontains $FileSystem){return $false}
 if($FileSystem -ieq 'FAT32' -and $SizeBytes -gt [long]4294967295){return $false}
 return $true
}
function Get-SetupDriverStreamCapacity {
 param([string]$Destination)
 $root=[IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Destination))
 $drive=New-Object IO.DriveInfo($root)
 return [pscustomobject]@{AvailableBytes=[long]$drive.AvailableFreeSpace;FileSystem=$drive.DriveFormat}
}
function Copy-SetupDriverVerifiedStream {
 param([Parameter(Mandatory=$true)][IO.Stream]$InputStream,[Parameter(Mandatory=$true)][IO.Stream]$OutputStream,[long]$SizeBytes,[string]$SHA256)
 if($SizeBytes -le 0 -or $SHA256 -notmatch '\A[a-fA-F0-9]{64}\z'){throw 'Invalid expected size or digest.'}
 $buffer=New-Object byte[] 65536;$count=[long]0;$sha=[Security.Cryptography.SHA256]::Create()
 try{
  while(($read=$InputStream.Read($buffer,0,$buffer.Length)) -gt 0){
   if([long]$read -gt ($SizeBytes-$count)){throw 'Response exceeds expected size.'}
   $OutputStream.Write($buffer,0,$read);[void]$sha.TransformBlock($buffer,0,$read,$buffer,0);$count += [long]$read
  }
  if($count -ne $SizeBytes){throw 'Response is shorter than expected.'}
  [void]$sha.TransformFinalBlock((New-Object byte[] 0),0,0)
  $actual=([BitConverter]::ToString($sha.Hash)).Replace('-','').ToLowerInvariant()
  if($actual -cne $SHA256.ToLowerInvariant()){throw 'Response digest mismatch.'}
  return [pscustomobject]@{SizeBytes=$count;SHA256=$actual}
 }finally{$sha.Dispose()}
}
# Caller owns the initially empty staging stream, and supplies trusted capacity from its destination volume.
# Returned verification is not a flush, durability guarantee or publication.
# Failure leaves its contents unverified; no path is opened, removed, renamed or cached here.
function Invoke-SetupDriverHttpStream {
 param([string]$Uri,[Parameter(Mandatory=$true)][IO.Stream]$OutputStream,[long]$SizeBytes,[string]$SHA256,[Parameter(Mandatory=$true)]$Capacity)
 if($SizeBytes -le 0 -or $SHA256 -notmatch '\A[a-fA-F0-9]{64}\z'){throw 'Invalid expected size or digest.'}
 if(($Capacity.AvailableBytes -isnot [long] -and $Capacity.AvailableBytes -isnot [int]) -or $Capacity.FileSystem -isnot [string] -or -not (Test-SetupDriverStreamCapacity -SizeBytes $SizeBytes -AvailableBytes $Capacity.AvailableBytes -FileSystem $Capacity.FileSystem)){throw 'Destination capacity is insufficient or invalid.'}
 if(-not $OutputStream.CanWrite -or -not $OutputStream.CanSeek -or $OutputStream.Position -ne 0 -or $OutputStream.Length -ne 0){throw 'An empty caller-owned staging stream is required.'}
 if([string]::IsNullOrWhiteSpace($Uri) -or $Uri -match '[\p{C}\s]'){throw 'Invalid HTTP source.'}
 $parsed=$null
 if(-not [Uri]::TryCreate($Uri,[UriKind]::Absolute,[ref]$parsed) -or @('http','https') -cnotcontains $parsed.Scheme -or [string]::IsNullOrEmpty($parsed.Host) -or -not [string]::IsNullOrEmpty($parsed.UserInfo)){throw 'Invalid HTTP source.'}
 $response=$null;$inputStream=$null
 try{
  $request=[Net.WebRequest]::Create($parsed)
  if($request -isnot [Net.HttpWebRequest]){throw 'HTTP response required.'}
  $request.AllowAutoRedirect=$false;$request.Timeout=30000;$request.ReadWriteTimeout=30000
  $response=$request.GetResponse()
  if([int]$response.StatusCode -ne 200){throw 'Complete HTTP response required.'}
  $inputStream=$response.GetResponseStream()
  return Copy-SetupDriverVerifiedStream -InputStream $inputStream -OutputStream $OutputStream -SizeBytes $SizeBytes -SHA256 $SHA256
 }finally{if($inputStream){$inputStream.Dispose()};if($response){$response.Dispose()}}
}
