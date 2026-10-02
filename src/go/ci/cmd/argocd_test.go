package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestListRenderedWritesGitHubOutput(t *testing.T) {
	root := t.TempDir()
	for _, cluster := range []string{"oci", "trinity"} {
		dir := filepath.Join(root, cluster)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	writeApps := func(cluster, body string) {
		t.Helper()
		path := filepath.Join(root, cluster, "apps.yaml")
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	writeApps("oci", "apps:\n  - name: pihole\n    type: rendered\n    path: applications/pihole\n  - name: echo\n    type: helm\n")
	writeApps("trinity", "apps:\n  - name: actual-sync\n    type: rendered\n    path: applications/actual-sync\n")

	out := filepath.Join(t.TempDir(), "github_output")
	if err := os.WriteFile(out, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GITHUB_OUTPUT", out)

	prevDir := argocdClustersDir
	prevURL := argocdRepoURL
	t.Cleanup(func() {
		argocdClustersDir = prevDir
		argocdRepoURL = prevURL
	})
	argocdClustersDir = root
	argocdRepoURL = "https://github.com/example/homelab.git"

	if err := argocdListRenderedCmd.RunE(argocdListRenderedCmd, nil); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	for _, want := range []string{"oci\tpihole\tapplications/pihole", "trinity\tactual-sync\tapplications/actual-sync"} {
		if !strings.Contains(text, want) {
			t.Fatalf("GITHUB_OUTPUT missing %q:\n%s", want, text)
		}
	}
	if strings.Contains(text, "echo") {
		t.Fatalf("helm app leaked into output:\n%s", text)
	}
}

func TestListRenderedAcceptsActionArgs(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "oci"), 0o755); err != nil {
		t.Fatal(err)
	}
	apps := []byte("apps:\n  - name: pihole\n    type: rendered\n    path: applications/pihole\n")
	if err := os.WriteFile(filepath.Join(root, "oci", "apps.yaml"), apps, 0o644); err != nil {
		t.Fatal(err)
	}
	out := filepath.Join(t.TempDir(), "github_output")
	if err := os.WriteFile(out, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GITHUB_OUTPUT", out)

	rootCmd.SetArgs([]string{
		"argocd", "list-rendered",
		"--repo-url=https://github.com/example/homelab.git",
		"--target-revision=master",
		"--clusters-dir=" + root,
		"--argo-namespace=argocd",
		"--argo-project=default",
	})
	t.Cleanup(func() { rootCmd.SetArgs(nil) })

	if err := rootCmd.Execute(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "oci\tpihole\tapplications/pihole") {
		t.Fatalf("GITHUB_OUTPUT missing rendered app:\n%s", data)
	}
}

func TestGenerateRejectsMissingRepoURL(t *testing.T) {
	prev := argocdRepoURL
	t.Cleanup(func() { argocdRepoURL = prev })
	argocdRepoURL = ""

	err := argocdGenerateCmd.RunE(argocdGenerateCmd, nil)
	if err == nil || !strings.Contains(err.Error(), "--repo-url is required") {
		t.Fatalf("got %v, want --repo-url is required", err)
	}
}
