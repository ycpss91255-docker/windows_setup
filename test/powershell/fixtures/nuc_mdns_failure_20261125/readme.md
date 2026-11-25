# nuc_mdns_failure_20261125

2026-11-25 在 NUC 測試複本，以未修正的原生註冊程式（#452 之前）搭配測試用主機名稱 `TESTMDNS357` 實測 `Begin` 失敗：

- 沒有 #360 診斷的 main 程式：狀態與例外都是 PowerShell 外層文字 `Exception calling "Begin" with "3" argument(s): ...`，內層原生階段只在外層訊息尾端。
- 加上 #360 診斷後：狀態錯誤為固定分類 `callback-schema`。
- 用 #452 的修正原生再執行同流程，測試名稱註冊成功並可由另一台主機查到，測試後已撤銷。

`WrappedChinese` 依 issue 描述的中文系統外層文字撰寫，未在實機以中文系統量測。檔內沒有主機名稱、IP 或帳號。
