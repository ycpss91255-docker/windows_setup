package main

import (
	"fmt"
	"strings"
	"testing"
)

// TestPullRequestBaseRepositoryChecked 讓 repository.full_name 正確、只有 base.repo.full_name
// 不同的 PR 事件單獨被拒絕，避免兩個倉庫名稱檢查互相遮蔽。
func TestPullRequestBaseRepositoryChecked(t *testing.T) {
	sha := strings.Repeat("a", 40)
	base := strings.Repeat("b", 40)
	event := func(baseRepo string) []byte {
		return []byte(fmt.Sprintf(`{"repository":{"full_name":"%s"},"number":3,"pull_request":{"number":3,"base":{"sha":"%s","ref":"main","repo":{"full_name":"%s"}},"head":{"sha":"%s"}}}`, fixedRepository, base, baseRepo, sha))
	}
	if _, e := parseSourceEvent("pull_request", "refs/pull/3/merge", sha, base, event(fixedRepository)); e != nil {
		t.Fatalf("matching base repository rejected: %v", e)
	}
	for _, other := range []string{"ycpss91255/windows_setup", "ycpss91255-docker/windows_setup", "other-owner/windows_setup", ""} {
		if _, e := parseSourceEvent("pull_request", "refs/pull/3/merge", sha, base, event(other)); e == nil {
			t.Fatalf("base repository %q accepted while repository.full_name is correct", other)
		}
	}
}
