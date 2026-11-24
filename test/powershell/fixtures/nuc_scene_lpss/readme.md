# NUC 現場快照：Serial IO／LPSS 裝置節錄

供 `test/powershell/unit/driver_naming_only_scene_replay_tests.ps1` 重放 #364 的現場狀態。

| 檔案 | 來源檔（唯讀快照 drivers/） | 來源 SHA256 | 取得命令 |
| --- | --- | --- | --- |
| pnp_present.txt | pnp_present.txt | 581036BB15EDB159B2418712631D264DEC3B40B09DEAE9F18C5F64B771381D55 | `Get-PnpDevice -PresentOnly \| Format-List *` |
| win32_pnpsigneddriver.txt | win32_pnpsigneddriver.txt | FAC199A28CF8A299190CCA5408E3CBEA9724F3DED432F8722ECE62F65F9B05CD | `Get-CimInstance Win32_PnPSignedDriver \| Format-List *` |
| pnp_properties.txt | pnp_properties.txt | 66E92A588D504603F733A0A59FDE3168EABCED7207655E41B9571BDC3D99817D | `Get-PnpDeviceProperty` 的 HardwareIds、CompatibleIds、ProblemCode、DriverInfPath |

擷取日期 2026-11-22（唯讀 SSH 擷取）。

## 節錄範圍

只保留硬體 ID 為 `DEV_A127`、`DEV_A160`、`DEV_A161`、`DEV_A162`、`ACPI\INT345D` 的五個裝置區塊，區塊內容、欄位順序與空值維持原樣。
CRLF 與 Format-List 的斷行維持原樣；僅在檔首加 UTF-8 BOM 以便 Windows PowerShell 5.1 讀取。

## 去識別

- 電腦名稱改為 `FIXTURE-PC`。
- 裝置執行個體識別碼的後段雜湊 `11583659` 改為 `00000000`。
- 硬體 ID、驅動版本、供應商、INF 名稱保留。

## 快照沒有的資料

- Format-List 會把清單截成四項並以 `...` 結尾：CompatibleIds 只有前四項；HardwareIds 本身不超過四項，完整。
- win32_pnpsigneddriver.txt 內含擷取當時編碼已變成替代字元的本地化文字（DeviceName、Location、DriverDate），原樣保留，驗證邏輯不使用。
- 驅動包 `nuc8/manifest.json` 本身不在快照；測試以 repo 清單去除宣告式標記後的 SHA256 對照已發行資產的 ManifestSHA256，證明兩者相同。
- 沒有 Windows 內建物件的完整 `Win32_OperatingSystem`；測試固定組建 26200（與 pnputil 版本 10.0.26200 一致）。
