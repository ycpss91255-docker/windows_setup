package unit_test

import (
	"testing"
	a "windows_setup/script/test/acceptance"
)

func TestCurrentOverviewBadgeRoute(t *testing.T) {
	base := "https://example.github.io/project/"
	good := "[![Coverage](" + base + "main/coverage.svg)](" + base + ")"
	cases := []struct {
		name, doc string
		valid     bool
	}{
		{"exact root", good, true},
		{"old native leaf", "[![Coverage](" + base + "main/coverage.svg)](" + base + "main/index.html)", false},
		{"unlinked image", "![Coverage](" + base + "main/coverage.svg)", false},
		{"other site", "[![Coverage](" + base + "main/coverage.svg)](https://elsewhere.example/)", false},
		{"wrong image", "[![Coverage](" + base + "main/other.svg)](" + base + ")", false},
		{"duplicate", good + "\n" + good, false},
		{"root query", "[![Coverage](" + base + "main/coverage.svg)](" + base + "?x=1)", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := a.ValidateOverviewBadge(tc.doc, base)
			if (err == nil) != tc.valid {
				t.Fatalf("valid=%v error=%v", tc.valid, err)
			}
		})
	}
}
