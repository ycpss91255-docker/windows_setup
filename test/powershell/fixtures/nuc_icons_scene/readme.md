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

## 目標格被佔用的現場對照（第二批）

| 檔案 | 來源 | 來源 SHA256 | 擷取時間 |
|---|---|---|---|
| occupied_target_cell_scene.json | 階段測試 `gui2/after/d_icons375_run3_p375.txt` 的步驟 3、5、8（run2 同結果） | 5ccb2e18b3ffc2000afbe6472315fb7e8c251c0c329126a76c38b5f8ad0f772f（run2：4af63ff43700fd98941591dace75268984ddaaa491895570343e7b841a0e7c50） | 2026-11-23 21:21～21:24 |

- `Initial`：把「網路」放在 (14,100) 佔用「本機」目標格後的畫面（步驟 3）；`AfterUnfixedLoad`：未修版 Load 後（步驟 5，本機留在 (14,198)）；`AfterFixedLoad`：含補套用的套件 Load 後（步驟 8，四個圖示回範本）。
- 去識別／整理：來源以主控台編碼讀出，圖示名稱為亂碼，依 Index 0～3 還原為本機、網路、資源回收筒、控制台；其餘欄位只擷取 Name／X／Y，Width／Height 取自來源。座標未改。
- 此情境為人工佔格，**重現不了** #351 當次 Setup 的失敗（run1 以近似座標 (14,198) 起始，未修版 Load 就通過，因貼齊成 100）。#351 原始現場根因仍不確定。
- 補套用次數結果檔無欄位，未量測。
- 格線列為 y=2、100、198（間距 98），系統圖示間距 SM_CX/CYICONSPACING=75、DPI 96；範本 102 與貼齊後 100 的差在容差 ±2 內。
