# 自動登入現場重放資料

來源為一臺實機的唯讀擷取，對應 #343 與 PR #356。不含任何密碼或 LSA 機密內容；LSA 只擷取「是否存在」。

| 檔案 | 來源 | 來源 SHA256 | 擷取時間（+08:00） |
| --- | --- | --- | --- |
| `winlogon_first_scene.reg.txt` | 現場快照 `registry/winlogon.txt` 的 Winlogon 主機碼，子機碼未收錄 | `1fac508c0387d4d0a76ea9a97ed87797901012614865453665c562ba4d18c27a` | 2026-11-22 20:25（檔案時間） |
| `stage_before.excerpt.txt` | 階段測試 `before/before.out` 的 Winlogon 段，加 `before/before_lsa.out` 全文 | `92fc749aba8ccd60ac94a2ca547b6d9734f4f732989c7dfa33219b0438644d25`、`78413e1714ca21256b555e4c9170836a7cf35399edef48b4009843227dfa8996` | 2026-11-22 22:50 |
| `stage_after_restore.excerpt.txt`、`stage_after_restore_report.json` | `after_restore/after_restore.out` 的 Winlogon、LSA 與結果檔段 | `1ef66bf9060c5b3a113894632b342bda1308739f2f57ed541161ce3685fc6187` | 2026-11-22 22:56 |
| `stage_after_reenable.excerpt.txt` | `after_reenable/after_reenable.out` 的 Winlogon、LSA 與結果檔段 | `675060a85e90edbe67ff82d054a7915c7b146bd8170f98795286347f040f1221` | 2026-11-22 23:31 |

## 去識別

- 帳號名稱改為 `fixture_user`，電腦名稱改為 `FIXTURE-PC`。
- SID 的網域部分改為 `S-1-5-21-1000000001-1000000002-1000000003-`，保留尾碼。現場 `AutoLogonSID` 為 `-1000`、操作帳號為 `-1001`，兩者本來就不同。
- `LastUsedUsername` 的 `defaultuser0` 是 Windows 內建流程名稱，保留原值。
- 其餘型別、值、順序、空值與換行不變。測試執行時只把結果檔的 SID 換成執行測試的帳號。

## 沒有擷取到

- 停用後與重新啟用後的完整 Winlogon 主機碼：只擷取六個值名稱及 `DefaultPassword` 是否存在，因此不含當時的 `AutoLogonSID`、`LastUsedUsername`。
- 現場快照的查詢在遠端遮蔽 `DefaultPassword`；「不存在」的依據是 `before.out` 的值名稱清單。
- 停用後重新開機的登入畫面。
- 未修版在實機上的執行結果。
