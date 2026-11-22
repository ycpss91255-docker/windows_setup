#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_component_contract.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function New-Fixture { return @{SchemaVersion=[int]1;Id='synthetic';Version='1.2.3';OfficialRaw=@{SizeBytes=[long]4294967297;SHA256=('a'*64);SourceUrl='https://example.invalid/official?format=public'};Prepared=@{SizeBytes=[long]2147483649;SHA256=('b'*64);DerivedFromSHA256=('a'*64);Preparation='synthetic rule';License='synthetic license'}} }
function Reject($m){try{Test-SetupDriverComponentManifest $m | Out-Null;return $false}catch{return $true}}
$failures=@()
$m=New-Fixture;$normalized=Test-SetupDriverComponentManifest $m
if($normalized.OfficialRaw.SourceUrl -cne $m.OfficialRaw.SourceUrl){$failures+='source not preserved'}
$m=New-Fixture;$m.OfficialRaw.Remove('SourceUrl');if(-not (Reject $m)){$failures+='missing official source accepted'}
$m=New-Fixture;$m.OfficialRaw.SourceUrl='http://example.invalid/raw';if(-not (Reject $m)){$failures+='HTTP official source accepted'}
$m=New-Fixture;$m.Prepared.SHA256=('b'*64)+"`n";if(-not (Reject $m)){$failures+='digest trailing LF accepted'}
$m=New-Fixture;$m.OfficialRaw=@($m.OfficialRaw);if(-not (Reject $m)){$failures+='raw array accepted'}
$m=New-Fixture;$m.Prepared=@($m.Prepared);if(-not (Reject $m)){$failures+='prepared array accepted'}
$m=New-Fixture;if(-not (Reject @(,$m))){$failures+='root array accepted'}
if($failures.Count){throw ('Contract gaps: '+($failures -join '; '))}
$m=New-Fixture
$checked=Test-SetupDriverComponentManifest $m
Assert ($checked.OfficialRaw.SizeBytes -is [long] -and $checked.OfficialRaw.SizeBytes -eq [long]4294967297) 'valid 64-bit component'
$m=New-Fixture;$m.OfficialRaw.SizeBytes=[int]8
$json=$m|ConvertTo-Json -Depth 5|ConvertFrom-Json
$checked=Test-SetupDriverComponentManifest $json
Assert ($checked.OfficialRaw.SizeBytes -is [long] -and $checked.OfficialRaw.SizeBytes -eq 8 -and $checked.Prepared.SizeBytes -is [long]) 'JSON roundtrip normalizes integer sizes'
foreach($c in @('schema','id','version','size','fraction','boolean','overflow','hash','rawlf','derivedlf','idcontrol','rulecontrol','sourceuser','sourcelf','raw','prepared','derived','rule','license')){
 $m=New-Fixture
 switch($c){schema{$m.SchemaVersion='1'} id{$m.Id=''} version{$m.Version=''} size{$m.OfficialRaw.SizeBytes=[long]0} fraction{$m.OfficialRaw.SizeBytes=1.5} boolean{$m.OfficialRaw.SizeBytes=$true} overflow{$m.OfficialRaw.SizeBytes=[decimal]::MaxValue} hash{$m.Prepared.SHA256='bad'} rawlf{$m.OfficialRaw.SHA256=('a'*64)+"`n"} derivedlf{$m.Prepared.DerivedFromSHA256=('a'*64)+"`n"} idcontrol{$m.Id="synthetic`n"} rulecontrol{$m.Prepared.Preparation="rule`n"} sourceuser{$m.OfficialRaw.SourceUrl='https://user@example.invalid/a'} sourcelf{$m.OfficialRaw.SourceUrl="https://example.invalid/a`n"} raw{$m.OfficialRaw=$null} prepared{$m.Prepared=$null} derived{$m.Prepared.DerivedFromSHA256=('c'*64)} rule{$m.Prepared.Preparation=''} license{$m.Prepared.License=''}}
 Assert (Reject $m) ('reject '+$c)
}
function Decide($local,$path,$valid,$observation,$url){Select-SetupDriverComponentSource -LocalSpecified $local -LocalPath $path -LocalValid $valid -OfficialObservation $observation -FallbackUrl $url}
Assert ((Decide $true 'X:\synthetic' $true 'NotFound404' 'https://example.invalid/a').Source -eq 'Local') 'local wins without network'
Assert ((Decide $true '' $true 'NotFound404' 'https://example.invalid/a').Source -eq 'Stop') 'blank explicit local stops even if marked valid'
foreach($p in @('', 'bad')){Assert ((Decide $true $p $false 'NotFound404' 'https://example.invalid/a').Source -eq 'Stop') 'invalid explicit local stops'}
Assert ((Select-SetupDriverComponentSource -LocalSpecified $true -LocalPath 'invalid' -LocalValid 'false' -OfficialObservation 'NotChecked' -FallbackUrl '').Source -eq 'Stop') 'reject coerced validity'
Assert ((Select-SetupDriverComponentSource -LocalSpecified 'false' -LocalPath '' -LocalValid $false -OfficialObservation 'NotChecked' -FallbackUrl '').Source -eq 'Stop') 'reject coerced local selection'
Assert ((Decide $false '' $false 'NotChecked' '').Source -eq 'Official') 'default official'
foreach($x in @('NotFound404','EOL')){Assert ((Decide $false '' $false $x 'https://example.invalid/a?lang=en').Source -eq 'Fallback') ('trusted '+$x)}
foreach($x in @('NetworkError','IntegrityFailure','SignatureFailure','Unauthorized','UnexpectedResponse','Unknown')){Assert ((Decide $false '' $false $x 'https://example.invalid/a').Source -eq 'Stop') ('stop '+$x)}
foreach($u in @('','http://example.invalid/a','https://user@example.invalid/a','https:\example.invalid/a',"https://example.invalid/`n",'https://')){Assert ((Decide $false '' $false 'EOL' $u).Source -eq 'Stop') 'reject unsafe fallback'}
Write-Output 'PASS: synthetic driver component contract'
