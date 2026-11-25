# NUC 驅動子元件延後確認資料（2026-11-25）

重灌後驅動階段（00:04:54～00:08:59）有 5 個目標被判為 Unverified：UWPPair、amdwin、amdfendr、MEWMIProv（目前已載入驅動未確認簽章，版本空白），以及 amdocl（必需子元件尚未枚舉）。

## 資料來源與實測

- 驅動階段 `driver_result.json` 與主控台輸出：5 個目標的 Reason 皆沒有「安裝後已等待 N 秒」，代表沒有進入等待路徑。
- 結束時 `pnputil /enum-drivers` 已有這 5 個 INF（oem16、oem17、oem18、oem21、oem31），簽署者皆為 Microsoft Windows Hardware Compatibility Publisher；同一時刻 `Win32_PnPSignedDriver` 一列也沒有。
- 重灌後約 6.5 分鐘（00:11:24）的唯讀核對：5 個裝置的 DEVPKEY、CIM 列與簽章都正常。
- 每約 2 秒取樣的主要 PCI／ACPI／I2C／UART 裝置（共 12 台，DEVPKEY 版本於驅動階段改變）：在最長 275 秒的觀察窗內，沒有任何一台的 CIM 列追上 DEVPKEY。取樣不含 SWD 子元件。

## 去識別

InstanceId 尾端的機器專屬雜湊改為 `FIXTURE`；`ROOT\AMDLOG\0000` 為固定編號、不含機器資訊。`OlderVersion` 是為「需要安裝」案例合成的較舊版本，非實測。

## 缺少的資料

- 子元件本身的 CIM／DEVPKEY 時間序列（取樣器未含 SWD）。測試裡「延後出現」的秒數是合成值，不是實測延遲。
- 因此結論只有：該次執行中 CIM 追上的時間大於 275 秒，且多於共用等待額度 150 秒；不能由此推論實際延遲上限。
