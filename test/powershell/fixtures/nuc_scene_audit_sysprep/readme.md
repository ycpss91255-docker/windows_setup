# 現場重放 fixture：稽核模式 Sysprep 對話框擋住 Init（#481）

用途：`test/powershell/unit/init_sysprep_dialog_tests.ps1` 重放乾淨安裝後進入稽核模式，在內建 Administrator 桌面以系統管理員身分執行 `init.cmd`，因稽核模式自動開啟的「系統準備工具」（sysprep.exe）對話框仍在同工作階段，路由被判為 `RejectUnknownSetupState`，且只顯示「狀態未知」不說明原因的問題。

## 欄位來源

- `UnfixedMessage`：未修版（main `bfdccab4`）在現場顯示的錯誤原文。
- `ModeFactsAfterClose`：手動關閉 Sysprep 對話框後，以唯讀方式執行 `Get-SetupInitPreparationFacts` 讀到的值，照原值保留；`SetupInProgress` 當時未記錄，不列入。
- `ImageState`、`IsAdministrator`、`DesktopOwned`：同一次唯讀診斷讀到的值；關閉前後 ImageState 相同。
- `RouteAfterClose`：同一次診斷 `Get-InitRoute` 的回傳值。
- `Sid`：以合成值 `S-1-5-21-1-2-3-500` 取代實際 SID，只保留內建 Administrator 的 `-500` 結尾。

## 推定（非擷取）

- 關閉前的狀態沒有完整擷取，只確認當時同工作階段有 `sysprep.exe`。測試以關閉後的事實加上 `SetupProcessInSession=True`、同工作階段安裝程序名稱只有 `sysprep.exe` 重建；其他欄位在關閉前後不會因關閉對話框改變。
- 對話框的程序識別碼未擷取，測試使用合成值。
- 自動關閉以視窗關閉要求（等同按「取消」）進行，尚未在實機驗證；測試只以模擬確認關閉成功與失敗兩種流程。

## 限制

- 結果只代表該台電腦在該次系統狀態，不可直接套用至另一台電腦。
