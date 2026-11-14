//go:build windows && browserlayout

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"html"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

func TestMobileOverviewBrowserLayout(t *testing.T) {
	browser := os.Getenv("WINDOWS_SETUP_LAYOUT_BROWSER")
	if !filepath.IsAbs(browser) {
		t.Fatal("WINDOWS_SETUP_LAYOUT_BROWSER must be an absolute browser path")
	}
	if info, err := os.Stat(browser); err != nil || !info.Mode().IsRegular() {
		t.Fatal("configured browser is unavailable")
	}
	names := []string{"Unit.driver", "Unit.account", "Unit.version", "Unit.display", "Unit.ssh", "Unit.coverage", "Unit.other"}
	checks := make([]any, 0, len(names))
	for _, name := range names {
		checks = append(checks, map[string]any{"Name": name, "Layer": "Unit", "Status": "Passed", "Executed": true, "Assertions": []any{map[string]any{"Name": `C:\fixture\AppData\` + strings.Repeat("long_unbroken_segment_", 30) + `<&end>`, "Passed": true}}})
	}
	report, err := json.Marshal(map[string]any{"Success": true, "Totals": map[string]any{}, "Checks": checks})
	if err != nil {
		t.Fatal(err)
	}
	page, _ := overviewRootDocuments("v1.2.3", map[string][]byte{"summary.json": report}, map[string][]byte{"summary.json": report})
	script := `<script>(function(){const ds=[...document.querySelectorAll('details')];const before=ds.map(d=>d.textContent);let errors=[];if(innerWidth!==EXPECTED)errors.push('viewport '+innerWidth);if(ds.length!==7)errors.push('domain count');for(let i=0;i<ds.length;i++){for(const d of ds)d.open=false;ds[i].querySelector('summary').click();if(!ds[i].open)errors.push('open '+i);if(document.documentElement.scrollWidth>document.documentElement.clientWidth)errors.push('overflow '+i+' '+document.documentElement.scrollWidth);if(ds[i].textContent!==before[i])errors.push('content '+i);const expected='C:\\fixture\\AppData\\'+'long_unbroken_segment_'.repeat(30)+'<&end>';if(ds[i].textContent.split(expected).length!==3)errors.push('assertion '+i);}for(const e of document.querySelectorAll('.row>span,.big')){const r=document.createRange();r.selectNodeContents(e);if(r.getClientRects().length!==1||e.scrollWidth>e.clientWidth)errors.push('label wraps');}const out=document.createElement('pre');out.id='layout-result';out.textContent=errors.length?errors.join(';'):'PASS';document.body.appendChild(out);})();</script>`

	dir := t.TempDir()

	for _, width := range []int{390, 1440} {
		t.Run(fmt.Sprint(width), func(t *testing.T) {
			document := strings.Replace(string(page), "</body>", strings.ReplaceAll(script, "EXPECTED", fmt.Sprint(width))+"</body>", 1)
			file := filepath.Join(dir, fmt.Sprintf("overview-%d.html", width))
			wrapper := fmt.Sprintf(`<iframe style="width:%dpx;height:900px;border:0" srcdoc="%s" onload="const x=this.contentDocument.getElementById('layout-result');const o=document.createElement('pre');o.id='layout-result';o.textContent=x?x.textContent:'MISSING';document.body.appendChild(o)"></iframe>`, width, html.EscapeString(document))
			if err := os.WriteFile(file, []byte(wrapper), 0600); err != nil {
				t.Fatal(err)
			}
			profile := filepath.Join(dir, fmt.Sprintf("profile-%d", width))
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			defer cancel()
			uri := (&url.URL{Scheme: "file", Path: "/" + filepath.ToSlash(file)}).String()
			cmd := exec.CommandContext(ctx, browser, "--headless=new", "--disable-gpu", "--disable-background-networking", "--host-resolver-rules=MAP * ~NOTFOUND", "--no-first-run", "--no-default-browser-check", "--user-data-dir="+profile, "--window-size=1600,1000", "--dump-dom", uri)
			output, e := cmd.CombinedOutput()
			if ctx.Err() != nil {
				t.Fatalf("browser timed out: %v", ctx.Err())
			}
			if e != nil {
				t.Fatalf("browser failed: %v: %s", e, output)
			}
			re := regexp.MustCompile(`<pre id="layout-result">([^<]*)</pre>`)
			m := re.FindSubmatch(output)
			if len(m) != 2 || string(m[1]) != "PASS" {
				t.Fatalf("layout did not pass: %s", m)
			}
		})
	}
}
