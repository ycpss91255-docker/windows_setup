package main

import (
	"fmt"
	"regexp"
	"strings"
)

// syncMergeValid 核對 GitHub「更新分支」在 PR 分支上產生的同步主線合併提交。
// 標題已由呼叫端比對為 `Merge branch 'main' into <PR head 分支>`；此處再要求：
//   - 第一個父提交是 PR 分支原有的提交（位於本次檢查範圍內，不是 base 可達的提交）；
//   - 第二個父提交是事件 base（main 當時）的祖先，即當時主線已有的提交；
//   - tree 等於兩個父提交無衝突合併的結果，合併本身不夾帶額外內容。
//     有衝突、需人工解決的同步不符合此條件，須以「合併：…」標題的人工合併處理。
func syncMergeValid(repo, id, first, second, base string, inRange map[string]bool) error {
	if !commitOID.MatchString(first) || !commitOID.MatchString(second) || !commitOID.MatchString(base) {
		return fmt.Errorf("new merge commit has invalid title: %s", id)
	}
	if !inRange[first] || inRange[second] || !isAncestor(repo, second, base) {
		return fmt.Errorf("sync merge commit parents are not a PR commit and a main ancestor: %s", id)
	}
	tree, err := graphGit(repo, "rev-parse", id+"^{tree}")
	if err != nil {
		return err
	}
	expected, err := graphGit(repo, "merge-tree", "--write-tree", first, second)
	if err != nil || tree != expected {
		return fmt.Errorf("sync merge commit tree differs from a clean merge of its parents: %s", id)
	}
	return nil
}

var syncTitleRe = regexp.MustCompile(`^Merge branch 'main' into (\S+)$`)

func queueSyncBranch(title string) (string, bool) {
	m := syncTitleRe.FindStringSubmatch(title)
	if m == nil {
		return "", false
	}
	return m[1], true
}

// queueSyncMergeValid 核對合併佇列範圍內的同步主線合併提交。merge_group 事件的 ref 是
// gh-readonly-queue/…，無法對應 PR 分支，且一組佇列可含多個 PR；因此分支名稱改由範圍內的
// 佇列合併提交背書：其標題 `Merge pull request #<n> from <owner>/<分支>` 已由
// queueMergeCommitValid 以 GitHub API 核對 PR head 倉庫為本倉庫、分支與第二父提交一致。
// 同步合併須可由該佇列合併提交的第二父提交（PR head）到達，再套用與 PR 階段相同的結構核對。
func queueSyncMergeValid(repo, listing, id, first, second, ref, base string, inRange map[string]bool) error {
	for _, line := range strings.Split(listing, "\n") {
		f := strings.Fields(line)
		if len(f) != 3 {
			continue
		}
		title, err := mergeTitle(repo, f[0])
		if err != nil {
			return err
		}
		m := queueTitle.FindStringSubmatch(title)
		if m == nil || m[3] != ref || !isAncestor(repo, id, f[2]) {
			continue
		}
		return syncMergeValid(repo, id, first, second, base, inRange)
	}
	return fmt.Errorf("sync merge commit branch is not backed by a queue pull request merge: %s", id)
}
