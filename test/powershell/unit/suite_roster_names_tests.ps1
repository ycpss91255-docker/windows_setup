#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
# 執行器以 BaseName.Replace('_tests','') 取 suite 名稱；原生證據封裝（native_stage.go）以 ^...([a-z0-9_]+)_tests\.ps1$ 從 git ls-files 推導。兩者必須對每個檔案得到同一個名稱，
# 否則所有 suite 都通過，最後封裝仍以「native source roster contains missing, duplicate or unsuccessful suite」失敗。
$goPattern='^test/powershell/(unit|integration)/([a-z0-9_]+)_tests\.ps1$'
$tracked=@(& git.exe -C $root ls-files 'test/powershell/unit' 'test/powershell/integration' 2>$null)
Assert ($LASTEXITCODE -eq 0 -and $tracked.Count -gt 0) '能列出受版本控制的測試檔'
$mismatch=@()
foreach($path in $tracked){
 $relative=$path.Replace('\','/')
 $match=[regex]::Match($relative,$goPattern)
 if(-not $match.Success){$mismatch+=('不符合原生證據封裝的檔名規則：'+$relative);continue}
 $layer=$(if($match.Groups[1].Value -ceq 'unit'){'Unit'}else{'Integration'})
 $viaGo=$layer+'.'+$match.Groups[2].Value
 $viaRunner=$layer+'.'+([IO.Path]::GetFileNameWithoutExtension($relative)).Replace('_tests','')
 if($viaGo -cne $viaRunner){$mismatch+=($relative+'：封裝推導 '+$viaGo+'，執行器推導 '+$viaRunner)}
}
Assert ($mismatch.Count -eq 0) ('每個測試檔在執行器與原生證據封裝得到相同的 suite 名稱：'+($mismatch -join '；'))
