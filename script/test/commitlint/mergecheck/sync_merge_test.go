package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"
)

// TestPullRequestSyncMainMerge 驗證 PR 階段接受 GitHub「更新分支」產生的
// `Merge branch 'main' into <head 分支>` 合併提交，且必須通過結構核對。
func TestPullRequestSyncMainMerge(t *testing.T) {
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
	main2 := git("rev-parse", "HEAD")

	treeOf := func(a, b string) string { return git("merge-tree", "--write-tree", a, b) }
	merge := func(msg, tree string, parents ...string) string {
		args := []string{"commit-tree", tree}
		for _, p := range parents {
			args = append(args, "-p", p)
		}
		return git(append(args, "-m", msg)...)
	}
	syncTitle := "Merge branch 'main' into feature/x"
	good := merge(syncTitle, treeOf(prOld, main1), prOld, main1)
	// 帶入額外內容：tree 多了一個檔案。
	git("switch", "--quiet", "--detach", good)
	write("extra.txt", "extra\n")
	extraTree := git("write-tree")
	git("reset", "--quiet", "--hard")
	git("clean", "--quiet", "-fd")
	// main 之後才出現的提交，不是 base 的祖先。
	git("switch", "--quiet", "--detach", main2)
	write("e.txt", "e\n")
	git("commit", "--quiet", "-m", "主線：base 之後的提交")
	future := git("rev-parse", "HEAD")

	runCase := func(head, ref string, base string) error {
		synthetic := merge("synthetic", treeOf(base, head), base, head)
		git("switch", "--quiet", "--detach", synthetic)
		raw := fmt.Sprintf(`{"repository":{"full_name":"%s"},"number":9,"pull_request":{"number":9,"base":{"sha":"%s","ref":"main","repo":{"full_name":"%s"}},"head":{"sha":"%s","ref":"%s","repo":{"full_name":"%s"}}}}`,
			fixedRepository, base, fixedRepository, head, ref, fixedRepository)
		return checkEventInRepository(repo, "pull_request", "refs/pull/9/merge", synthetic, "", []byte(raw), root, []string{root})
	}
	for _, tc := range []struct {
		name string
		head string
		ref  string
		base string
		want bool
	}{
		{"sync merge accepted", good, "feature/x", main2, true},
		{"title names a different branch", good, "feature/y", main2, false},
		{"second parent is newer than base", merge(syncTitle, treeOf(prOld, future), prOld, future), "feature/x", main2, false},
		{"first parent is not a PR commit", merge(syncTitle, treeOf(main1, prOld), main1, prOld), "feature/x", main2, false},
		{"merge brings extra content", merge(syncTitle, extraTree, prOld, main1), "feature/x", main2, false},
		{"other English title", merge("Merge branch 'dev' into feature/x", treeOf(prOld, main1), prOld, main1), "feature/x", main2, false},
		{"no head ref in event", good, "", main2, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			err := runCase(tc.head, tc.ref, tc.base)
			if (err == nil) != tc.want {
				t.Fatalf("want accepted=%v: %v", tc.want, err)
			}
		})
	}
	t.Run("push event does not accept sync merge", func(t *testing.T) {
		git("switch", "--quiet", "--detach", good)
		if err := validateMergeTitlesForEvent(repo, []string{good}, []string{root}, "push_main"); err == nil {
			t.Fatal("sync merge accepted outside pull_request")
		}
	})
}
