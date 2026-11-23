package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"
)

// TestMergeGroupSyncMainMerge 驗證合併佇列範圍內的 `Merge branch 'main' into <分支>`：
// 分支名稱須由佇列合併提交（其 PR head 已由 API 核對為本倉庫）背書，並套用與 PR 階段相同的結構核對。
func TestMergeGroupSyncMainMerge(t *testing.T) {
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
	write := func(name, content string) {
		t.Helper()
		if e := os.WriteFile(repo+"/"+name, []byte(content), 0o644); e != nil {
			t.Fatal(e)
		}
		git("add", name)
	}
	git("init", "--quiet", "-b", "main", repo)
	write("a.txt", "a\n")
	git("commit", "--quiet", "-m", "起點")
	root := git("rev-parse", "HEAD")
	git("switch", "--quiet", "-c", "feature/x")
	write("b.txt", "b\n")
	git("commit", "--quiet", "-m", "功能：新增 b")
	prOld := git("rev-parse", "HEAD")
	git("switch", "--quiet", "main")
	write("c.txt", "c\n")
	git("commit", "--quiet", "-m", "主線：新增 c")
	main1 := git("rev-parse", "HEAD")
	write("d.txt", "d\n")
	git("commit", "--quiet", "-m", "主線：新增 d")
	base := git("rev-parse", "HEAD")
	git("switch", "--quiet", "--detach", main1)
	write("e.txt", "e\n")
	git("commit", "--quiet", "-m", "主線：base 之後的提交")
	future := git("rev-parse", "HEAD")

	treeOf := func(a, b string) string { return git("merge-tree", "--write-tree", a, b) }
	merge := func(tree string, parents []string, msg ...string) string {
		args := []string{"commit-tree", tree}
		for _, p := range parents {
			args = append(args, "-p", p)
		}
		for _, m := range msg {
			args = append(args, "-m", m)
		}
		return git(args...)
	}
	syncTitle := "Merge branch 'main' into feature/x"
	good := merge(treeOf(prOld, main1), []string{prOld, main1}, syncTitle)
	git("switch", "--quiet", "--detach", good)
	write("extra.txt", "extra\n")
	extraTree := git("write-tree")
	git("reset", "--quiet", "--hard")
	git("clean", "--quiet", "-fd")

	owner := strings.SplitN(fixedRepository, "/", 2)[0]
	oldLookup := prHeadLookup
	defer func() { prHeadLookup = oldLookup }()

	// head 為 PR 分支最後一筆提交（同步合併或其後代）；queueRef 為佇列提交標題中的分支。
	runCase := func(syncCommit, queueRef, headRepo string, queueMerge bool) error {
		prHeadLookup = func(number int) (prHead_, error) {
			if number != 7 {
				return prHead_{}, fmt.Errorf("unknown PR")
			}
			return prHead_{SHA: syncCommit, Ref: queueRef, Repo: headRepo}, nil
		}
		var head string
		if queueMerge {
			head = merge(treeOf(base, syncCommit), []string{base, syncCommit}, fmt.Sprintf("Merge pull request #7 from %s/%s", owner, queueRef), "功能：新增 b")
		} else {
			head = merge(treeOf(base, syncCommit), []string{base, syncCommit}, "合併：手動合併")
		}
		git("switch", "--quiet", "--detach", head)
		ref := "refs/heads/gh-readonly-queue/main/pr-7-" + syncCommit
		raw := fmt.Sprintf(`{"repository":{"full_name":"%s"},"merge_group":{"base_ref":"refs/heads/main","base_sha":"%s","head_ref":"%s","head_sha":"%s"}}`, fixedRepository, base, ref, head)
		return checkEventInRepository(repo, "merge_group", ref, head, "", []byte(raw), root, []string{root})
	}
	for _, tc := range []struct {
		name       string
		sync       string
		queueRef   string
		headRepo   string
		queueMerge bool
		want       bool
	}{
		{"sync merge accepted in queue", good, "feature/x", fixedRepository, true, true},
		{"PR head repository is a fork", good, "feature/x", "other-owner/windows_setup", true, false},
		{"title branch differs from queue PR branch", good, "feature/y", fixedRepository, true, false},
		{"no queue merge commit names the branch", good, "feature/x", fixedRepository, false, false},
		{"first parent is not a PR commit", merge(treeOf(main1, prOld), []string{main1, prOld}, syncTitle), "feature/x", fixedRepository, true, false},
		{"second parent is newer than base", merge(treeOf(prOld, future), []string{prOld, future}, syncTitle), "feature/x", fixedRepository, true, false},
		{"first parent is outside the range", merge(treeOf(main1, root), []string{main1, root}, syncTitle), "feature/x", fixedRepository, true, false},
		{"merge brings extra content", merge(extraTree, []string{prOld, main1}, syncTitle), "feature/x", fixedRepository, true, false},
		{"other English title", merge(treeOf(prOld, main1), []string{prOld, main1}, "Merge branch 'dev' into feature/x"), "feature/x", fixedRepository, true, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			err := runCase(tc.sync, tc.queueRef, tc.headRepo, tc.queueMerge)
			if (err == nil) != tc.want {
				t.Fatalf("want accepted=%v: %v", tc.want, err)
			}
		})
	}
}

// TestMergeGroupTwoQueuedPRs 驗證一組佇列含兩個 PR 時，同步合併的背書綁定到「自己的」PR：
// 夾帶在 A 的歷史、標題卻指向 B 分支的同步合併必須拒絕；B 自己歷史中的同一種同步合併可通過。
func TestMergeGroupTwoQueuedPRs(t *testing.T) {
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
	write := func(name string) {
		t.Helper()
		if e := os.WriteFile(repo+"/"+name, []byte(name+"\n"), 0o644); e != nil {
			t.Fatal(e)
		}
		git("add", name)
	}
	git("init", "--quiet", "-b", "main", repo)
	write("a.txt")
	git("commit", "--quiet", "-m", "起點")
	root := git("rev-parse", "HEAD")
	branchCommit := func(name string) string {
		git("switch", "--quiet", "--detach", root)
		write("pr_" + name + ".txt")
		git("commit", "--quiet", "-m", "功能：新增 "+name)
		return git("rev-parse", "HEAD")
	}
	prA, prB := branchCommit("a"), branchCommit("b")
	git("switch", "--quiet", "--detach", root)
	write("c.txt")
	git("commit", "--quiet", "-m", "主線：新增 c")
	main1 := git("rev-parse", "HEAD")
	write("d.txt")
	git("commit", "--quiet", "-m", "主線：新增 d")
	base := git("rev-parse", "HEAD")
	treeOf := func(a, b string) string { return git("merge-tree", "--write-tree", a, b) }
	commit := func(parents []string, msg ...string) string {
		args := []string{"commit-tree", treeOf(parents[0], parents[1])}
		for _, p := range parents {
			args = append(args, "-p", p)
		}
		for _, m := range msg {
			args = append(args, "-m", m)
		}
		return git(args...)
	}
	owner := strings.SplitN(fixedRepository, "/", 2)[0]
	syncInto := func(branch string) string { return "Merge branch 'main' into " + branch }
	oldLookup := prHeadLookup
	defer func() { prHeadLookup = oldLookup }()
	run := func(headA, headB string) error {
		heads := map[int]prHead_{7: {SHA: headA, Ref: "feature/a", Repo: fixedRepository}, 8: {SHA: headB, Ref: "feature/b", Repo: fixedRepository}}
		prHeadLookup = func(number int) (prHead_, error) {
			h, ok := heads[number]
			if !ok {
				return prHead_{}, fmt.Errorf("unknown PR")
			}
			return h, nil
		}
		queueA := commit([]string{base, headA}, fmt.Sprintf("Merge pull request #7 from %s/feature/a", owner), "功能：新增 a")
		queueB := commit([]string{queueA, headB}, fmt.Sprintf("Merge pull request #8 from %s/feature/b", owner), "功能：新增 b")
		git("switch", "--quiet", "--detach", queueB)
		ref := "refs/heads/gh-readonly-queue/main/pr-8-" + headB
		raw := fmt.Sprintf(`{"repository":{"full_name":"%s"},"merge_group":{"base_ref":"refs/heads/main","base_sha":"%s","head_ref":"%s","head_sha":"%s"}}`, fixedRepository, base, ref, queueB)
		return checkEventInRepository(repo, "merge_group", ref, queueB, "", []byte(raw), root, []string{root})
	}
	for _, tc := range []struct {
		name         string
		headA, headB string
		want         bool
	}{
		{"each PR syncs its own branch", commit([]string{prA, main1}, syncInto("feature/a")), commit([]string{prB, main1}, syncInto("feature/b")), true},
		{"sync merge titled for B inside B history", prA, commit([]string{prB, main1}, syncInto("feature/b")), true},
		{"sync merge titled for B smuggled into A history", commit([]string{prA, main1}, syncInto("feature/b")), prB, false},
		{"sync merge titled for A smuggled into B history", prA, commit([]string{prB, main1}, syncInto("feature/a")), false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if err := run(tc.headA, tc.headB); (err == nil) != tc.want {
				t.Fatalf("want accepted=%v: %v", tc.want, err)
			}
		})
	}
}
