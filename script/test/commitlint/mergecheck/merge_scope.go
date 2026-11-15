package main

import (
	"fmt"
	"os/exec"
	"regexp"
	"strings"
	"unicode"
)

var commitOID = regexp.MustCompile(`^[0-9a-f]{40}$`)

func graphGit(repo string, args ...string) (string, error) {
	c := exec.Command("git", append([]string{"-C", repo}, args...)...)
	b, e := c.Output()
	if e != nil {
		return "", fmt.Errorf("git graph verification failed: %w", e)
	}
	return strings.TrimSpace(string(b)), nil
}

func validateMergeTitles(repo string, tips, excluded []string) error {
	if len(tips) == 0 || len(excluded) == 0 {
		return fmt.Errorf("missing graph boundary")
	}
	shallow, e := graphGit(repo, "rev-parse", "--is-shallow-repository")
	if e != nil || shallow != "false" {
		return fmt.Errorf("complete Git history required")
	}
	for _, id := range append(append([]string{}, tips...), excluded...) {
		if !commitOID.MatchString(id) {
			return fmt.Errorf("invalid commit identity")
		}
		if _, e = graphGit(repo, "cat-file", "-e", id+"^{commit}"); e != nil {
			return e
		}
	}
	args := []string{"rev-list", "--parents"}
	args = append(args, tips...)
	args = append(args, "--not")
	args = append(args, excluded...)
	listing, e := graphGit(repo, args...)
	if e != nil {
		return e
	}
	for _, line := range strings.Split(listing, "\n") {
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) > 3 {
			return fmt.Errorf("unsupported merge parent count")
		}
		if len(fields) == 3 {
			title, e := graphGit(repo, "show", "-s", "--format=%s", fields[0])
			if e != nil {
				return e
			}
			if !strings.HasPrefix(title, "合併：") || !strings.ContainsFunc(strings.TrimPrefix(title, "合併："), func(r rune) bool { return unicode.Is(unicode.Han, r) }) {
				return fmt.Errorf("new merge commit has invalid title: %s", fields[0])
			}
		}
	}
	return nil
}

type sourceEvent struct{ Kind, Checkout, RunSHA, Base, Head, Before, After, Main string }

func isAncestor(repo, ancestor, descendant string) bool {
	if !commitOID.MatchString(ancestor) || !commitOID.MatchString(descendant) {
		return false
	}
	return exec.Command("git", "-C", repo, "merge-base", "--is-ancestor", ancestor, descendant).Run() == nil
}

func deriveEventScope(repo string, event sourceEvent, anchor string) ([]string, []string, error) {
	if !commitOID.MatchString(event.Checkout) || event.Checkout != event.RunSHA || !commitOID.MatchString(anchor) {
		return nil, nil, fmt.Errorf("invalid checkout identity")
	}
	if _, err := graphGit(repo, "cat-file", "-e", event.Checkout+"^{commit}"); err != nil {
		return nil, nil, err
	}
	switch event.Kind {
	case "pull_request":
		if !isAncestor(repo, anchor, event.Base) || !commitOID.MatchString(event.Head) {
			return nil, nil, fmt.Errorf("invalid PR ancestry")
		}
		parents, err := graphGit(repo, "show", "-s", "--format=%P", event.Checkout)
		if err != nil || parents != event.Base+" "+event.Head {
			return nil, nil, fmt.Errorf("PR checkout parents mismatch")
		}
		tree, err := graphGit(repo, "rev-parse", event.Checkout+"^{tree}")
		if err != nil {
			return nil, nil, err
		}
		expected, err := graphGit(repo, "merge-tree", "--write-tree", event.Base, event.Head)
		if err != nil || tree != expected {
			return nil, nil, fmt.Errorf("PR checkout tree mismatch")
		}
		return []string{event.Head}, []string{event.Base}, nil
	case "push_main":
		if event.After != event.Checkout || !isAncestor(repo, anchor, event.Before) || !isAncestor(repo, event.Before, event.After) {
			return nil, nil, fmt.Errorf("invalid main push ancestry")
		}
		return []string{event.After}, []string{event.Before}, nil
	case "tag":
		if !isAncestor(repo, anchor, event.Checkout) || !isAncestor(repo, event.Checkout, event.Main) {
			return nil, nil, fmt.Errorf("tag is not an eligible main descendant")
		}
		return []string{event.Checkout}, []string{anchor}, nil
	case "dispatch_main":
		if event.Checkout != event.Main || !isAncestor(repo, anchor, event.Main) {
			return nil, nil, fmt.Errorf("invalid manual main identity")
		}
		return []string{event.Main}, []string{anchor}, nil
	default:
		return nil, nil, fmt.Errorf("unsupported event")
	}
}
