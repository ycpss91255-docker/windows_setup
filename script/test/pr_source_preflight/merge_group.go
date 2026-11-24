package main

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

var groupHeadRef = regexp.MustCompile(`/pr-([0-9]+)-[0-9a-f]+$`)

type queueNode struct {
	Position   int `json:"position"`
	HeadCommit struct {
		OID string `json:"oid"`
	} `json:"headCommit"`
	PullRequest struct {
		Number            int   `json:"number"`
		IsCrossRepository *bool `json:"isCrossRepository"`
		HeadRepository    *struct {
			NameWithOwner string `json:"nameWithOwner"`
		} `json:"headRepository"`
	} `json:"pullRequest"`
}

// checkMergeGroup 嚴格核對 merge_group 事件：佇列內本組每個 PR 都來自同一倉庫、
// group head 由 base 合併而成、實際 checkout 就是被測的 group head。任何無法證明的情況一律拒絕。
func checkMergeGroup(repo, eventPath, queuePath, repository, checkout, runSHA string) error {
	if repository == "" || !strings.Contains(repository, "/") {
		return errors.New("missing repository")
	}
	data, err := os.ReadFile(eventPath)
	if err != nil {
		return err
	}
	var ev struct {
		MergeGroup *struct {
			BaseRef string `json:"base_ref"`
			BaseSHA string `json:"base_sha"`
			HeadRef string `json:"head_ref"`
			HeadSHA string `json:"head_sha"`
		} `json:"merge_group"`
	}
	if err = json.Unmarshal(data, &ev); err != nil || ev.MergeGroup == nil {
		return errors.New("merge_group event missing")
	}
	mg := ev.MergeGroup
	for _, v := range []string{checkout, runSHA, mg.BaseSHA, mg.HeadSHA} {
		if !oid.MatchString(v) {
			return errors.New("missing or invalid commit identity")
		}
	}
	if mg.BaseRef != "refs/heads/main" {
		return errors.New("merge group base is not main")
	}
	if checkout != mg.HeadSHA || runSHA != mg.HeadSHA {
		return errors.New("checkout or run SHA differs from the merge group head")
	}
	git := func(args ...string) (string, error) {
		c := exec.Command("git", args...)
		c.Dir = repo
		b, e := c.Output()
		return strings.TrimSpace(string(b)), e
	}
	if actual, e := git("rev-parse", "--verify", "HEAD^{commit}"); e != nil || actual != mg.HeadSHA {
		return errors.New("repository HEAD differs from the merge group head")
	}
	if _, e := git("rev-parse", "--verify", "HEAD^{tree}"); e != nil {
		return errors.New("merge group tree unreadable")
	}
	if _, e := git("merge-base", "--is-ancestor", mg.BaseSHA, mg.HeadSHA); e != nil {
		return errors.New("merge group head is not built on its base")
	}
	q, err := os.ReadFile(queuePath)
	if err != nil {
		return err
	}
	var reply struct {
		Data struct {
			Repository struct {
				MergeQueue *struct {
					Entries struct {
						Nodes []queueNode `json:"nodes"`
					} `json:"entries"`
				} `json:"mergeQueue"`
			} `json:"repository"`
		} `json:"data"`
	}
	if err = json.Unmarshal(q, &reply); err != nil || reply.Data.Repository.MergeQueue == nil {
		return errors.New("merge queue unavailable")
	}
	nodes := reply.Data.Repository.MergeQueue.Entries.Nodes
	var entry *queueNode
	for i := range nodes {
		if nodes[i].HeadCommit.OID == mg.HeadSHA {
			entry = &nodes[i]
			break
		}
	}
	if entry == nil {
		return errors.New("no merge queue entry for the group head")
	}
	m := groupHeadRef.FindStringSubmatch(mg.HeadRef)
	if m == nil || m[1] != itoa(entry.PullRequest.Number) {
		return errors.New("group head ref does not name the queue entry pull request")
	}
	for _, n := range nodes {
		if n.Position > entry.Position {
			continue
		}
		pr := n.PullRequest
		if pr.IsCrossRepository == nil || *pr.IsCrossRepository || pr.HeadRepository == nil || pr.HeadRepository.NameWithOwner != repository {
			return errors.New("merge group contains a pull request not proven same-repository")
		}
	}
	return nil
}

func itoa(n int) string {
	b, _ := json.Marshal(n)
	return string(b)
}
