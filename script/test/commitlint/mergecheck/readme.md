# 同次新增合併提交檢查

此維護工具使用 `grandfather.json` 的固定主線 anchor 與採用時已公開 PR 的精確 head，可達的既有提交集合對所有事件共用；不根據提交日期、目前 PR head 或執行者輸入擴大豁免。鎖定清單來自兩輪 GitHub API 取樣與人工審核，非原子快照；任何更動需重新審核並更新固定摘要。這是經程式碼審查的防錯措施，不是防止能修改工作流程或來源者的安全邊界。

PR 檢查事件的 base、head、實際 merge checkout 與 tree，僅檢查 PR head 的新可達提交，不把 GitHub 合成 checkout 當作使用者提交。main push 必須有可信 before／after 祖先關係。tag 須解析至實際 checkout、位於固定 anchor 之後且為已核對 main 的祖先；anchor 之前的歷史 tag 不由此新檢查回填，直接拒絕。只支援 main 的 workflow_dispatch；`merge_group` 事件須有 `merge_group` 物件：base_ref 為 `refs/heads/main`、head_sha 等於實際 checkout 與 run SHA、workflow ref 等於事件 head_ref 且位於 `gh-readonly-queue/main/`，並且固定 anchor 為 base 的祖先、base 為 group head 的祖先；範圍為 base 之後新增的提交，其中合併提交依佇列合併標題規則檢查。其他未知事件明確拒絕。來源缺失、淺歷史、baseline 物件無法取得、事件身分矛盾均失敗，不縮小驗證集合。

CI 使用完整 checkout，從固定 GitHub HTTPS 來源取得 manifest 每個精確 SHA 所需物件，不跟隨目前 PR 分支；若上游不再提供某物件會停止並需維護者審查。此工具不修改 branch protection、標籤或既有歷史。原有可選 `commit-msg` hook 的單筆訊息檢查保持獨立。
採用此檢查前已合併至 main 的 `fb7a85067449f316055fe4867318d2037e560455` 標題不符新規則；僅 tag 與 main 手動執行的歷史掃描對該單一提交免除標題檢查。它不是豁免根，祖先與後續提交仍按既定範圍檢查；PR 與 main push 不套用此例外。

合併佇列以 GitHub 固定格式產生的 merge commit（標題 `Merge pull request #<n> from <本倉庫 owner>/<head 分支>`）可通過：正文第一行須為中文「領域：結果」PR 標題，第二個父提交必須等於該 PR 目前的 head，且 head 倉庫與分支須與標題一致；以 GitHub API 查詢 PR head，查詢失敗一律拒絕。其他英文合併標題仍拒絕，人工合併的「合併：…」規則與既有歷史豁免不變。

PR 階段另接受 GitHub「更新分支」同步主線產生的合併提交，標題須完全為 `Merge branch 'main' into <本 PR 的 head 分支>`（head 分支取自事件，且 head 倉庫須為本倉庫）。結構核對：第一個父提交須是 PR 分支原有的提交（位於本次檢查範圍內）；第二個父提交須是事件 base 的祖先，即當時主線已有的提交；tree 須等於兩父提交以 `git merge-tree --write-tree` 無衝突合併的結果，故合併本身不夾帶額外內容。有衝突、需人工解決的同步不符合此條件，須以「合併：…」標題人工合併。此例外套用於 pull_request、merge_group、main push 事件，以及 tag 與 main 手動執行的歷史掃描。

merge_group 與 main push 事件的 ref（`gh-readonly-queue/…`、main）無法對應 PR 分支，且範圍可含多個 PR，因此範圍內同步合併的分支名稱改由範圍內的佇列合併提交背書：該提交標題 `Merge pull request #<n> from <本倉庫 owner>/<分支>` 已以 GitHub API 核對 PR head 倉庫為本倉庫，同步合併的標題分支須等於它，且須可由其第二父提交（PR head）到達，再套用同樣的結構核對。範圍內沒有對應佇列合併提交、或該 PR head 來自 fork，一律拒絕。main push 以事件 before 作為 base，其餘與佇列相同；未經佇列直接推送到 main 的同步合併沒有背書，仍拒絕。此作法不新增網路查詢，並沿用既有 API 核對。

tag 與 main 手動執行的歷史掃描自固定 anchor 起，同步合併的第二父提交也在掃描範圍內，因此沿已核對 main 的第一父鏈找出引入該同步合併的那一步主線，以該步的第一父提交為 before，重做與 main push 相同的核對（該步的佇列合併會再查詢一次 API）。第一父鏈不取標籤所在提交，PR 歷史內自造的佇列合併不能充當主線。若一次 push 併入多個佇列合併，歷史掃描以每一步分別核對，較 push 的整段範圍嚴格：同步合併的第一父提交若只屬於同批較早的 PR 會被拒絕。此作法不豁免任何其他不符標題規則的既有合併提交。
