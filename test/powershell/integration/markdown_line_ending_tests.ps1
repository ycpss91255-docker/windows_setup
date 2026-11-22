#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
# Owned Markdown documents use Windows CRLF; upstream third-party and vendored content keep their original bytes.
$upstream='^(modules/debloat/win11debloat|vendor)/'
$tracked=@(& git -C $root -c core.quotePath=false ls-files -- '*.md')
if($LASTEXITCODE -ne 0 -or -not $tracked.Count){throw '無法列出已追蹤的 Markdown 文件。'}
$owned=@($tracked|Where-Object {$_ -notmatch $upstream})
Assert ($owned.Count -gt 0) '找到自有 Markdown 文件'
foreach($path in $owned){
 $text=[IO.File]::ReadAllText((Join-Path $root $path))
 $bare=[regex]::Matches($text,'(?<!\r)\n').Count
 Assert ($bare -eq 0) ('自有 Markdown 只使用 CRLF：'+$path+'（單獨 LF '+$bare+' 處）')
 $attributes=(@(& git -C $root check-attr text eol -- $path) -join "`n")
 Assert ($attributes -match ': text: set' -and $attributes -match ': eol: crlf') ('Git 屬性固定自有 Markdown 為 CRLF：'+$path)
}
foreach($path in @($tracked|Where-Object {$_ -match $upstream})){
 $attributes=(@(& git -C $root check-attr text -- $path) -join "`n")
 Assert ($attributes -match ': text: unset') ('第三方 Markdown 保留上游位元組：'+$path)
}
Write-Host ('ALL PASS: '+$count+' line ending assertions; source inspection only.')
