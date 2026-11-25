# NUC8 現場重放 fixture：工作列驗收的畫面證據（#353）

用途：`test/powershell/unit/taskbar_acceptance_scene_replay_tests.ps1` 以 NUC8 實機取得的總驗收輸出重放「未修版把設定讀回寫成釘選登入後套用通過，修正版不寫」的差異，並核對重開後 `Acceptance-Result.json` 的 `TaskbarEvidence`。

## 檔案與來源

| fixture | 來源 | 擷取日期 |
|---|---|---|
| `taskbar_checks_unfixed_scene.json` | 未修版（`main` 的 `core/verification_library.ps1` 與 `core/after_restart_library.ps1`）對照執行的 `Verification-Result.json`，只取工作列相關項目的 Name、Status、Passed、Detail | 2026-11-25 |
| `taskbar_checks_fixed_scene.json` | 修正版（PR 的兩個檔案）同一對照執行的同欄位項目 | 2026-11-25 |
| `taskbar_evidence_v5_restart_scene.json` | v5 候選包重開後實機總驗收 `Acceptance-Result.json` 的 `TaskbarEvidence` 整段 | 2026-11-25 |

原始檔的 SHA256（取自 NUC 對照執行；原檔含主機名與使用者識別，不進倉庫）：未修版 `Verification-Result.json` `ecb0e2e29aaf5b06f82be785c8df36f944daebeca5a3c34f22ccf94ab7b7c67a`、修正版 `Verification-Result.json` `d94eada8b98bdb87dc94373148c8358c460e7a3a3da6dc48a5be2bdbb2c79436`。三個 fixture 本身的 SHA256 以 `git hash-object` 為準。

## 對照方式（唯讀）

- 同一份 v5 工具包複本各一份，只替換 `core/verification_library.ps1` 與 `core/after_restart_library.ps1`：未修版換成 `main` 版，修正版換成 PR 版；兩份複本其餘檔案相同。
- 以複本中的 `Complete-SetupAfterRestartAcceptance` 走完整總驗收彙整（`verify_only.ps1` 的檢查全部實際執行），但 `%ProgramData%` 導向複本旁的沙箱目錄，並把 GUI worker 換成替身（見限制）。未註冊排程、未寫 RunOnce、未修改實際設定；複本與沙箱於執行後刪除。
- 結果：未修版寫出「釘選登入後套用」且 Passed，驗收結果沒有 `TaskbarEvidence`；修正版沒有該項目，驗收結果含 `TaskbarEvidence`，`VisualStatus=Unknown`，兩項政策讀回皆 Passed。

## 去識別

三個 fixture 只含檢查名稱、狀態、通過旗標與說明文字，不含電腦名稱、使用者識別或路徑；來源檔的識別欄位未取用。

## 限制與假設

- GUI worker 以替身取代：Taskbar 角色回傳 `Configured=true`、`BindingMatches=true`、`Success=true`、`RequiresNextSignIn=false`、`Status=Confirmed`，與 v5 重開後實機 `TaskbarEvidence` 記錄的讀回一致；其他角色（顯示、主題、桌面圖示等）未執行，對應檢查在對照中為未通過或略過，所以對照執行的整體 `Success` 為 false，與本修正無關。因此「畫面是否真的套用」沒有被觀察。
- 對照只證明驗收輸出的差異：未修版在沒有畫面證據時聲稱釘選已套用，修正版不聲稱。不證明工作列實際畫面、也不證明登入曾發生；實際畫面未由真螢幕目視驗證。
- 結果只代表該台 NUC8 在該次系統狀態與工具包版本；不可直接套用至另一台電腦。
