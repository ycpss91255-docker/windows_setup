# NUC8 Code 28 現場擷取（去識別）

供 `test/powershell/unit/driver_code28_scene_replay_tests.ps1` 重放 #350 的現場症狀。檔案是 NUC8 實機唯讀擷取的 `Format-List`／JSON 原文片段，只保留四個異常裝置（8086:1911、8086:A127、8086:A131、ACPI INT3515）的記錄，欄位、型別、空值與順序不變。

| fixture | 來源檔 | 來源 SHA256 | 片段 |
| --- | --- | --- | --- |
| `pnp_properties.excerpt.txt` | `drivers/pnp_properties.txt`（`Get-PnpDeviceProperty` 輸出） | `66E92A588D504603F733A0A59FDE3168EABCED7207655E41B9571BDC3D99817D` | 四個裝置各四個屬性（HardwareIds、CompatibleIds、ProblemCode、DriverInfPath）共 16 筆 |
| `pnp_present.excerpt.txt` | `drivers/pnp_present.txt`（`Get-PnpDevice -PresentOnly`） | `581036BB15EDB159B2418712631D264DEC3B40B09DEAE9F18C5F64B771381D55` | 四筆 |
| `win32_pnpsigneddriver.excerpt.txt` | `drivers/win32_pnpsigneddriver.txt`（`Win32_PnPSignedDriver`） | `FAC199A28CF8A299190CCA5408E3CBEA9724F3DED432F8722ECE62F65F9B05CD` | 四筆，驅動欄位全空 |
| `driver_result.targets.excerpt.json` | `files/modules/drivers/driver_logs/driver_result.json` | `CDAFE94530718110321789F99AD09EADC4790C5245E04E71AF621913C66EB724` | 五個目標物件，皆為 `Unverified：目標驅動狀態屬性讀取失敗` |

## 擷取時間
- 屬性、裝置與已簽驅動輸出：2026-11-22 約 20:25–20:30（UTC+8），安裝階段結束後、未重開機。
- `driver_result.json`：`CompletedAt` 為 2026-11-22T17:01:21+08:00。

## 去識別
- 裝置 InstanceId 後段的機器相依字串 `11583659` 全部換成 `00000000`。
- 電腦名稱換成 `FIXTURE-PC`。
- 其他內容（硬體 ID、SUBSYS、驅動版本、狀態、型別）保留原文。

## 沒有擷取到的資料
- `Format-List` 對空值只印空白，無法區分 `$null` 與空字串；重放時一律視為 `$null`。
- 沒有驅動套件即時來源的 manifest；重放使用 repo 的 `drivers/nuc8i7hvk_hnk/manifest.json`，其 INF 路徑與現場 `driver_result.json` 的 `Windows10-x64` 路徑不同，只以硬體 ID 比對目標。
- 沒有同一時間的 `pnputil` 輸出片段；本重放只涵蓋計畫階段，不涵蓋安裝後讀回。
