package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestMergeGroupEventScope(t *testing.T) {
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
	anchor := commit([]string{"錨點"})
	base := commit([]string{"主線"}, anchor)
	prHead := commit([]string{"PR 提交"}, anchor)
	owner := strings.SplitN(fixedRepository, "/", 2)[0]
	good := commit([]string{fmt.Sprintf("Merge pull request #7 from %s/feature/x", owner), "文件：更新合併規範"}, base, prHead)
	badTitle := commit([]string{"整合：不合規", "文件：更新合併規範"}, base, prHead)
	unrelatedBase := commit([]string{"無關"})
	old := prHeadLookup
	defer func() { prHeadLookup = old }()
	prHeadLookup = func(n int) (prHead_, error) {
		return prHead_{SHA: prHead, Ref: "feature/x", Repo: fixedRepository}, nil
	}
	event := func(baseRef, baseSHA, headSHA, headRef string) []byte {
		return []byte(fmt.Sprintf(`{"repository":{"full_name":"%s"},"merge_group":{"base_ref":"%s","base_sha":"%s","head_sha":"%s","head_ref":"%s"}}`, fixedRepository, baseRef, baseSHA, headSHA, headRef))
	}
	queueRef := func(sha string) string { return "refs/heads/gh-readonly-queue/main/pr-7-" + sha }
	for _, tc := range []struct {
		name     string
		checkout string
		ref      string
		raw      []byte
		want     bool
	}{
		{"valid single PR group", good, queueRef(good), event("refs/heads/main", base, good, queueRef(good)), true},
		{"group merge with invalid title", badTitle, queueRef(badTitle), event("refs/heads/main", base, badTitle, queueRef(badTitle)), false},
		{"base ref is not main", good, queueRef(good), event("refs/heads/other", base, good, queueRef(good)), false},
		{"group head differs from checkout", good, queueRef(good), event("refs/heads/main", base, prHead, queueRef(good)), false},
		{"group head is not built on the base", good, queueRef(good), event("refs/heads/main", unrelatedBase, good, queueRef(good)), false},
		{"workflow ref differs from the event head ref", good, "refs/heads/main", event("refs/heads/main", base, good, queueRef(good)), false},
		{"head ref is not a main queue ref", good, "refs/heads/gh-readonly-queue/other/pr-7-x", event("refs/heads/main", base, good, "refs/heads/gh-readonly-queue/other/pr-7-x"), false},
		{"no merge_group object", good, queueRef(good), []byte(fmt.Sprintf(`{"repository":{"full_name":"%s"}}`, fixedRepository)), false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			git("checkout", "--quiet", "--detach", tc.checkout)
			err := checkEventInRepository(repo, "merge_group", tc.ref, tc.checkout, "", tc.raw, anchor, []string{anchor})
			if (err == nil) != tc.want {
				t.Fatalf("want pass=%v, got %v", tc.want, err)
			}
		})
	}
}
