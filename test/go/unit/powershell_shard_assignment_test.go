package unit_test

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"

	rc "windows_setup/script/test/repo_coverage"
)

func repoShardCatalogTests(t *testing.T) []rc.PowerShellShardTest {
	t.Helper()
	pattern := regexp.MustCompile(`^[a-z0-9_]+_tests\.ps1$`)
	tests := []rc.PowerShellShardTest{}
	for _, layer := range []string{"unit", "integration"} {
		entries, err := os.ReadDir(filepath.Join("../../..", "test/powershell", layer))
		if err != nil {
			t.Fatal(err)
		}
		for _, entry := range entries {
			if !entry.IsDir() && pattern.MatchString(entry.Name()) {
				tests = append(tests, rc.PowerShellShardTest{File: "test/powershell/" + layer + "/" + entry.Name(), SHA256: strings.Repeat("a", 64), Engine: "powershell"})
			}
		}
	}
	sort.Slice(tests, func(i, j int) bool { return tests[i].File < tests[j].File })
	return tests
}

func shardLoads(t *testing.T, tests []rc.PowerShellShardTest, count int) ([]int, []int) {
	t.Helper()
	assignment, err := rc.AssignPowerShellShards(tests, count)
	if err != nil {
		t.Fatal(err)
	}
	if len(assignment) != len(tests) {
		t.Fatalf("assignment covers %d of %d suites", len(assignment), len(tests))
	}
	loads, sizes := make([]int, count), make([]int, count)
	for i, shard := range assignment {
		if shard < 0 || shard >= count {
			t.Fatalf("suite %d assigned outside matrix: %d", i, shard)
		}
		loads[shard] += rc.PowerShellSuiteWeight(tests[i].File)
		sizes[shard]++
	}
	return loads, sizes
}

func TestPowerShellShardAssignmentCoversEverySuiteOnceDeterministically(t *testing.T) {
	tests := repoShardCatalogTests(t)
	if len(tests) < 8 {
		t.Fatalf("repository has too few suites: %d", len(tests))
	}
	first, err := rc.AssignPowerShellShards(tests, 8)
	if err != nil {
		t.Fatal(err)
	}
	second, _ := rc.AssignPowerShellShards(tests, 8)
	if fmt.Sprint(first) != fmt.Sprint(second) {
		t.Fatal("assignment is not reproducible")
	}
	_, sizes := shardLoads(t, tests, 8)
	total := 0
	for shard, size := range sizes {
		if size == 0 {
			t.Fatalf("shard %d has no suites", shard)
		}
		total += size
	}
	if total != len(tests) {
		t.Fatalf("suites executed %d times for %d suites", total, len(tests))
	}
}

func TestPowerShellShardAssignmentBalancesMeasuredWeights(t *testing.T) {
	tests := repoShardCatalogTests(t)
	loads, _ := shardLoads(t, tests, 8)
	lowest, highest := loads[0], loads[0]
	for _, load := range loads {
		if load < lowest {
			lowest = load
		}
		if load > highest {
			highest = load
		}
	}
	if float64(highest) > float64(lowest)*1.08 {
		t.Fatalf("weighted load is unbalanced: %v", loads)
	}
	mod := make([]int, 8)
	for i, test := range tests {
		mod[i%8] += rc.PowerShellSuiteWeight(test.File)
	}
	modHighest := 0
	for _, load := range mod {
		if load > modHighest {
			modHighest = load
		}
	}
	if highest >= modHighest {
		t.Fatalf("weighted critical shard %d is not shorter than modulo %d", highest, modHighest)
	}
}

func TestPowerShellShardAssignmentRejectsInvalidCounts(t *testing.T) {
	tests := repoShardCatalogTests(t)
	for _, count := range []int{0, -1, 9} {
		if _, err := rc.AssignPowerShellShards(tests, count); err == nil {
			t.Fatalf("count %d accepted", count)
		}
	}
	for _, count := range []int{1, 8} {
		if _, err := rc.AssignPowerShellShards(tests, count); err != nil {
			t.Fatalf("count %d rejected: %v", count, err)
		}
	}
}

func TestPowerShellShardAssignmentUsesDefaultWeightForNewSuites(t *testing.T) {
	tests := []rc.PowerShellShardTest{{File: "test/powershell/unit/a_new_tests.ps1"}, {File: "test/powershell/unit/b_new_tests.ps1"}, {File: "test/powershell/unit/c_new_tests.ps1"}}
	assignment, err := rc.AssignPowerShellShards(tests, 3)
	if err != nil || fmt.Sprint(assignment) != "[0 1 2]" {
		t.Fatalf("unmeasured suites must spread by sorted name: %v %v", assignment, err)
	}
}
