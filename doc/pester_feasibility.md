# Pester 測試遷移第一階段評估

本評估針對 main `42d76507dad390f23be975e2e74a188f96ceae03`，只研究可行性，不遷移正式測試或變更品質門檻。建議暫不批准全面遷移：代表性接線可行，但仍缺同範圍覆蓋率對照、失敗訊息及維護工時實測，無法證明目前值得支付遷移成本。後續若要試點，應另行審查單一小批次，保留既有驗收與回退。

## 1. 版本與環境

議題最初提到內建 3.4 與 Pester 5；現行 `script/test/powershell_coverage.ps1` 已固定 Pester 6.0.0 及 Gallery SHA512，使用 Windows PowerShell 5.1 子程序。它支援明確提供已預備的套件，缺失或雜湊錯誤時拒絕回退；一般 CI 可用固定官方來源取得並驗證。離線／全新環境必須事先以可信管道提供符合固定 SHA512 的套件，不能假設機器已安裝模組。Windows container 與 windows-2022 均須各自具備相同套件與支援的 PowerShell，並由正式工作核對；本評估未在新機或容器重新取得或執行套件。下載暫態問題另見 #252，不在本評估修改。

## 2. 隔離與代表性探針

使用已與現有固定 SHA512 相符的本機 Pester 6.0.0 套件，在私有 TEMP 解壓，以專案現有的 `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass` 程序選項執行，未改系統原則。三個 Pester `It` 探針通過、0 失敗：

- 子程序執行原 `uac_helpers_tests.ps1`，其假登錄 stub 與自有暫存資料維持隔離；探針同時檢查子程序 exit 0 與全部 typed `@@ASSERT@@` 為真。
- 以 `Add-Type` 建立只回傳常數的惰性假 CLR 類型，檢查 Pester 中可呼叫。這沒有編譯或執行實際 Win32 程式。
- 子程序執行 `neutral_paths_tests.ps1`，在自有 TEMP 建立檔案 fixture；檢查 exit 0 及 21 個 typed assertion 全部為真。

探針只是代表性橋接：每個既有 suite 被包成一個 `It`，原始 assertion 數量不等於 Pester 測試數；它不是把各斷言改寫成 Pester，也未驗證所有 mock 作用域、共享 CLR、短路徑與跨程序情境。需用各 suite 的真實負例逐項驗證，保留隔離邊界。探針檔案、已解壓套件與執行環境位於當次私有 TEMP，並非正式測試或可攜交付物。

## 3. 可替代範圍

Pester 可提供測試結構、斷言、mock 與測試結果／覆蓋率輸出；它已在 collector 的 `Invoke-Pester` 中執行 wrapper 並收集 coverage，並非目前完全沒有使用 Pester。將自訂 assertion 改寫後可評估減少部分解析與重複 helper，但只有代表性橋接結果，尚無可刪除程式清單。

仍需獨立處理完整來源清單與排除、固定版本與雜湊、worker 身分、run／attempt 綁定、分片完整性與合併、C#／PowerShell runtime 整合、公開 artifact 脫敏、requirements gate、portal 及 Release 證據。Pester 結果輸出不自動提供上述專案契約；不能直接刪除 `repo_coverage_tool`、`powershell_shards`、`ci_quality_summary`、portal 或 `requirements_gate`。

## 4. 覆蓋率準確度

現行 PS5.1 worker 已啟用 Pester 6 coverage，保存 executed/missed 命令位置；專案另以完整來源、命令 span 與四片證據合併，計算 `FullyCoveredCommandStartLines` 並與 managed runtime 彙整。Pester 的原始命令計數、單次 Cobertura 及最終合併後的行指標不可直接當作同一分母。補充同源實測：在私有 TEMP 的合成 `sample.ps1` 同一行放 true／false 分支，單一 Pester suite 只呼叫 true；使用固定 SHA512 Pester 6 與實際 `powershell_coverage.ps1` collector、Windows PowerShell 5.1.26100.10068，exit 0。相同來源與同一次 suite 的 Pester 命令資料為 4 個命中、2 個未命中；Pester 原始 Cobertura 宣告 2/2 行命中，專案 collector 的正規化 `coverage.xml` 為 1/2 行完全命中：分支所在第 2 行因另有兩個未命中命令而列未覆蓋，第 3 行命中。這是單 worker 合成樣本、非完整 runtime 或跨片驗收；不能推算整體差距或等價。仍須以完整來源與已知正負例核對分母、跨片 union 和跨行命令，再維持原門檻。

## 5. 遷移與回退

目前 main 有 258 個 `unit`／`integration` 的 `*_tests.ps1`（而非議題提出時約 239）；這是檔案數，並非測試或 assertion 數。若後續獲准試點，先選一個副作用受控的 suite，逐項對照真實正負例及 typed assertion，再按隔離方式分批；新舊並存期間各自保留可驗證結果，避免同一行為重複計數或遺漏。每批的失敗與覆蓋範圍不降低，且保留原套件與輸出讀取；回退以既有 merge 歷史及原 CI 路徑恢復，不能刪舊測試後才尋找補救。分批工時尚未量測。

## 6. 維護成本與決策

main 42d 的靜態盤點（`git ls-files` 範圍內各檔 `splitlines()`，含測試與非程式檔，互斥資料夾除特別註明外不重疊）：`script/test/repo_coverage/` 17 檔 2,429 行，負責來源、標準化與 worker/shard 驗證；`script/test/repo_coverage_tool/` 16 檔 3,590 行，含 CLI 與測試；`script/test/powershell_coverage*` 2 檔 243 行，負責 collector 與 shard 入口；`script/test/ci_quality_summary.ps1` 1 檔 34 行，彙總；`script/test/requirements_gate/` 2 檔 117 行，執行需求閘門；`script/report/` 8 檔 606 行，負責報表與入口。三個 `powershell_shards.go`／測試檔的 317、575、569 行已包含在前兩個資料夾，不可重複加總。此為受限路徑快照，未涵蓋所有呼叫端或 portal 相依工具，不代表可刪數量。

目前不能量化可刪程式行數或預期節省：instrumentation、證據綁定與公共報表仍有獨立責任，且三個探針沒有測定轉寫、維護或故障診斷成本。以測試數、斷言數、未命中負例與真實執行時間記錄一個受控試點，再比較持續維護成本；未完成該比較前，全面遷移是否划算結論為「證據不足」，不是已證明不可行。無需為本文件製造紅燈。
