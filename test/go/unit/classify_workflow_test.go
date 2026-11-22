package unit_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPullRequestClassifyGatesOnlyDeclaredHeavyJobs(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("../../..", ".github/workflows/windows_tests.yml"))
	if err != nil {
		t.Fatal(err)
	}
	text := strings.ReplaceAll(string(data), "\r\n", "\n")
	classify := coverageJob(text, "classify")
	for _, required := range []string{"fetch-depth: 0", "ci_classify.ps1", "continue-on-error: true", "steps.classify.outcome != 'success'", "-FailOpen", "select_doc_checks", "doc_tests"} {
		if !strings.Contains(classify, required) {
			t.Fatalf("classify missing %s", required)
		}
	}
	gated := map[string]string{
		"isolated-tests":          "select_tests",
		"powershell-coverage":     "select_powershell_coverage",
		"coverage-aggregation":    "select_coverage_aggregation",
		"requirements-gate":       "select_requirements_gate",
		"docker-tests":            "select_docker_tests",
		"oobe_payload_inspection": "select_oobe_payload",
	}
	for job, key := range gated {
		body := coverageJob(text, job)
		if !strings.Contains(body, "needs.classify.outputs."+key+" == 'true'") {
			t.Fatalf("%s is not gated by classify output %s", job, key)
		}
		if !strings.Contains(body, "classify") || !strings.Contains(body, "needs: [") {
			t.Fatalf("%s does not wait for classify", job)
		}
		for _, line := range strings.Split(body, "\n") {
			if strings.HasPrefix(line, "    if:") && strings.Contains(line, "github.event") {
				t.Fatalf("%s must be selected by classify, not by an event condition", job)
			}
		}
	}
	docs := coverageJob(text, "doc-checks")
	for _, required := range []string{"needs.classify.outputs.select_doc_checks == 'true'", "run_ci.ps1", "-Suite", "needs.classify.outputs.doc_tests"} {
		if !strings.Contains(docs, required) {
			t.Fatalf("doc-checks missing %s", required)
		}
	}
	if !strings.Contains(docs, "-Layer All") {
		t.Fatal("doc-checks must keep the complete inventory check before selecting suites")
	}
	rollup := coverageJob(text, "ci-rollup")
	for _, required := range []string{"if: always()", "needs: [classify, doc-checks,", "needs.classify.result", "needs.doc-checks.result", "Resolve-CIRollupStates", "select_tests", "select_docker_tests", "select_coverage_aggregation", "select_doc_checks", "Assert-CIResults"} {
		if !strings.Contains(rollup, required) {
			t.Fatalf("ci-rollup missing %s", required)
		}
	}
	if !strings.Contains(coverageJob(text, "requirements-gate"), "always() && needs.classify.outputs.select_requirements_gate == 'true' && needs.coverage-aggregation.result != 'cancelled'") {
		t.Fatal("requirements-gate must not run when classify did not select it, and must still report cancelled aggregation")
	}
}

func TestClassifyScriptPrefixesStayInWorkflowOutputs(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("../../..", ".github/workflows/windows_tests.yml"))
	if err != nil {
		t.Fatal(err)
	}
	script, err := os.ReadFile(filepath.Join("../../..", "script/test/ci_classify.ps1"))
	if err != nil {
		t.Fatal(err)
	}
	classify := coverageJob(strings.ReplaceAll(string(data), "\r\n", "\n"), "classify")
	for _, key := range []string{"tests", "powershell_coverage", "coverage_aggregation", "requirements_gate", "docker_tests", "oobe_payload"} {
		if !strings.Contains(string(script), "'"+key+"'") {
			t.Fatalf("classifier does not emit %s", key)
		}
		if !strings.Contains(classify, "select_"+key+": ${{ steps.classify.outputs.select_"+key) {
			t.Fatalf("classify does not export select_%s", key)
		}
	}
}
