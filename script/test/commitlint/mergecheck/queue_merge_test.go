package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestQueueMergeCommitRules(t *testing.T) {
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
	git("init", "--quiet", repo)
	tree := git("mktree")
	commit := func(message []string, parents ...string) string {
		args := []string{"commit-tree", tree}
		for _, p := range parents {
			args = append(args, "-p", p)
		}
		for _, m := range message {
			args = append(args, "-m", m)
		}
		return git(args...)
	}
	root := commit([]string{"起點"})
	main1 := commit([]string{"主線"}, root)
	prHead := commit([]string{"PR 提交"}, root)
	otherHead := commit([]string{"另一個提交"}, root)
	owner := strings.SplitN(fixedRepository, "/", 2)[0]
	title := func(n int, branch string) string {
		return fmt.Sprintf("Merge pull request #%d from %s/%s", n, owner, branch)
	}
	oldLookup := prHeadLookup
	defer func() { prHeadLookup = oldLookup }()
	prHeadLookup = func(number int) (prHead_, error) {
		if number != 7 {
			return prHead_{}, fmt.Errorf("unknown PR")
		}
		return prHead_{SHA: prHead, Ref: "feature/x", Repo: fixedRepository}, nil
	}
	for _, tc := range []struct {
		name    string
		message []string
		second  string
		want    bool
	}{
		{"queue merge with Chinese PR title", []string{title(7, "feature/x"), "文件：更新合併規範"}, prHead, true},
		{"manual Chinese merge remains valid", []string{"合併：納入功能"}, prHead, true},
		{"second parent is not the PR head", []string{title(7, "feature/x"), "文件：更新合併規範"}, otherHead, false},
		{"body title is English", []string{title(7, "feature/x"), "docs: update merge rules"}, prHead, false},
		{"body lacks the domain separator", []string{title(7, "feature/x"), "更新合併規範"}, prHead, false},
		{"body has no body", []string{title(7, "feature/x")}, prHead, false},
		{"branch differs from the PR head ref", []string{title(7, "other"), "文件：更新合併規範"}, prHead, false},
		{"foreign owner", []string{"Merge pull request #7 from someone/feature/x", "文件：更新合併規範"}, prHead, false},
		{"unknown pull request", []string{title(8, "feature/x"), "文件：更新合併規範"}, prHead, false},
		{"arbitrary English merge title", []string{"Merge branch 'x' into main", "文件：更新合併規範"}, prHead, false},
		{"title with trailing text", []string{title(7, "feature/x") + " extra", "文件：更新合併規範"}, prHead, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			m := commit(tc.message, main1, tc.second)
			err := validateMergeTitles(repo, []string{m}, []string{root})
			if (err == nil) != tc.want {
				t.Fatalf("want pass=%v, got %v", tc.want, err)
			}
		})
	}
}
