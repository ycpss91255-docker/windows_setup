#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
# 結構取自 pnputil /enum-drivers /devices /format xml 的實機輸出（nuc_scene_snapshot 的 pnputil_devices_xml）
$script:xml=''
function Get-SetupDriverEnumDriversXmlText {if($script:xml -eq 'THROW'){throw '原生盤點失敗'};return $script:xml}
$script:xml=@'
<?xml version="1.0" encoding="utf-8"?>
<PnpUtil Version="10.0.26200" Command="/enum-drivers /devices /format xml">
    <Driver DriverName="oem11.inf"><OriginalName>amdfendr.inf</OriginalName><SignerName>Microsoft Windows Hardware Compatibility Publisher</SignerName></Driver>
    <Driver DriverName="oem27.inf"><OriginalName>sunrisepoint-hsystemthermal.inf</OriginalName><SignerName>Microsoft Windows Hardware Compatibility Publisher</SignerName></Driver>
    <Driver DriverName="oem28.inf"><OriginalName>x.inf</OriginalName><SignerName>Contoso Test Publisher</SignerName></Driver>
    <Driver DriverName="oem29.inf"><OriginalName>y.inf</OriginalName></Driver>
</PnpUtil>
'@
Assert ((Get-SetupDriverPublishedSigner -PublishedName 'oem27.inf') -eq 'Microsoft Windows Hardware Compatibility Publisher') '依發布名稱取得簽署者'
Assert ((Get-SetupDriverPublishedSigner -PublishedName 'OEM27.INF') -eq 'Microsoft Windows Hardware Compatibility Publisher') '發布名稱不分大小寫'
Assert ((Get-SetupDriverPublishedSigner -PublishedName 'oem28.inf') -eq 'Contoso Test Publisher') '回傳實際簽署者以供規則比對'
Assert ($null -eq (Get-SetupDriverPublishedSigner -PublishedName 'oem99.inf')) '找不到發布名稱回傳 null'
Assert ($null -eq (Get-SetupDriverPublishedSigner -PublishedName 'oem29.inf')) '沒有 SignerName 回傳 null'
$script:xml='THROW'
Assert ($null -eq (Get-SetupDriverPublishedSigner -PublishedName 'oem27.inf')) '原生盤點失敗回傳 null'
$script:xml='<not xml'
Assert ($null -eq (Get-SetupDriverPublishedSigner -PublishedName 'oem27.inf')) 'XML 格式錯誤回傳 null'
$script:xml='<!DOCTYPE x [<!ENTITY a "b">]><PnpUtil><Driver DriverName="oem27.inf"><SignerName>Microsoft Windows Hardware Compatibility Publisher</SignerName></Driver></PnpUtil>'
Assert ($null -eq (Get-SetupDriverPublishedSigner -PublishedName 'oem27.inf')) '含 DTD 的 XML 一律拒絕'

# 真正的 Get-SetupDriverEnumDriversXmlText：以假的 pnputil 腳本驗證成功與失敗退出碼
Remove-Item function:Get-SetupDriverEnumDriversXmlText
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
$fake=Join-Path ([IO.Path]::GetTempPath()) ('fake_pnputil_'+[guid]::NewGuid().ToString('N')+'.cmd')
$script:fakeExit=0
function Get-SetupDriverPnpTool {return $fake}
try{
 [IO.File]::WriteAllText($fake,"@echo off`r`necho ^<PnpUtil^>^<Driver DriverName=`"oem27.inf`"^>^<SignerName^>Microsoft Windows Hardware Compatibility Publisher^</SignerName^>^</Driver^>^</PnpUtil^>`r`nexit /b 0`r`n",[Text.Encoding]::ASCII)
 Assert ((Get-SetupDriverPublishedSigner -PublishedName 'oem27.inf') -eq 'Microsoft Windows Hardware Compatibility Publisher') '原生工具成功時解析輸出'
 [IO.File]::WriteAllText($fake,"@echo off`r`necho failed`r`nexit /b 5`r`n",[Text.Encoding]::ASCII)
 Assert ($null -eq (Get-SetupDriverPublishedSigner -PublishedName 'oem27.inf')) '原生工具退出碼非 0 時回傳 null'
}finally{Remove-Item -LiteralPath $fake -ErrorAction SilentlyContinue}
Write-Output 'driver published signer test passed'
