#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('driver_cleanup_inherited_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$shape=Join-Path $root 'test/powershell/fixtures/driver_cache_nuc_listing_20261122.txt'
$runner=Join-Path $fixture 'runner.ps1';$log=Join-Path $fixture 'private.log'
$source=@'
param([string]$SourceRoot,[string]$FixtureRoot,[string]$ShapePath)
$ErrorActionPreference='Stop'
# Real Assert-SetupUpdateAcl and real ACL objects; only Get-Acl is replaced so the fixture never touches real ProgramData.
. (Join-Path $SourceRoot 'modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$parent=Join-Path ([IO.Path]::GetFullPath($FixtureRoot)) 'cache';[void][IO.Directory]::CreateDirectory($parent);$parent=[IO.Path]::GetFullPath($parent)
function Get-SetupDriverCacheParent {$parent}
$script:SetupDriverExtractionLeases=@{};$script:extra=@{}
function Get-Acl {
 param($LiteralPath,$ErrorAction)
 $full=[IO.Path]::GetFullPath($LiteralPath)
 $directory=(Microsoft.PowerShell.Management\Get-Item -LiteralPath $full -Force).PSIsContainer
 $acl=if($directory){[Security.AccessControl.DirectorySecurity]::new()}else{[Security.AccessControl.FileSecurity]::new()}
 $depth=0;if($full.StartsWith($parent+'\')){$depth=$full.Substring($parent.Length+1).Split('\').Count}
 if($depth -le 1){
  $acl.SetSecurityDescriptorSddlForm('O:BAG:S-1-5-21-1-2-3-513D:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
 }else{
  $flags=if($directory){'OICIID'}else{'ID'}
  $sddl='O:BAG:S-1-5-21-1-2-3-513D:AI(A;'+$flags+';FA;;;SY)(A;'+$flags+';FA;;;BA)'
  $leaf=[IO.Path]::GetFileName($full)
  if($script:extra.ContainsKey($leaf)){$sddl+=$script:extra[$leaf]}
  $acl.SetSecurityDescriptorSddlForm($sddl)
 }
 return $acl
}
function NewTree {
 $path=Join-Path $parent ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($path)
 $deep=Join-Path $path 'a\b\c';[void][IO.Directory]::CreateDirectory($deep)
 [IO.File]::WriteAllText((Join-Path $path 'payload.sys'),'inert');[IO.File]::WriteAllText((Join-Path $deep 'deep.inf'),'inert')
 $script:SetupDriverExtractionLeases[$path]=[pscustomobject]@{NativeActive=$false;Token=[guid]::NewGuid().ToString('N')}
 return $path
}
$one=NewTree;$sibling=NewTree
$errorRecord=$null;$removed=$false;try{$removed=Remove-SetupDriverExtractionRoot $one}catch{$errorRecord=$_;Write-Host ('@@REASON@@'+$_.Exception.Message)}
Assert ($null -eq $errorRecord -and $removed -and -not(Test-Path $one)) '受保護本輪根目錄下繼承ACL的三層子目錄與檔案可完整清理'
Assert ((Test-Path $sibling) -and $script:SetupDriverExtractionLeases.ContainsKey($sibling)) '清理後兄弟本輪目錄保持不變'
$cases=@(
 @{Name='子目錄含繼承的一般使用者允許規則';Leaf='c';Sddl='(A;OICIID;FA;;;BU)'},
 @{Name='子目錄含外加的一般使用者允許規則';Leaf='c';Sddl='(A;OICI;FA;;;BU)'},
 @{Name='子目錄含拒絕規則';Leaf='c';Sddl='(D;OICI;FA;;;WD)'},
 @{Name='子檔含非可信允許規則';Leaf='deep.inf';Sddl='(A;;FA;;;BU)'}
)
# Replay of the real tree shape captured on the NUC (99 unprotected children, up to 5 levels under each protected lease).
$rows=@(Get-Content -LiteralPath $ShapePath -Encoding UTF8|ForEach-Object{$c=$_.Split('|');[pscustomobject]@{Path=$c[0];Depth=[int]$c[1]}}|Where-Object Depth -ge 1)
foreach($lease in @($rows|Where-Object Depth -eq 1)){
 $path=Join-Path $parent ([guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($path)
 foreach($row in $rows){if($row.Path -eq $lease.Path -or $row.Path.StartsWith($lease.Path+'/')){$rel=$row.Path.Substring($lease.Path.Length).TrimStart('/').Replace('/','\');$dir=if($rel){Join-Path $path $rel}else{$path};[void][IO.Directory]::CreateDirectory($dir);[IO.File]::WriteAllText((Join-Path $dir 'f.bin'),'inert')}}
 $script:SetupDriverExtractionLeases[$path]=[pscustomobject]@{NativeActive=$false;Token=[guid]::NewGuid().ToString('N')}
 $err=$null;$ok=$false;try{$ok=Remove-SetupDriverExtractionRoot $path}catch{$err=$_.Exception.Message;Write-Host ('@@REASON@@'+$err)}
 Assert ($null -eq $err -and $ok -and -not(Test-Path $path)) ('現場擷取目錄結構重放可清理：'+$lease.Path)
}
foreach($case in $cases){
 $script:extra=@{$case.Leaf=$case.Sddl}
 $tree=NewTree;$rejected=$false;try{Remove-SetupDriverExtractionRoot $tree|Out-Null}catch{$rejected=$_.Exception.Message.Contains('ACL')}
 Assert ($rejected -and (Test-Path (Join-Path $tree 'a\b\c\deep.inf'))) ('拒絕並保留資料：'+$case.Name)
 $script:extra=@{}
}
'@
[IO.File]::WriteAllText($runner,$source,[Text.UTF8Encoding]::new($true))
$prior=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -SourceRoot $root -FixtureRoot $fixture -ShapePath $shape *> $log;$native=$LASTEXITCODE}
finally{$ErrorActionPreference=$prior}
foreach($line in Get-Content -LiteralPath $log){if($line -match '^@@(ASSERT|REASON)@@'){Write-Host $line}}
if($native -ne 0){throw ('Inherited driver cleanup ACL child failed; native exit '+$native)}
