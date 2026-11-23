# 電源紀錄位置現場重放固件說明

用途：`test/powershell/integration/power_record_scene_replay_tests.ps1` 以第一現場舊版第 03 模組實際寫下的兩個紀錄檔當作假 `powercfg` 的輸出，重放 `Power-Before`／`Power-After` 的寫入位置。固件只供測試讀取，不是部署資料。

| 固件 | 內容 | 原檔名 | 來源 | 來源 SHA256 | 擷取時間（+08:00） |
|---|---|---|---|---|---|
| `scene_sub_sleep_query.txt` | `powercfg /query SCHEME_CURRENT SUB_SLEEP` 輸出 | `Power-Before-20261122-165757.txt` | 第一現場唯讀快照的工具包 `modules\power` 內檔案（舊版模組寫在工具包資料夾，這正是現場症狀） | `17DA6FE6602012967C544A6CDD5E39EADD00A02FEB697EEBB7E686ECB3D3AEF3` | 2026-11-22 16:57:58 |
| `scene_standby_hibernate_idle_query.txt` | `STANDBYIDLE` 與 `HIBERNATEIDLE` 查詢輸出（兩段相連） | `Power-After.txt` | 同上 | `16526F8DDA5966738F2D848AF2E8D62B72CEFE9EC8193DE3918735DC9A1BFF6D` | 2026-11-22 16:57:58 |

## 處理方式

兩個固件為位元組原樣複製（SHA256 與來源相同）。改名是因為 `.gitignore` 排除 `*-After.txt` 等每機紀錄檔名。測試用假 `powercfg` 依參數個數回傳這些內容，並要求修正後寫到 `%ProgramData%\NUC8-Setup` 的 `Power-Before-*.txt`、`Power-After.txt` 與固件位元組相同。

## 去識別

內容不含使用者名稱、電腦名、SID、IP 或私人路徑，因此沒有替換；電源配置 GUID 是 Windows 內建值。

## 沒有擷取到的資料

- 兩個固件各自對應哪一段 `powercfg` 輸出，是依檔案內容與模組指令推定（`Power-After.txt` 在第二段 `HIBERNATEIDLE` 前切開）；實機沒有逐指令保存原始輸出。
- 舊版模組在其他電腦或其他時間的輸出沒有擷取，測試只代表這一台機器在這個時間點。