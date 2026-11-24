# 重灌後現場擷取（NUC8，沒有驅動包）

六個 Code 28 裝置（8086:1911、8086:A127、8086:A121、8086:A123、8086:A131、ACPI INT3515）的原樣擷取，只做去識別（InstanceId 的機器專屬段 `11583659` 改為 `00000000`），屬性、型別與順序不改。

| 檔案 | 來源 | 來源 SHA256 |
|---|---|---|
| problem_devices.json | 基準擷取（無驅動）problem_devices.json | E9BDA2724E58FBF0A23D6B2F8E71D344B557AD4FCB68E0301958F03D5E4B1AE1 |
| pnp_present.json | 同上 pnp_devices.json（六個裝置） | BF1F0C75CA02C12FDFCDD8323CF3F296FD8F813D9556B587BD0F37D3C5ABD242 |
| cim_signed_driver.json | 同上 cim_signed_driver.json（六個裝置） | 825FB4B66C7FE4EC9DA24B56730E02158763057CB448106E47BF0326E386EB1D |
| live_native_shape.json | 同一台機器同一狀態的唯讀原生查詢（未修版輸出） | 958380FEE45279E5E1F51B9FE5F84FF9D29DE9C878005DC08B2030CCA5757DE3 |
| live_plans.json | 同上，未修版與修正版的計畫狀態 | 52C87664E891EC5B77B7767EBD82F0F747C86578EA932A05B72ED94C8B1B2996（修正版） |

- 基準擷取只列出有值的屬性；沒有值的屬性（DriverInfPath、CompatibleIds）由 `live_native_shape.json` 補回原生形狀：型別 Empty、沒有 Data 成員。
- JSON 只做排版（縮排、LF、去行尾空白），內容不變。
- 限制：基準擷取沒有健康裝置的屬性，因此複合 A127 目標只檢查「不再誤判」，不逐項比對現場結果。