#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path $env:TEMP ('network_entry_'+[guid]::NewGuid().ToString('N'));$core=Join-Path $fixture 'core';[void][IO.Directory]::CreateDirectory($core)
$utf=New-Object Text.UTF8Encoding($true)
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
foreach($name in @('start_windows.ps1','network_preflight_library.ps1')){Copy-Item -LiteralPath (Join-Path $root ('core/'+$name)) -Destination $core}
[IO.File]::WriteAllText((Join-Path $core 'hardware.ps1'),'function Test-SetupInteractiveHost {return $false}; function Select-SetupDriverRequest {param($PackageRoot,$DriverPackagePath,$PathSpecified,$ConfirmedBoard,$ConfirmationComputer,$Interactive);$global:events+="selection";return @{DriverPackagePath=$DriverPackagePath;ConfirmedBoard=$ConfirmedBoard;ConfirmationComputer=$ConfirmationComputer}}',$utf)
[IO.File]::WriteAllText((Join-Path $core 'configure_setup.ps1'),'param($DriverPackagePath,$ConfirmedBoard,$ConfirmationComputer,[switch]$NonInteractive);$global:events+="configure:"+$DriverPackagePath',$utf)
[IO.File]::WriteAllText((Join-Path $core 'verify_only.ps1'),'$global:events+="verify"',$utf)
[IO.File]::WriteAllText((Join-Path $core 'verify_after_restart.ps1'),'$global:events+="after"',$utf)
function Get-NetConnectionProfile {param($ErrorAction);$global:events+='network';if($global:failRead){throw 'synthetic'};return [pscustomobject]@{IPv4Connectivity='Disconnected';IPv6Connectivity='NoTraffic'}}
$entry=Join-Path $core 'start_windows.ps1'
foreach($fail in @($false,$true)){$global:events=@();$global:failRead=$fail;& $entry -NonInteractive -DriverPackagePath 'fixture-package';Assert (($global:events -join ',') -ceq 'network,selection,configure:fixture-package') '離線或查詢失敗先提示仍轉交本機包與設定'}
foreach($arg in @('VerifyOnly','AfterRestart')){$global:events=@();$params=@{};$params[$arg]=$true;& $entry @params;Assert (($global:events -join ',') -ceq $(if($arg -eq 'VerifyOnly'){'verify'}else{'after'})) '既有驗證模式不查網或啟動設定'}
foreach($path in @('modules/ssh/apply_ssh_settings.cmd','modules/updates/install_windows_updates.cmd')){Assert (Test-Path -LiteralPath (Join-Path $root $path) -PathType Leaf) ('提示重試入口存在 '+$path)}
$ssh=[IO.File]::ReadAllText((Join-Path $root 'modules/ssh/apply_ssh_settings.cmd'));$update=[IO.File]::ReadAllText((Join-Path $root 'modules/updates/install_windows_updates.cmd'));$map=Get-Content -LiteralPath (Join-Path $root 'core/paths.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($ssh -match '-Module "Apply-SSHSettings"' -and $map.'Apply-SSHSettings.ps1' -ceq 'modules/ssh/apply_ssh_settings.ps1') 'SSH 重試入口映射至原獨立階段'
Assert ($update -match '-Module "Install-WindowsUpdates"' -and $map.'Install-WindowsUpdates.ps1' -ceq 'modules/updates/install_windows_updates.ps1') '更新重試入口映射至原獨立階段'