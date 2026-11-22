package main

import "fmt"

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
