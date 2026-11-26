# NUC8 現場重放 fixture：未偵測到螢幕（#448）

用途：`test/powershell/unit/gui_no_display_tests.ps1` 以 NUC8 實機擷取重放螢幕與圖示驗收在沒有螢幕時只回報 worker 退出碼的問題，以及修正版在縮放不是 100% 時顯示錯誤解析度的問題。

## 兩個現場型態

| 型態 | 擷取日期 | 內容 |
|---|---|---|
| `640x480` | 2026-11-25 | 重新開機後沒有目前存在的螢幕，主畫面 640x480、縮放 100%，Windows 螢幕數 1 |
| `1920x1080 縮放 150%` | 2026-11-26 | 沒有目前存在的螢幕，顯示模式 1920x1080、縮放 150%，Windows 螢幕數 1 |

兩者都沒有目前存在的 PnP 螢幕裝置、worker 排程退出碼 1、未修版入口只顯示退出碼；解析度與縮放不同，不是同一型態。是否有實體接線未知。

## 欄位來源

- `UnfixedDisplayResult`、`UnfixedIconsResult`：未修版 worker 在受保護目錄寫出的結果檔，移除 `RunId`、`UserSID`、`Computer` 三個識別欄位，其餘照原值。`640x480` 由當時的候選包產生，`1920x1080 縮放 150%` 由 main `cc02f514` 產生。
- `Video`：`Win32_VideoController` 目前解析度。`PnpDevices`：`Get-PnpDevice` 螢幕類別的存在旗標與狀態，不含裝置名稱與識別碼。
- `CimMonitors`：`Win32_PnPEntity` 螢幕類別的筆數；`640x480` 當時未擷取（`null`），測試以 0 筆處理。
- `PrimaryWidth`、`PrimaryHeight`、`MonitorCount`：互動桌面以 Windows Forms 讀到的值。`1920x1080 縮放 150%` 讀到的是 DPI 換算後的 1280x720。`640x480` 以系統度量擷取，縮放 100%，兩者相同。
- `DesktopIcons`：互動桌面的四個系統圖示座標；`640x480` 未擷取（`null`），測試沿用範本座標。
- `FixedMessageBeforeResolutionFix`：修正版 `e157edc0` 在同一現場的訊息，解析度寫成 1280×720。

## 實機對照（唯讀）

main `cc02f514` 與修正版 `e157edc0` 兩份工具包只差 `core/gui_stage_library.ps1` 與 `core/verification_library.ps1`，各執行螢幕與圖示單獨驗收及總驗收。總驗收的 `%ProgramData%` 導向沙箱，GUI worker 走真實受保護目錄。兩版前後共四次讀回（螢幕數、解析度、圖示座標、範本雜湊、殘留排程）完全相同。總驗收 40 項只有「實際解析度與縮放」「四個圖示的實際排列座標」由未通過改為未驗證，整體都不通過。

## 限制

- 只包含沒有螢幕的對照；接回螢幕後的對照尚未執行。
- 解析度顯示修正（改讀 `Video`）尚未在實機重跑。
- 查詢失敗、沒有原因等情境為合成案例。
- 結果只代表該台電腦在該次系統狀態，不可直接套用至另一台電腦。
