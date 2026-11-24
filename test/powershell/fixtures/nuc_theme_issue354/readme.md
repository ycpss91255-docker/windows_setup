# Issue 354 NUC 現場資料（去識別）

| 檔案 | 來源 | 來源 SHA256 | 擷取時間 |
| --- | --- | --- | --- |
| theme_apply_autohidden_result.json | 現場快照 `files/programdata/windows_setup_gui/theme/<RunId>/data/Theme-Result.json` | d1926f73b2265164390b848e178bfe39361b62877d755a3d410054eb528f3d7a | 2026-11-22 17:02（套用） |
| theme_verify_visible_result.json | 現場快照 `gui3/files/theme/<RunId>/data/Theme-Verification.json` | c72ab8974634592c92def347820a77b20eff12c423e79ba4c5fe1bda109bc948 | 2026-11-22 21:13（VerifyOnly） |

去識別：UserSID 換成 `S-1-5-21-1-2-3-1001`，Computer 換成 `fixture-computer`；其餘欄位、型別、順序、BOM 與縮排不動。

未擷取到：沒有現場畫面截圖，也沒有使用者目視觀察與上述 RunId 的對應；`TaskbarRGB` 只在可見那次有值（33,33,33）。「使用者看到工作列沒換色」是哪一次執行，未確認。
