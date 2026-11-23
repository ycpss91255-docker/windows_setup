# NUC8 桌面圖示現場資料（去識別）

| 檔案 | 來源 | 來源 SHA256 | 擷取時間 |
|---|---|---|---|
| setup_run_load_result.json | 快照 `files/programdata/windows_setup_gui/icons/<RunId>/data/Icons-Result.json` | 4d8680e889afd9d336243ded964f525037f5e51d990d35938e33d693fcf4ab33 | 2026-11-22 17:02 Setup 第 19 階段 Load 結果 |
| stage_before_verify_result.json | 階段測試 `gui/before/icons_verify.json` | 8249bf58c76bd969e9873f25be0864896d64df90c84b77150db940f9cf02687b | 2026-11-22 22:35 Verify（未套用） |

去識別：`UserSID`→`S-1-5-21-0-0-0-1001`、`Computer`→`TESTPC`、`RunId`→全零 GUID；座標、順序、欄位與編碼（UTF-8 BOM）未改。

## 沒擷取到的資料
- Setup 第 19 階段 Load **之前**的圖示座標（唯一的 Load 前快照缺互動桌面 ListView 座標），所以無法重放「為何被推到 198」。
- 兩次擷取的格線間距不同：Setup 結果的列為 y=2、100、198（間距 98），階段測試的列為 y=2、102、202（間距 100）；原因未知。
- 同一台機器後續 Load（22:35，未修版）自 202 套用即成功讀回 (14,102)，與 Setup 當次失敗不同；故無法由現有資料重現當次失敗。

## 需從 NUC 唯讀補擷取
1. 全新安裝後、Setup 第 19 階段 Load 前的互動桌面 ListView 座標（`Capture()` 的 Name/X/Y 與 AutoArrange）。
2. 當下的 DPI、顯示縮放與圖示間距設定，以解釋 98 與 100 的差異。
