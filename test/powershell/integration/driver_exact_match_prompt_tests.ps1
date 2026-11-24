#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path $env:TEMP ('windows_setup_driver_exact_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force|Out-Null
$count=0
$st=@{Board='';Boards=$null;Answers=$null;Prompts=@()}
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++}
function Get-CimInstance {param($ClassName,$ErrorAction);if($st.Boards){foreach($b in $st.Boards){[pscustomobject]@{Product=$b}}}else{[pscustomobject]@{Product=$st.Board}}}
function Get-NetConnectionProfile {param($ErrorAction);[pscustomobject]@{IPv4Connectivity='Disconnected';IPv6Connectivity='NoTraffic'}}
function Read-Host {param($Prompt);$st.Prompts+=[string]$Prompt;if(-not $st.Answers.Count){throw ('Unexpected prompt: '+$Prompt)};return $st.Answers.Dequeue()}
. (Join-Path $root 'core/hardware.ps1')
$profileFile=Join-Path $root 'drivers/nuc8i7hvk_hnk/profile.json'
$profileHash=(Get-FileHash -LiteralPath $profileFile -Algorithm SHA256).Hash
# Each scenario gets its own PackageRoot so the adjacent package is isolated.
function New-Scenario([string]$Name,[string[]]$Boards=@('NUC8i7HVB','NUC8i7HNB'),[switch]$NoPackageJson,[switch]$BadPackageJson,[switch]$BadHash){
 $base=Join-Path $fixture $Name
 $pkgRoot=Join-Path $base 'windows_setup';New-Item -ItemType Directory -Path $pkgRoot -Force|Out-Null
 $payload=Join-Path $base 'windows_driver_packages\nuc8';New-Item -ItemType Directory -Path $payload -Force|Out-Null
 $manifest=@(foreach($n in @('Chipset.zip','SerialIO.zip','UCM.zip','GFX-Radeon.zip')){$f=Join-Path $payload $n;[IO.File]::WriteAllText($f,'fixture');@{File=$n;SHA256=(Get-FileHash $f -Algorithm SHA256).Hash}})
 if($BadHash){$manifest[0].SHA256=('0'*64)}
 $manifest|ConvertTo-Json|Set-Content (Join-Path $payload 'manifest.json') -Encoding UTF8
 if(-not $NoPackageJson){
  if($BadPackageJson){[IO.File]::WriteAllText((Join-Path $payload 'package.json'),'{ broken',[Text.UTF8Encoding]::new($false))}
  else{@{SchemaVersion=2;ProfileId='nuc8i7hvk_hnk';Architecture='x64';ProfileSHA256=$profileHash;SupportedBoards=$Boards}|ConvertTo-Json|Set-Content (Join-Path $payload 'package.json') -Encoding UTF8}
 }
 $inc=Join-Path $payload 'drivers\nuc8i7hvk_hnk';New-Item -ItemType Directory -Path $inc -Force|Out-Null
 Copy-Item -LiteralPath $profileFile -Destination (Join-Path $inc 'profile.json')
 [pscustomobject]@{PackageRoot=$pkgRoot;Payload=$payload}
}
function Invoke-Request($Scenario,[string]$Board,[string[]]$Answers){
 $st.Board=$Board;$st.Prompts=@();$st.Answers=New-Object 'Collections.Generic.Queue[string]'
 foreach($a in $Answers){$st.Answers.Enqueue($a)}
 $all=@(Select-SetupDriverRequest -PackageRoot $Scenario.PackageRoot -Interactive $true *>&1)
 $script:r=@($all|Where-Object {$_.PSObject.Properties['DriverPackagePath']})|Select-Object -Last 1
 $script:out=(@($all|Where-Object {-not $_.PSObject.Properties['DriverPackagePath']})|ForEach-Object {[string]$_}) -join "`n"
}
$exact=New-Scenario 'exact'
Invoke-Request $exact 'NUC8i7HVB' @('')
Assert ($r.DriverPackagePath -eq $exact.Payload) '完全對上時 Enter 安裝（選用相鄰包）'
Assert ($st.Prompts.Count -eq 1 -and $st.Prompts[0] -match 'NUC8i7HVB' -and $st.Prompts[0] -match 'Enter') '完全對上的提示寫出偵測到的型號並說明 Enter 安裝'
Invoke-Request $exact 'NUC8i7HNB' @('y')
Assert ($r.DriverPackagePath -eq $exact.Payload) '完全對上時 Y 安裝'
Invoke-Request $exact 'NUC8i7HVB' @('n')
Assert (-not $r.DriverPackagePath) '完全對上時 N 略過'
Assert ($out -match '本次不安裝驅動' -and $out -match 'windows\.cmd' -and $out -match 'AfterRestart') '略過時當場顯示本次不安裝驅動與補裝方法'
Invoke-Request $exact 'NUC8i7HVB' @('p',$exact.Payload)
Assert ($r.DriverPackagePath -eq $exact.Payload) '完全對上時 P 可指定其他位置'
Invoke-Request $exact 'NUC8i7HVB' @('x','?','')
Assert ($r.DriverPackagePath -eq $exact.Payload -and $st.Prompts.Count -eq 3) '無法辨識的輸入不當作同意，重新詢問'
Invoke-Request $exact 'NUC8i7HVB' @('x','n')
Assert (-not $r.DriverPackagePath -and $st.Prompts.Count -eq 2) '無法辨識輸入後仍可 N 略過'
# Not in the package list: Enter skips, Y is rejected by the existing identity check.
$notListed=New-Scenario 'notlisted' -Boards @('NUC8i7HNB')
Invoke-Request $notListed 'NUC8i7HVB' @('')
Assert (-not $r.DriverPackagePath -and $out -match '本次不安裝驅動') '型號不在包清單時 Enter 略過'
Assert ($st.Prompts[0] -notmatch 'Enter 或 Y') '型號不在包清單時提示不得宣稱 Enter 安裝'
Assert ($out -match '不在' -or $st.Prompts[0] -match '不在') '型號不在包清單時用白話說明哪裡沒對上'
Invoke-Request $notListed 'NUC8i7HVB' @('y','')
Assert (-not $r.DriverPackagePath -and $st.Prompts.Count -eq 2 -and $out -match '驅動包未通過檢查') '型號不在包清單時 Y 仍被既有檢查拒絕'
# Partial, prefix or differently cased board names must not match.
$partial=New-Scenario 'partial' -Boards @('NUC8i7HVB2','NUC8i7HNB')
Invoke-Request $partial 'NUC8i7HVB' @('')
Assert (-not $r.DriverPackagePath) '型號只有部分字串相同時 Enter 略過'
$prefix=New-Scenario 'prefix' -Boards @('NUC8i7HV','NUC8i7HNB')
Invoke-Request $prefix 'NUC8i7HVB' @('')
Assert (-not $r.DriverPackagePath) '型號只是前綴相同時 Enter 略過'
$lower=New-Scenario 'lower' -Boards @('nuc8i7hvb','nuc8i7hnb')
Invoke-Request $lower 'NUC8i7HVB' @('')
Assert (-not $r.DriverPackagePath) '大小寫不同時不算完全對上，Enter 略過'
# Manually confirmed board: Enter skips, Y still works.
Invoke-Request $exact '' @('1','NUC8i7HVB','')
Assert (-not $r.DriverPackagePath -and ($out -match '手動' -or $st.Prompts[-1] -match '手動')) '手動確認型號 Enter 略過並說明不是自動偵測'
Invoke-Request $exact '' @('1','NUC8i7HVB','y')
Assert ($r.DriverPackagePath -eq $exact.Payload -and $r.ConfirmedBoard -eq 'NUC8i7HVB') '手動確認型號仍可用 Y 明確選用'
# Unknown / multiple boards never reach a one-key install.
Invoke-Request $exact '' @('g')
Assert (-not $r.DriverPackagePath) '未知型號略過'
$st.Boards=@('NUC8i7HVB','NUC8i7HNB')
Invoke-Request $exact 'NUC8i7HVB' @('')
Assert (-not $r.DriverPackagePath -and $r.Hardware.DetectionStatus -eq 'Ambiguous') '多塊主機板時 Enter 不安裝'
$st.Boards=$null
# Identity file missing or corrupt.
$missing=New-Scenario 'nopkg' -NoPackageJson
Invoke-Request $missing 'NUC8i7HVB' @('')
Assert (-not $r.DriverPackagePath -and $out -match '本次不安裝驅動') 'package.json 缺少時 Enter 略過'
$broken=New-Scenario 'brokenpkg' -BadPackageJson
Invoke-Request $broken 'NUC8i7HVB' @('')
Assert (-not $r.DriverPackagePath) 'package.json 損毀時 Enter 略過'
# Exact match but SHA256 mismatch must not install; the existing retry flow follows.
$badHash=New-Scenario 'badhash' -BadHash
Invoke-Request $badHash 'NUC8i7HVB' @('','')
Assert (-not $r.DriverPackagePath -and $out -match '驅動包未通過檢查' -and $out -match 'SHA256') '完全對上但 SHA256 不符時不安裝並走重新輸入流程'
# Non-interactive and explicit-path behaviour is unchanged.
$st.Board='NUC8i7HVB';$st.Prompts=@();$st.Answers=New-Object 'Collections.Generic.Queue[string]'
$r=Select-SetupDriverRequest -PackageRoot $exact.PackageRoot -Interactive $false
Assert (-not $r.DriverPackagePath -and $st.Prompts.Count -eq 0) '非互動模式不詢問也不安裝'
$r=Select-SetupDriverRequest -PackageRoot $exact.PackageRoot -Interactive $false -DriverPackagePath $exact.Payload -PathSpecified
Assert ($r.DriverPackagePath -eq $exact.Payload -and $st.Prompts.Count -eq 0) '指定 DriverPackagePath 時不詢問，仍驗證後使用'
$nothing=Join-Path $fixture 'elsewhere\deep';New-Item -ItemType Directory -Path $nothing -Force|Out-Null
Invoke-Request ([pscustomobject]@{PackageRoot=$nothing}) 'NUC8i7HVB' @('')
Assert (-not $r.DriverPackagePath -and $st.Prompts.Count -eq 1 -and $st.Prompts[0] -match '找不到相鄰') '找不到相鄰包時 Enter 略過行為不變'
Assert ($count -gt 0) '至少有一個斷言'
Write-Host ('ALL PASS: '+$count+' driver exact-match prompt assertions; no host changes.')
Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
