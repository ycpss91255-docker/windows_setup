# driver_cache_nuc_listing_20261122.txt 說明

- 來源：NUC8 實機唯讀擷取 `driver_cache_listing.txt`（Get-ChildItem／Get-Acl 摘要）；來源 SHA256 AA491BF31018A2A2E99C87776DD27CF024EF32B7065A77E8916C0D973D9ADE6D；擷取日 2026-11-22（v0.2.6，#355 現場）。
- 欄位：`相對路徑|深度（root=0、本輪目錄=1）|AreAccessRulesProtected|Owner|FileCount`。
- 去識別：本輪 GUID 目錄名依出現順序改為 `lease01`～`lease06`；根目錄路徑省略。其餘目錄名、型別、順序、旗標與擁有者保持原樣。
- 現場事實：1 個根與 6 個本輪目錄受保護；其下 99 個子目錄全部 `AreAccessRulesProtected=False`、擁有者 `BUILTIN\Administrators`，最深為本輪目錄下 5 層。
- 快照沒有擷取到（須從 NUC 唯讀補擷取）：各目錄與檔案實際 DACL 規則（SID、權限、繼承旗標、IsInherited）、檔案的 owner／保護旗標、本輪根目錄與快取父目錄的規則、各層 ACL 的 SDDL。測試中的規則為依 v0.2.6 設計假設，不是現場資料。

- 2026-11-23 補擷取（NUC 唯讀）：子目錄 ACL 為 `O:BAG:<本機群組>D:(A;OICIID;FA;;;SY)(A;OICIID;FA;;;BA)`，子檔為 `(A;ID;FA;;;SY)(A;ID;FA;;;BA)`，與測試使用的 SDDL 一致（群組 SID 已去識別）；105 個子目錄、無重新解析點、無唯讀檔、最長路徑 152 字元。
