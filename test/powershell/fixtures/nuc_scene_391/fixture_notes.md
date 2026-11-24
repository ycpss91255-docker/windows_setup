# #391 現場重放 fixture 說明

來源為 NUC8 手動 GUI 驗收（2026-11-22）的唯讀擷取，供 `icons_language_scene_replay_tests.ps1` 重放。

| fixture | 來源檔 | 來源 SHA256 | 擷取時間（+08:00） |
|---|---|---|---|
| `target_user_desktop_key.reg.txt` | `registry/theme.txt` 中該使用者 `Control Panel\Desktop` 及其 `LanguageConfigurationPending`、`MuiCached` 三段（第 203–249、281–282、313–314 行） | `DFF1532D901723599FABF8993A84768ED925022B957B3E2C473E1C201A8F270B` | 2026-11-22 20:25 |
| `icons_verify_stdout.txt` | `gui2/icons.stdout.txt`（從 SSH 執行 `desktop_icon_layout.ps1 -Mode Verify` 的標準輸出，原樣位元組） | `299D1D815B6BEA5CE8BC056526E690101A18583846A5DD50698000DE3B788CC8` | 2026-11-22 21:05 |

## 去識別
- 使用者 SID 換成 `S-1-5-21-1000-2000-3000-1001`。檔內沒有使用者名稱、電腦名、IP。
- 刪除 `TranscodedImageCache`（二進位值內含本機路徑，與語言判斷無關）。其餘值、型別、順序與原檔相同，換行維持 CRLF。

## 現場事實
- 該使用者的 `Control Panel\Desktop` 沒有 `PreferredUILanguages` 值，只有 `PreviousPreferredUILanguages` 與 `PreferredUILanguagesPending`（皆 `zh-TW`）；`MuiCached\MachinePreferredUILanguages` 為 `zh-TW`。
- 從 SSH 執行 Verify 的輸出為「[略過] 目前桌面排列範本僅適用繁體中文，未套用座標。」，狀態 `Skipped`。

## 沒有擷取到（不可編造，需從 NUC 唯讀補擷取）
1. SSH session 內 `(Get-UICulture).Name` 的實際值。重放中以 `en-US` 代表「非 zh-TW」，這是依輸出推論，不是實測值。
2. SSH session 的 `whoami /user` 與是否為提權 token；SSH 端 `Get-SetupEntryUserUILanguage` 實際回傳（Name、Source、Reason）。
3. 同一 SSH session 讀取 `HKU\<SID>\Control Panel\Desktop` 的 `PreferredUILanguages` 是否存在、`MuiCached` 實際值（本檔來自 reg query，非該 session）。
4. 修正版在 NUC 上從 SSH 執行 `-Mode Verify` 的實際輸出（實機對照）。
