# NUC8 現場重放 fixture：工作列自動隱藏（#353）

用途：`test/powershell/unit/taskbar_autohide_nuc_scene_replay_tests.ps1` 以這台 NUC8 的實際擷取資料重放「Apply 回報成功，之後 VerifyOnly 讀回 false」的現場症狀。誰把狀態還原的仍然未知，本 fixture 與測試不宣稱已找到。

## 檔案與來源

| fixture | 來源（快照內相對路徑） | 來源 SHA256 | 擷取時間 |
|---|---|---|---|
| `taskbar_apply_scene.json` | `files/programdata/windows_setup_gui/taskbar/<RunId>/data/Taskbar-Result.json` | `7A4D1BB89AB1E1CC0051A902BCECCDC2A27CC9DD739F27C02E1324EEBF3839B8` | 檔內 CheckedAt 2026-11-22 17:02:40（+08:00） |
| `taskbar_verify_scene.json` | `gui3/files/taskbar/<RunId>/data/Taskbar-Verification.json` | `1C36A9AB14E41747A0DA8DE198EFFA8208ADBABAF0E1DB592AB6FB219C1B0962` | 檔內 CheckedAt 2026-11-22 21:12:57（+08:00） |
| `StuckRects3.reg.txt` | `registry/taskbar_shell.txt` 內 `HKCU\...\Explorer\StuckRects3` 的 Settings | 整檔 `ACF2484694B1F7831C60576E9B7AB7EF119C7D3A49BF0129FB27067B10A7707B` | 檔案時間 2026-11-22 20:27:12（+08:00） |

兩個 JSON 因 `.gitignore` 的 `*-Result.json` 規則（每機結果檔不進倉庫）而改名；內容未變，只做去識別。JSON 保留原 BOM、CRLF、欄位順序、型別與空值（例如 `TaskbarDa` 為 null）。`StuckRects3.reg.txt` 的十六進位字串與原擷取逐字相同，只刪掉其他機碼輸出，第 9 位元組為 `02`（未含自動隱藏位元）。

## 去識別

- `UserSID` → `S-1-5-21-1000000000-2000000000-3000000000-1001`
- `Computer` → `NUC-FIXTURE`
- 其餘欄位（RunId、路徑、時間、數值）未改動。

## 重放模型與假設

- 時間順序：17:02 Apply 回報 `AutoHide=true`、`AppBarState=1`；20:27 擷取 StuckRects3 第 9 位元組 `0x02`；21:12 VerifyOnly 讀回 `AutoHide=false`、`AppBarState=0`。
- 測試把「Explorer 重新載入時由 StuckRects3 第 9 位元組位元 0 決定自動隱藏」當成**模型假設**，用來把 Apply 後的狀態接到 Verify 讀回；這個假設沒有被實機證實。
- 測試只主張：Apply 若不寫入持久狀態，則登錄值維持 fixture 的 `0x02`，之後讀回為 false。誰、何時還原了狀態，沒有證據。

## 快照沒有的資料（待 NUC 唯讀補擷取）

1. Apply 完成當下（17:02）的 StuckRects3 Settings 原始位元組；`Taskbar-Before-*.reg` 在 Apply 之前產生，且不含 StuckRects3。
2. 17:02 到 21:12 之間 StuckRects3 的變化時間點（例如最後寫入時間）與前後值。
3. 21:12 VerifyOnly 當下同時刻的 StuckRects3 位元組（現有為 20:27 擷取）。
4. Explorer 行程的啟動時間與重啟次數，以及 Apply 之後是否有 Explorer 重啟或登出登入。
5. 第一階段測試結束時是否有還原自動隱藏的動作與時間。
6. Apply 之後以不同延遲（立即、數秒後）讀 StuckRects3，確認 Windows 11 26200 上 `ABM_SETSTATE` 是否由 Explorer 自行持久化。
7. 全新使用者設定檔上 StuckRects3 是否存在，以及 `Settings` 值長度。
8. 全新使用者首次登入後立即讀 StuckRects3 是否存在及 `Settings` 長度（Apply 在找不到時只回報未持久化，不建立）。
9. 在沒有 StuckRects3 的狀態下 `ABM_SETSTATE` 是否讓 Explorer 建立該機碼。
