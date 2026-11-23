package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

type mgFixture struct {
	dir, base, prHead, groupHead, other string
}

func newMergeGroupFixture(t *testing.T) mgFixture {
	t.Helper()
	d := t.TempDir()
	git := func(args ...string) string {
		t.Helper()
		c := exec.Command("git", args...)
		c.Dir = d
		c.Env = append(os.Environ(), "GIT_AUTHOR_NAME=Fixture", "GIT_AUTHOR_EMAIL=fixture@example.invalid", "GIT_COMMITTER_NAME=Fixture", "GIT_COMMITTER_EMAIL=fixture@example.invalid")
		b, e := c.CombinedOutput()
		if e != nil {
			t.Fatalf("git %v: %s: %v", args, b, e)
		}
		return strings.TrimSpace(string(b))
	}
	git("init", "-q")
	os.WriteFile(filepath.Join(d, "f"), []byte("base"), 0600)
	git("add", "f")
	git("commit", "-qm", "base")
	base := git("rev-parse", "HEAD")
	os.WriteFile(filepath.Join(d, "f"), []byte("head"), 0600)
	git("commit", "-qam", "pr")
	prHead := git("rev-parse", "HEAD")
	tree := git("rev-parse", "HEAD^{tree}")
	group := git("commit-tree", tree, "-p", base, "-p", prHead, "-m", "group")
	other := git("commit-tree", git("rev-parse", base+"^{tree}"), "-m", "unrelated")
	git("checkout", "--detach", "-q", group)
	return mgFixture{d, base, prHead, group, other}
}

func queueEntry(position, number int, cross bool, repo any) map[string]any {
	return map[string]any{"position": position, "headCommit": map[string]string{"oid": strings.Repeat("0", 40)}, "pullRequest": map[string]any{"number": number, "isCrossRepository": cross, "headRepository": repo}}
}

func TestMergeGroupStrictChecks(t *testing.T) {
	same := map[string]string{"nameWithOwner": "fixture/repo"}
	fork := map[string]string{"nameWithOwner": "someone/repo"}
	type in struct {
		baseRef, headRef string
		checkout, runSHA string
		baseSHA, headSHA string
		nodes            []map[string]any
		nullQueue        bool
		repoHead         string
	}
	cases := []struct {
		name string
		mut  func(f mgFixture, i *in)
		ok   bool
	}{
		{"valid group", func(f mgFixture, i *in) {}, true},
		{"later entry from a fork is not in the group", func(f mgFixture, i *in) {
			i.nodes = append(i.nodes, queueEntry(2, 8, true, fork))
		}, true},
		{"earlier entry from a fork", func(f mgFixture, i *in) {
			i.nodes = []map[string]any{queueEntry(1, 6, true, fork), i.nodes[0]}
			i.nodes[1]["position"] = 2
		}, false},
		{"entry from a fork", func(f mgFixture, i *in) {
			i.nodes[0] = queueEntry(1, 7, true, fork)
			i.nodes[0]["headCommit"] = map[string]string{"oid": f.groupHead}
		}, false},
		{"same name but flagged cross repository", func(f mgFixture, i *in) { i.nodes[0]["pullRequest"].(map[string]any)["isCrossRepository"] = true }, false},
		{"fork name without the cross repository flag", func(f mgFixture, i *in) {
			i.nodes[0]["pullRequest"].(map[string]any)["headRepository"] = fork
		}, false},
		{"actual HEAD differs from the event head", func(f mgFixture, i *in) { i.repoHead = f.base }, false},
		{"deleted head repository", func(f mgFixture, i *in) { i.nodes[0]["pullRequest"].(map[string]any)["headRepository"] = nil }, false},
		{"head ref names another pull request", func(f mgFixture, i *in) {
			i.headRef = "refs/heads/gh-readonly-queue/main/pr-99-" + strings.Repeat("a", 40)
		}, false},
		{"no queue entry for the group head", func(f mgFixture, i *in) { i.nodes[0]["headCommit"] = map[string]string{"oid": strings.Repeat("e", 40)} }, false},
		{"merge queue absent", func(f mgFixture, i *in) { i.nullQueue = true }, false},
		{"base is not an ancestor of the group head", func(f mgFixture, i *in) { i.baseSHA = f.other }, false},
		{"checkout differs from the group head", func(f mgFixture, i *in) { i.checkout = f.base }, false},
		{"run SHA differs from the group head", func(f mgFixture, i *in) { i.runSHA = f.base }, false},
		{"base ref is not main", func(f mgFixture, i *in) { i.baseRef = "refs/heads/other" }, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := newMergeGroupFixture(t)
			node := queueEntry(1, 7, false, same)
			node["headCommit"] = map[string]string{"oid": f.groupHead}
			i := in{baseRef: "refs/heads/main", headRef: "refs/heads/gh-readonly-queue/main/pr-7-" + strings.Repeat("a", 40), checkout: f.groupHead, runSHA: f.groupHead, baseSHA: f.base, headSHA: f.groupHead, nodes: []map[string]any{node}}
			tc.mut(f, &i)
			if i.repoHead != "" {
				c := exec.Command("git", "checkout", "--detach", "-q", i.repoHead)
				c.Dir = f.dir
				if b, e := c.CombinedOutput(); e != nil {
					t.Fatalf("git checkout: %s: %v", b, e)
				}
			}
			event := filepath.Join(f.dir, "event.json")
			queue := filepath.Join(f.dir, "queue.json")
			ev, _ := json.Marshal(map[string]any{"merge_group": map[string]string{"base_ref": i.baseRef, "base_sha": i.baseSHA, "head_ref": i.headRef, "head_sha": i.headSHA}})
			var mq any
			if !i.nullQueue {
				mq = map[string]any{"entries": map[string]any{"nodes": i.nodes}}
			}
			q, _ := json.Marshal(map[string]any{"data": map[string]any{"repository": map[string]any{"mergeQueue": mq}}})
			os.WriteFile(event, ev, 0600)
			os.WriteFile(queue, q, 0600)
			err := run([]string{"-mode", "merge-group", "-repo", f.dir, "-event", event, "-queue", queue, "-repository", "fixture/repo", "-checkout", i.checkout, "-run-sha", i.runSHA})
			if (err == nil) != tc.ok {
				t.Fatalf("want success=%v, got %v", tc.ok, err)
			}
		})
	}
}

func TestWorkflowChecksMergeGroup(t *testing.T) {
	workflow, err := os.ReadFile(filepath.Join("..", "..", "..", ".github", "workflows", "windows_tests.yml"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(workflow)
	if !strings.Contains(text, "-mode merge-group") || !strings.Contains(text, "mergeQueue(branch: \"main\")") {
		t.Fatal("source-preflight must verify merge_group events")
	}
}
