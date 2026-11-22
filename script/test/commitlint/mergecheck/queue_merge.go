package main

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

// prHead_ 是 GitHub 回報的 PR head 身分。
type prHead_ struct{ SHA, Ref, Repo string }

// prHeadLookup 向 GitHub 取得 PR 的 head；測試以固件取代。無法取得一律視為失敗。
var prHeadLookup = lookupPRHead

func lookupPRHead(number int) (prHead_, error) {
	repository := os.Getenv("GITHUB_REPOSITORY")
	if repository == "" {
		repository = fixedRepository
	}
	out, err := exec.Command("gh", "api", fmt.Sprintf("repos/%s/pulls/%d", repository, number), "--jq", `[.head.sha,.head.ref,.head.repo.full_name]|join(" ")`).Output()
	if err != nil {
		return prHead_{}, fmt.Errorf("pull request head lookup failed: %w", err)
	}
	f := strings.Fields(string(out))
	if len(f) != 3 {
		return prHead_{}, fmt.Errorf("pull request head lookup incomplete")
	}
	return prHead_{SHA: f[0], Ref: f[1], Repo: f[2]}, nil
}

var queueTitle = regexp.MustCompile(`^Merge pull request #([1-9][0-9]*) from ([^/\s]+)/(\S+)$`)
var prTitle = regexp.MustCompile(`^[^：\s][^：]*：\S`)

// queueMergeCommitValid 接受合併佇列以 GitHub 固定格式產生的 merge commit：
// 標題 `Merge pull request #<n> from <本倉庫 owner>/<head ref>`、正文第一行為中文「領域：結果」PR 標題、
// 第二個父提交必須是該 PR 的 head，且 PR 的 head 倉庫與分支和標題一致。
func queueMergeCommitValid(repo, id, subject, secondParent string) error {
	m := queueTitle.FindStringSubmatch(subject)
	if m == nil {
		return fmt.Errorf("new merge commit has invalid title: %s", id)
	}
	number, err := strconv.Atoi(m[1])
	if err != nil || strings.SplitN(fixedRepository, "/", 2)[0] != m[2] {
		return fmt.Errorf("new merge commit has invalid title: %s", id)
	}
	body, err := graphGit(repo, "show", "-s", "--format=%b", id)
	if err != nil {
		return err
	}
	first := strings.TrimSpace(strings.SplitN(strings.TrimSpace(body), "\n", 2)[0])
	if !prTitle.MatchString(first) || !strings.ContainsFunc(first, func(r rune) bool { return unicode.Is(unicode.Han, r) }) {
		return fmt.Errorf("queue merge commit PR title is not 領域：結果 in Chinese: %s", id)
	}
	head, err := prHeadLookup(number)
	if err != nil {
		return err
	}
	if head.SHA != secondParent || head.Repo != fixedRepository || head.Ref != m[3] {
		return fmt.Errorf("queue merge commit does not match pull request head: %s", id)
	}
	return nil
}
