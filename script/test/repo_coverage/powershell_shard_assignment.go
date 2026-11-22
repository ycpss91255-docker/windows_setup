package repo_coverage

import (
	"fmt"
	"sort"
)

// MaxPowerShellShards is the largest supported collection matrix.
const MaxPowerShellShards = 8

const defaultPowerShellSuiteSeconds = 30

// PowerShellSuiteWeight returns the measured cost of a suite in seconds.
func PowerShellSuiteWeight(file string) int {
	if seconds, ok := powerShellSuiteSeconds[file]; ok && seconds > 0 {
		return seconds
	}
	return defaultPowerShellSuiteSeconds
}

// AssignPowerShellShards returns the zero based shard for every catalog test.
// It is a pure function of the sorted canonical catalog and the committed
// weights (longest processing time first, ties to the lowest shard), so the
// planner, packer and merger always agree and every suite runs exactly once.
func AssignPowerShellShards(tests []PowerShellShardTest, count int) ([]int, error) {
	if count < 1 || count > MaxPowerShellShards {
		return nil, fmt.Errorf("PowerShell shard count must be between 1 and %d", MaxPowerShellShards)
	}
	order := make([]int, len(tests))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(a, b int) bool {
		wa, wb := PowerShellSuiteWeight(tests[order[a]].File), PowerShellSuiteWeight(tests[order[b]].File)
		if wa != wb {
			return wa > wb
		}
		return tests[order[a]].File < tests[order[b]].File
	})
	assignment, loads := make([]int, len(tests)), make([]int, count)
	for _, global := range order {
		lightest := 0
		for shard := 1; shard < count; shard++ {
			if loads[shard] < loads[lightest] {
				lightest = shard
			}
		}
		assignment[global] = lightest
		loads[lightest] += PowerShellSuiteWeight(tests[global].File)
	}
	return assignment, nil
}
