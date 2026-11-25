package unit_test

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// 被後續合併取代的 main run 必須明確跳過索引與發布，且不得讓下游工作變紅或以舊 SHA 發布。
func TestSupersededMainRunSkipsPublication(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("../../..", ".github/workflows/windows_tests.yml"))
	if err != nil {
		t.Fatal(err)
	}
	workflow := strings.ReplaceAll(string(data), "\r\n", "\n")
	condition := func(job string) string {
		m := regexp.MustCompile(`(?m)^    if: (.*)$`).FindStringSubmatch(job)
		if len(m) != 2 {
			return ""
		}
		return m[1]
	}
	build := coverageJob(workflow, "build-portal")
	publish := coverageJob(workflow, "publish-reports")
	verify := coverageJob(workflow, "verify-deployment")

	if !regexp.MustCompile(`(?m)^    outputs:\n      superseded: \$\{\{ steps\.[a-z_]+\.outputs\.superseded \}\}`).MatchString(build) {
		t.Error("build-portal must expose the superseded decision as a job output")
	}
	if !strings.Contains(build, "Invoke-CIPortalBuild -Inputs $inputs") || !strings.Contains(build, "-OutputPath $env:GITHUB_OUTPUT") {
		t.Error("build-portal must record a clear superseded decision instead of failing")
	}
	uploadStep := ""
	for _, step := range strings.Split(build, "\n      - name:") {
		if strings.Contains(step, "actions/upload-artifact") {
			uploadStep = step
		}
	}
	if !strings.Contains(uploadStep, "superseded != 'true'") {
		t.Error("portal artifact upload must be skipped for a superseded run")
	}

	if !strings.Contains(condition(publish), "needs.build-portal.outputs.superseded != 'true'") {
		t.Error("Pages publication must not run for a superseded run")
	}
	if !strings.Contains(publish, "id: fresh") || !strings.Contains(publish, "Set-CIMainFreshness") || !strings.Contains(publish, "steps.fresh.outputs.current") {
		t.Error("publication must re-check that main has not advanced right before deploying")
	}
	deployIndex := strings.Index(publish, "uses: actions/deploy-pages")
	freshIndex := strings.Index(publish, "id: fresh")
	if freshIndex < 0 || deployIndex < 0 || freshIndex > deployIndex {
		t.Error("the freshness check must run before deploy-pages")
	}
	if !regexp.MustCompile(`(?m)^    outputs:\n      deployed: `).MatchString(publish) {
		t.Error("publish-reports must expose whether it deployed")
	}
	if !strings.Contains(condition(verify), "needs.publish-reports.outputs.deployed == 'true'") {
		t.Error("deployment verification must only run when this run actually deployed")
	}
}

// main 已前進時不得為 github-pages 環境留下部署紀錄：前進檢查須在不綁 environment 的前置工作完成，
// 被取代時整個發布工作被略過；發布工作內仍保留最後一次檢查。
func TestSupersededMainRunDoesNotCreateEnvironmentDeployment(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("../../..", ".github/workflows/windows_tests.yml"))
	if err != nil {
		t.Fatal(err)
	}
	workflow := strings.ReplaceAll(string(data), "\r\n", "\n")
	fresh := coverageJob(workflow, "pages-freshness")
	publish := coverageJob(workflow, "publish-reports")
	if fresh == "" {
		t.Fatal("a job without an environment must decide whether main has advanced")
	}
	if strings.Contains(fresh, "environment:") {
		t.Fatal("the freshness job must not bind the github-pages environment")
	}
	if !strings.Contains(fresh, "Set-CIMainFreshness") || !regexp.MustCompile(`(?m)^    outputs:\n      current: \$\{\{ steps\.[a-z_]+\.outputs\.current \}\}`).MatchString(fresh) {
		t.Error("the freshness job must run Set-CIMainFreshness and expose current")
	}
	if !regexp.MustCompile(`(?m)^    needs: \[[^\]]*pages-freshness[^\]]*\]`).MatchString(publish) {
		t.Error("publish-reports must wait for the freshness decision")
	}
	m := regexp.MustCompile(`(?m)^    if: (.*)$`).FindStringSubmatch(publish)
	if len(m) != 2 || !strings.Contains(m[1], "needs.pages-freshness.outputs.current == 'true'") {
		t.Error("publish-reports must be skipped as a whole when main has advanced")
	}
	if !strings.Contains(publish, "id: fresh") || !strings.Contains(publish, "steps.fresh.outputs.current == 'true'") {
		t.Error("the last-moment check before deploy-pages must remain")
	}
}
