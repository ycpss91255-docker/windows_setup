#Requires -Version 5.1
# 換行契約：自有文字檔依類型宣告換行並以該換行檢出；CMD 以 CRLF 供 cmd.exe 正確解析；
# 雜湊綁定的資產鎖定原位元組；第三方內容不轉換。Markdown 由文件換行規則另行管理。
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
function Format-Offenders($Items){$list=@($Items);if($list.Count -eq 0){return ''};return ' ('+$list.Count+'): '+(($list|Select-Object -First 8) -join ', ')}
$categories=@(
 @{Name='CMD 啟動器';Pattern='\.cmd$';Eol='crlf'},
 @{Name='PowerShell 腳本';Pattern='\.ps1$';Eol='lf'}
)
$thirdParty=@('modules/debloat/win11debloat/')
$locked=@{

}
$checkUncategorized=$false
$raw=& git -C $root -c core.quotepath=false ls-files -z --eol
if($LASTEXITCODE -ne 0){throw '無法列出 Git 追蹤檔案。'}
$entries=@(([string]($raw -join "`n")).Split([char]0)|ForEach-Object {$_.Trim("`n")}|Where-Object {$_})
Assert ($entries.Count -gt 100) '換行盤點取得完整追蹤清單'
$records=foreach($entry in $entries){
 if($entry -notmatch '^i/(?<index>\S+)\s+w/(?<work>\S+)\s+attr/(?<attr>.*?)\s*\t(?<path>.+)$'){throw ('無法解析換行盤點：'+$entry)}
 [pscustomobject]@{Path=$Matches.path;Index=$Matches.index;Work=$Matches.work;Attr=$Matches.attr.Trim()}
}
$owned=[Collections.Generic.List[object]]::new();$lockedSeen=0
$thirdBad=[Collections.Generic.List[string]]::new();$lockedBad=[Collections.Generic.List[string]]::new()
foreach($record in $records){
 $prefix=@($thirdParty|Where-Object {$record.Path.StartsWith($_)})
 if($prefix.Count){if($record.Attr -cne '-text'){$thirdBad.Add($record.Path+'['+$record.Attr+']')};continue}
 if($locked.ContainsKey($record.Path)){
  $lockedSeen++;$eol=$locked[$record.Path]
  if($record.Attr -cne '-text' -or $record.Index -cne $eol -or $record.Work -cne $eol){$lockedBad.Add($record.Path+'['+$record.Attr+'|i/'+$record.Index+'|w/'+$record.Work+']')}
  continue
 }
 if($record.Path.EndsWith('.md') -or ($record.Index -ceq '-text' -and $record.Attr -ceq '-text')){continue}
 $owned.Add($record)
}
if($thirdParty.Count){Assert ($thirdBad.Count -eq 0) ('第三方內容維持 -text 不轉換'+(Format-Offenders $thirdBad))}
if($locked.Count){
 Assert ($lockedSeen -eq $locked.Count) '雜湊綁定資產全部存在於追蹤清單'
 Assert ($lockedBad.Count -eq 0) ('雜湊綁定資產以 -text 鎖定原換行位元組'+(Format-Offenders $lockedBad))
}
$claimed=@{}
foreach($category in $categories){
 $members=@($owned|Where-Object {$_.Path -match $category.Pattern})
 Assert ($members.Count -gt 0) ($category.Name+'列入換行檢查')
 $attrBad=[Collections.Generic.List[string]]::new();$indexBad=[Collections.Generic.List[string]]::new();$bytesBad=[Collections.Generic.List[string]]::new()
 foreach($member in $members){
  $claimed[$member.Path]=$true
  if($member.Attr -cne ('text eol='+$category.Eol)){$attrBad.Add($member.Path+'['+$member.Attr+']')}
  if($member.Index -notin @('lf','none')){$indexBad.Add($member.Path+'[i/'+$member.Index+']')}
  $bytes=[IO.File]::ReadAllBytes((Join-Path $root $member.Path));$bad=$false
  for($i=0;$i -lt $bytes.Length;$i++){
   if($category.Eol -ceq 'lf'){if($bytes[$i] -eq 13){$bad=$true;break}}
   elseif($bytes[$i] -eq 10 -and ($i -eq 0 -or $bytes[$i-1] -ne 13)){$bad=$true;break}
  }
  if($bad){$bytesBad.Add($member.Path)}
 }
 Assert ($attrBad.Count -eq 0) ($category.Name+'宣告 text eol='+$category.Eol+(Format-Offenders $attrBad))
 Assert ($indexBad.Count -eq 0) ($category.Name+'在 Git index 以 LF 正規化儲存'+(Format-Offenders $indexBad))
 Assert ($bytesBad.Count -eq 0) ($category.Name+'在工作樹每行皆為 '+$category.Eol.ToUpperInvariant()+(Format-Offenders $bytesBad))
}
if($checkUncategorized){
 $unclaimed=@($owned|Where-Object {-not $claimed.ContainsKey($_.Path)}|ForEach-Object {$_.Path})
 Assert ($unclaimed.Count -eq 0) ('自有文字檔皆屬已宣告換行的類型'+(Format-Offenders $unclaimed))
}
Write-Host ('PASS: line endings; categories='+$categories.Count+' files='+$claimed.Count+' locked='+$locked.Count)
