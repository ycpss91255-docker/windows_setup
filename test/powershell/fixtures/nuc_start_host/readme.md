# NUC8 Start Host 暫停／消失現場紀錄

- 來源：NUC8 實機，2026-11-23 23:34–23:44（開始選單 #393／#398 調查），輸出由 `nuc_stage_tests\startmenu\after\` 取得。
  - `product_path_rehearsal.out`：來源 `s7.txt`，SHA256 `e7e5778c7b3d6f6082a48c2ea801c931c77a14b48074755e6bdb9e9cdc065e0e`。情境 A：結束 Host 後系統不再重生，匯出回 0x80070490；以 AppX 啟用 `FullTrustApp` 後立即匯出成功（pins=0）。情境 B：Host 閒置 30 秒，24 個以上執行緒全為 Suspended，匯出逾時 20 秒；再次啟用後立即匯出成功。
  - `aged_host_activation.out`：來源 `s4.txt`，SHA256 `e5eb2efab846e2a07e99869587e88d10c8a83a47c6f755bf1066efa2847348b6`。存活約 150 秒的 Host 執行緒全部 Suspended、匯出逾時；啟用後同一個程序恢復（Suspended 轉為 Wait/UserRequest），匯出 1.2 秒成功。
- 去識別：檔案未含使用者名稱、電腦名、SID、IP 或私人路徑，內容逐位元組保留。程序識別碼與時間為當時的實測值。AppX 伺服器名稱為系統固定字串。
- 沒有擷取到：自然重開自動登入後的實際 Host 狀態（需要使用者重開機，由 `readback_start_host.ps1` 補）；Host 反覆當機（0xc000027b）時啟用是否能讓 Host 長期存活；啟用後匯出若遇 0x80070490 的重試時序（本次兩種情境皆在第一次重試成功）。
- 重放測試只重現這些紀錄的狀態與結果；它證明程式依紀錄行為，不證明其他機器或版本。
