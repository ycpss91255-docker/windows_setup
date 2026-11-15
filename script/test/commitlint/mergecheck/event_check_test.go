package main

import (
	"fmt"
	"strings"
	"testing"
)

func TestFrozenManifestRoots(t *testing.T) {
	roots, e := frozenRoots()
	if e != nil || len(roots) != 24 || roots[0] != fixedAnchor {
		t.Fatalf("invalid roots: %d %v", len(roots), e)
	}
	saved := frozenManifest
	defer func() { frozenManifest = saved }()
	frozenManifest = append(append([]byte{}, saved...), ' ')
	if _, e = frozenRoots(); e == nil {
		t.Fatal("modified manifest accepted")
	}
}
func TestEventMetadataFailsClosed(t *testing.T) {
	sha := strings.Repeat("a", 40)
	base := strings.Repeat("b", 40)
	before := strings.Repeat("c", 40)
	pr := fmt.Sprintf(`{"repository":{"full_name":"%s"},"number":3,"pull_request":{"number":3,"base":{"sha":"%s","ref":"main","repo":{"full_name":"%s"}},"head":{"sha":"%s"}}}`, fixedRepository, base, fixedRepository, sha)
	push := fmt.Sprintf(`{"repository":{"full_name":"%s"},"ref":"refs/heads/main","before":"%s","after":"%s"}`, fixedRepository, before, sha)
	for _, tc := range []struct {
		name, kind, ref, raw string
		ok                   bool
	}{
		{"pr", "pull_request", "refs/pull/3/merge", pr, true},
		{"wrong PR ref", "pull_request", "refs/pull/4/merge", pr, false},
		{"wrong repo", "pull_request", "refs/pull/3/merge", strings.Replace(pr, fixedRepository, "other/repo", 1), false},
		{"wrong number", "pull_request", "refs/pull/3/merge", strings.Replace(pr, `"number":3,"pull_request"`, `"number":4,"pull_request"`, 1), false},
		{"push", "push", "refs/heads/main", push, true},
		{"wrong ref", "push", "refs/heads/other", push, false},
		{"tag", "push", "refs/tags/v1.0.0", fmt.Sprintf(`{"repository":{"full_name":"%s"},"ref":"refs/tags/v1.0.0","after":"%s"}`, fixedRepository, sha), true},
		{"manual", "workflow_dispatch", "refs/heads/main", fmt.Sprintf(`{"repository":{"full_name":"%s"}}`, fixedRepository), true},
		{"manual branch", "workflow_dispatch", "refs/heads/other", fmt.Sprintf(`{"repository":{"full_name":"%s"}}`, fixedRepository), false},
		{"unknown queue", "merge_group", "refs/heads/main", push, false},
		{"missing event", "push", "refs/heads/main", `{}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, e := parseSourceEvent(tc.kind, tc.ref, sha, base, []byte(tc.raw))
			if (e == nil) != tc.ok {
				t.Fatalf("want %v: %v", tc.ok, e)
			}
		})
	}
}
