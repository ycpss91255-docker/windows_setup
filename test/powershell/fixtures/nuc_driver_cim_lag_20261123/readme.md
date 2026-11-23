# NUC 驅動安裝後 CIM 列延遲現場資料（2026-11-23，Thermal A131）

用途：重放「`pnputil /add-driver /install` 之後，`Win32_PnPSignedDriver` 的列要 60～120 秒才出現」以及「移除驅動後 CIM 留幽靈列」兩個現場現象。

## 來源（本機擷取檔，不在 Git 內）

| 內容 | 來源 | 說明 |
| --- | --- | --- |
| `afterInstall` | `drivers2/372` 證據 `capture/ts_install_*/timeseries.json` | 安裝後 t+0、2、5、10、20、30、60、120 秒；同一程序與全新程序兩組取樣，兩組內容逐項相同（`freshProcessSameAsInProcess`） |
| `afterRemoveGhost` | `capture/code28_*/03_removed.json` | `pnputil /delete-driver /uninstall /force` 後約 10 秒；之後 6 分鐘以上同樣存在 |
| `SignerName` | 結束快照 `end.pnputil_enum_drivers.txt` 的 oem27.inf | `pnputil /enum-drivers` 的簽署者名稱 |

證據目錄與各檔 SHA256 在維護者本機的 `SHA256SUMS.txt`；原始日誌不上傳。

## 去識別與裁切

- InstanceId 最後一段實例位址 `3&11583659&0&A2` 改為 `3&FIXTURE&0&A2`；主機名、使用者名稱、時間戳不保留。
- 只保留讀回邏輯使用的欄位（CIM 版本／提供者／IsSigned、DEVPKEY 版本／提供者／INF 路徑／ProblemCode、裝置狀態）；CIM 的 DeviceName 在擷取時有編碼亂碼，且程式不使用，未保留。
- `null` 保持 `null`（CIM 列存在但版本、提供者、IsSigned 皆為空）。

## 沒有擷取到

- 安裝後 60～120 秒之間 CIM 列何時出現（只知道 t+60 沒有、t+120 有）。
- 其他 NUC 目標（GMM、UART2、TPS659xx、藍牙、MEI）的同類時間序列；只在 Thermal 一個裝置上取得。
