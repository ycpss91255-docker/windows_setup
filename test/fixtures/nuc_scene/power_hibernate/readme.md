# 電源休眠現場重放固件說明

用途：`test/powershell/integration/power_hibernate_scene_replay_tests.ps1` 以 NUC8 實機擷取的資料重放第 03 模組在「休眠仍啟用」現場狀態下的行為。固件只供測試讀取，不是部署資料。

| 固件 | 內容 | 來源 | 來源 SHA256 | 擷取時間（+08:00） | 固件 SHA256 |
|---|---|---|---|---|---|
| `powercfg_a_before.txt` | 套用前 `powercfg /a` 原始輸出 | 階段測試「套用前」記錄的 `powercfg /a` 區段 | `6586D158DF70C7C30FCEEBE7EA4ABEAEE740BC42F162F3DD35B97E460A9E6C63` | 2026-11-22 21:37:43 | `241275201E258BC86657FD7FF8C551B9F02D513D14E2C55A190DC0C1CDD5EFA0` |
| `power_registry_before.txt` | 套用前登錄值與 `hiberfil.sys` 區段 | 同上檔案的「HibernateEnabled etc」「hiberfil.sys」兩區段 | 同上 | 2026-11-22 21:37:43 | `0D5630193BC0DA976107A07B1E0E6FD6D55A63C131806A2E7EF620F0830FC6BA` |
| `powercfg_a_after.txt` | 套用後 `powercfg /a` 原始輸出 | 階段測試「套用後」記錄的 `powercfg /a` 區段 | `3646B81E1944B0EBAF53AF30F2CD8A0DEDA1EFFF170F32EB0BFD1272A9A76620` | 2026-11-22 21:40:09 | `B0CF33D2C8688CD6AA9ABDA0BDC234FF35D00A61AB1342A5E5DB3EC7DC6EA725` |
| `power_registry_after.txt` | 套用後登錄值與 `hiberfil.sys` 區段 | 同上檔案對應區段 | 同上 | 2026-11-22 21:40:09 | `993A98183FE9468AFD9E86F1F9BAFF3F22542B24CCA5E2A22120E2A27B6B4152` |
| `scene_sub_sleep_query.txt` | 第一現場舊版模組寫下的（原檔名 `Power-Before-20261122-165757.txt`） `powercfg /query SCHEME_CURRENT SUB_SLEEP` 輸出 | 第一現場唯讀快照的工具包 `modules\power` 內檔案 | `17DA6FE6602012967C544A6CDD5E39EADD00A02FEB697EEBB7E686ECB3D3AEF3` | 2026-11-22 16:57:58 | 同來源（位元組原樣複製） |
| `scene_standby_hibernate_idle_query.txt` | 第一現場舊版模組寫下的（原檔名 `Power-After.txt`） `STANDBYIDLE` 與 `HIBERNATEIDLE` 查詢輸出（兩段相連） | 同上 | `16526F8DDA5966738F2D848AF2E8D62B72CEFE9EC8193DE3918735DC9A1BFF6D` | 2026-11-22 16:57:58 | 同來源（位元組原樣複製） |

## 切片規則

「區段」指記錄檔中兩個 `===== 名稱 =====` 標題之間的原文行，不含標題；只轉為 UTF-8 BOM 與 CRLF（與來源檔相同），不改動任何數值。兩個 `scene_*.txt` 為位元組原樣複製（改名是因為 `.gitignore` 排除 `*-After.txt` 等每機紀錄檔名）。

## 去識別

這些固件的內容不含使用者名稱、電腦名、SID、IP 或私人路徑，因此沒有替換；電源配置 GUID 是 Windows 內建值。擷取記錄中的電腦名與 SID 只在 `Power-Result.json`，該檔不納入固件。

## 沒有擷取到的資料

- 登錄值型別（`GetValueKind`）與機碼值名稱清單（`GetValueNames`）：測試依 `Get-ItemProperty` 輸出推定，空白視為該值不存在；套用前的值型別未知，測試沒有讀取它。
- 套用後 `HibernateEnabled` 的型別：測試中的假 `powercfg /hibernate off` 把它設為 `DWord`，依據是實機執行後 `Power-Result.json` 回報 `Success=true`，而判定式要求 `DWord`；這是推定，不是擷取。
- `powercfg /hibernate off` 的原始輸出與退出碼：實機只有整體 Apply 退出碼，假指令因此不輸出文字、退出碼為 0。
- `hiberfil.sys` 是否存在：實機以 Windows PowerShell 5.1 的 `Test-Path` 擷取到 False，但 5.1 的 `Test-Path`／`Get-Item` 對系統鎖定的檔案一律回報不存在，這個值不能當成檔案不存在的證據。測試因此不斷言休眠檔，並以空的暫存目錄代替系統磁碟。須改用 `[IO.File]::Exists` 或目錄列舉補擷取。
- 休眠檔移除：套用前後的檔案狀態都未知，因此這份固件不能證明休眠檔已移除。

以上缺口列入「要從 NUC 唯讀補擷取」清單，補上實際資料前不得手編。
