package unit_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPowerShellCoverageUsesCompleteEightShardMatrix(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("../../..", ".github/workflows/windows_tests.yml"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(b)
	shard := coverageJob(text, "powershell-coverage")
	for _, required := range []string{"fail-fast: false", "shard: ${{ fromJSON(needs.compute-shards.outputs.shards) }}", "needs: [source-preflight, compute-shards]", "-ShardCount ([int]$env:SHARD_COUNT)", "SHARD_COUNT: ${{ needs.compute-shards.outputs.count }}", "powershell_coverage_shard.ps1", "GITHUB_RUN_ATTEMPT", "powershell-shard-", "retention-days: 7"} {
		if !strings.Contains(shard, required) {
			t.Fatalf("complete parallel collection missing %s", required)
		}
	}
	compute := coverageJob(text, "compute-shards")
	for _, required := range []string{"vars.CI_SHARDS", "n=\"${CI_SHARDS:-8}\"", "(( n > 8 )) && n=8", "(( n < 1 )) && n=1", "shards=[", "count=${n}"} {
		if !strings.Contains(compute, required) {
			t.Fatalf("shard count variable contract missing %s", required)
		}
	}
	host := coverageJob(text, "coverage-aggregation")
	for _, required := range []string{"needs: [isolated-tests, powershell-coverage, compute-shards]", "actions/download-artifact@", "powershell-shard-", "-PowerShellShardDirectory", "run_repo_coverage.ps1", "managed_coverage.ps1", "native-stage-restore"} {
		if !strings.Contains(host, required) {
			t.Fatalf("host cannot verify all shards without losing original producers: %s", required)
		}
	}
	if !strings.Contains(coverageJob(text, "ci-rollup"), "powershell-coverage") {
		t.Fatal("failed or skipped matrix can bypass rollup")
	}
}
