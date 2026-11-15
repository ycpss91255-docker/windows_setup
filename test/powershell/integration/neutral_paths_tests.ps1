#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path $env:TEMP ('neutral_paths_'+[guid]::NewGuid().ToString('N'))
$core=Join-Path $fixture 'core';[void][IO.Directory]::CreateDirectory($core)
Copy-Item -LiteralPath (Join-Path $root 'core/paths.ps1'),(Join-Path $root 'core/paths.json') -Destination $core
[IO.File]::WriteAllText((Join-Path $core 'hardware.ps1'),'# inert fixture',[Text.UTF8Encoding]::new($true))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
. (Join-Path $core 'paths.ps1')
foreach($name in @('Resolve-SetupPath','Initialize-SetupReports','Resolve-SetupModuleName')){Assert ([bool](Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) ('中性介面存在：'+$name)}
foreach($name in @('apply_uac_settings.ps1','Apply-UACSettings.ps1','Setup-Result.json','CustomHostsSync/config.json','Win11Debloat/config.json')){
 Assert ((Resolve-SetupPath $name) -ceq (Resolve-NucPath $name)) ('新舊路徑結果一致：'+$name)
}
Assert ((Resolve-SetupPath 'Apply-UACSettings.ps1') -ceq (Join-Path $fixture 'modules/uac/apply_uac_settings.ps1')) '舊別名解析至原實體'
Assert ((Resolve-SetupPath 'Setup-Result.json') -ceq (Join-Path $fixture 'reports/Setup-Result.json')) '未登錄報告維持 reports'
Assert ((Resolve-SetupPath 'CustomHostsSync/config.json') -ceq (Join-Path $fixture 'modules/ssh/custom_hosts_sync/config.json')) '允許的 CustomHostsSync 子路徑維持位置'
foreach($name in @('unregistered.ps1','unknown/path','outside.cmd')){
 $a='';$b='';try{Resolve-SetupPath $name|Out-Null}catch{$a=$_.Exception.Message};try{Resolve-NucPath $name|Out-Null}catch{$b=$_.Exception.Message}
 Assert ($a -and $a -ceq $b) ('新舊介面相同拒絕：'+$name)
}
Assert ((Resolve-SetupModuleName 'Apply-UACSettings.ps1') -ceq 'apply_uac_settings.ps1') '舊續跑模組名稱正規化'
foreach($name in @('Apply-UACSettings.ps1','unregistered.ps1')){Assert ((Resolve-SetupModuleName $name) -ceq (Resolve-NucModuleName $name)) ('續跑模組名稱一致：'+$name)}
Initialize-SetupReports;Initialize-NucReports
Assert (Test-Path -LiteralPath (Join-Path $fixture 'reports') -PathType Container) '兩個初始化入口可重複使用自有報告目錄'
. (Join-Path $core 'paths.ps1')
Assert ((Resolve-SetupPath 'Setup-Result.json') -ceq (Resolve-NucPath 'Setup-Result.json')) '重複載入後仍有一致報告路徑'
& {function Resolve-NucPath {param($Name) 'old-stub:'+ $Name};Assert ((Resolve-NucPath 'fixture') -ceq 'old-stub:fixture') '舊呼叫端作用域替身仍可覆寫'}
Assert ((Resolve-NucPath 'Setup-Result.json') -ceq (Join-Path $fixture 'reports/Setup-Result.json')) '子作用域替身不改外層舊介面'
