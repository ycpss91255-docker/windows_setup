package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"
)

// TestHistoricalScanSyncMainMerge 驗證 tag 與 main 手動執行的歷史掃描，以「引入該同步合併的那一步主線」
// 重做 main push 核對；主線只取已核對 main 的第一父鏈，不取標籤所在提交自己的第一父鏈。
func TestHistoricalScanSyncMainMerge(t *testing.T) {
	repo := t.TempDir()
	git := func(args ...string) string {
		t.Helper()
		c := exec.Command("git", args...)
		c.Dir = repo
		c.Env = append(os.Environ(), "GIT_AUTHOR_NAME=Fixture", "GIT_AUTHOR_EMAIL=fixture@example.invalid", "GIT_COMMITTER_NAME=Fixture", "GIT_COMMITTER_EMAIL=fixture@example.invalid")
		b, e := c.CombinedOutput()
		if e != nil {
			t.Fatalf("git %v: %s: %v", args, b, e)
		}
		return strings.TrimSpace(string(b))
	}
	git("init", "--quiet", "-b", "main", repo)
	child := func(parent, name string) string {
		t.Helper()
		if parent != "" {
			git("switch", "--quiet", "--detach", parent)
		}
		if e := os.WriteFile(repo+"/"+name, []byte(name+"\n"), 0o644); e != nil {
			t.Fatal(e)
		}
		git("add", name)
		git("commit", "--quiet", "-m", "新增 "+name)
		return git("rev-parse", "HEAD")
	}
	merge := func(first, second string, msg ...string) string {
		t.Helper()
		args := []string{"commit-tree", git("merge-tree", "--write-tree", first, second), "-p", first, "-p", second}
		for _, m := range msg {
			args = append(args, "-m", m)
		}
		return git(args...)
	}
	owner := strings.SplitN(fixedRepository, "/", 2)[0]
	queue := func(number int, branch string) []string {
		return []string{fmt.Sprintf("Merge pull request #%d from %s/%s", number, owner, branch), "功能：新增內容"}
	}
	anchor := child("", "a.txt")
	prX, prY := child(anchor, "x.txt"), child(anchor, "y.txt")
	main1 := child(anchor, "main1.txt")
	headX := merge(prX, main1, "Merge branch 'main' into feature/x")
	step1 := merge(main1, headX, queue(7, "feature/x")...)
	headY := merge(prY, step1, "Merge branch 'main' into feature/y")
	step2 := merge(step1, headY, queue(8, "feature/y")...)
	later := child(step2, "later.txt")

	// side 不在主線；PR 歷史內以它為第一父提交偽造佇列合併，使同步合併看似同步自「主線」。
	side := child(main1, "side.txt")
	forgedSync := merge(prX, side, "Merge branch 'main' into feature/x")
	forgedQueue := merge(side, forgedSync, queue(9, "feature/x")...)
	forgedMain := merge(main1, forgedQueue, "合併：納入分支")

	heads := map[int]prHead_{
		7: {SHA: headX, Ref: "feature/x", Repo: fixedRepository},
		8: {SHA: headY, Ref: "feature/y", Repo: fixedRepository},
		9: {SHA: forgedSync, Ref: "feature/x", Repo: fixedRepository},
	}
	oldLookup := prHeadLookup
	defer func() { prHeadLookup = oldLookup }()
	prHeadLookup = func(number int) (prHead_, error) {
		h, ok := heads[number]
		if !ok {
			return prHead_{}, fmt.Errorf("unknown PR")
		}
		return h, nil
	}
	for _, tc := range []struct {
		name, kind, checkout, main string
		want                       bool
	}{
		{"dispatch accepts syncs introduced by several mainline steps", "dispatch_main", later, later, true},
		{"tag on an older mainline step", "tag", step1, later, true},
		{"tag at current main", "tag", later, later, true},
		{"tag on a PR commit with a forged queue merge", "tag", forgedQueue, forgedMain, false},
		{"dispatch with a forged queue merge inside a PR", "dispatch_main", forgedMain, forgedMain, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			git("switch", "--quiet", "--detach", tc.checkout)
			err := checkHistoryEvent(repo, tc.kind, tc.checkout, tc.main, anchor)
			if (err == nil) != tc.want {
				t.Fatalf("want accepted=%v: %v", tc.want, err)
			}
			if !tc.want && !strings.Contains(err.Error(), "sync merge commit parents") {
				t.Fatalf("rejected for another reason: %v", err)
			}
		})
	}
}

// checkHistoryEvent 以 tag 或 main 手動執行事件核對 checkout；main 為已核對的主線頂端。
func checkHistoryEvent(repo, kind, checkout, main, anchor string) error {
	if kind == "dispatch_main" {
		raw := fmt.Sprintf(`{"repository":{"full_name":"%s"}}`, fixedRepository)
		return checkEventInRepository(repo, "workflow_dispatch", "refs/heads/main", checkout, main, []byte(raw), anchor, []string{anchor})
	}
	if out, err := exec.Command("git", "-C", repo, "tag", "--force", "v1.0.0", checkout).CombinedOutput(); err != nil {
		return fmt.Errorf("fixture tag: %s: %w", out, err)
	}
	raw := fmt.Sprintf(`{"repository":{"full_name":"%s"},"ref":"refs/tags/v1.0.0","after":"%s"}`, fixedRepository, checkout)
	return checkEventInRepository(repo, "push", "refs/tags/v1.0.0", checkout, main, []byte(raw), anchor, []string{anchor})
}
