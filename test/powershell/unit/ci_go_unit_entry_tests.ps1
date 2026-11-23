#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
. (Join-Path $root 'script/test/ci_tasks.ps1')
Assert ($null -ne (Get-Command Invoke-CIGoUnitTests -ErrorAction SilentlyContinue)) 'PR 階段的 Go 維護工具單元測試有獨立入口'
# 整合測試需要完整的 PowerShell 報告，PR 階段的獨立 Go 工作不跑；其餘套件逐一執行，沒有任何套件時不得回報成功。
$script:listed=@('example.invalid/windows_setup/script/test/mergecheck','example.invalid/windows_setup/test/go/integration','example.invalid/windows_setup/test/go/unit','example.invalid/windows_setup/test/go/integration_helpers')
$script:calls=New-Object Collections.Generic.List[object]
function Invoke-CINative{param([string]$File,[string[]]$Arguments=@())
 $script:calls.Add([pscustomobject]@{File=$File;Arguments=@($Arguments)})
 if($Arguments[0] -ceq 'list'){return $script:listed}
}
Invoke-CIGoUnitTests
$test=@($script:calls|Where-Object {$_.Arguments[0] -ceq 'test'})
Assert ($test.Count -eq 1 -and $test[0].File -ceq 'go.exe') '以 go test 執行一次'
$arguments=$test[0].Arguments
Assert (($arguments -contains '-mod=vendor') -and ($arguments -contains '-count=1')) '使用 vendor 並停用測試快取'
Assert (($arguments -contains 'example.invalid/windows_setup/script/test/mergecheck') -and ($arguments -contains 'example.invalid/windows_setup/test/go/unit')) '執行非整合測試的套件'
Assert (@($arguments|Where-Object {$_ -clike '*/test/go/integration'}).Count -eq 0) '排除 test/go/integration'
Assert ($arguments -contains 'example.invalid/windows_setup/test/go/integration_helpers') '名稱只是前綴相同的套件不被誤排除'
$script:listed=@('example.invalid/windows_setup/test/go/integration')
$empty='';try{Invoke-CIGoUnitTests}catch{$empty=$_.Exception.Message}
Assert ($empty -like '*沒有*') '排除整合測試後沒有任何套件時失敗，不回報成功'
