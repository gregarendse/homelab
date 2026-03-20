package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"text/template"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

// --- inventory types ---

type inventory struct {
	Apps []app `yaml:"apps"`
}

type app struct {
	Name      string `yaml:"name"`
	Type      string `yaml:"type"`
	Namespace string `yaml:"namespace"`
	Path      string `yaml:"path"`
	Helm      *helm  `yaml:"helm,omitempty"`
}

type helm struct {
	Kind           string   `yaml:"kind"`
	Path           string   `yaml:"path"`
	ReleaseName    string   `yaml:"releaseName"`
	RepoURL        string   `yaml:"repoURL"`
	Chart          string   `yaml:"chart"`
	TargetRevision string   `yaml:"targetRevision"`
	ValueFiles     []string `yaml:"valueFiles"`
}

func (a app) DestNamespace() string {
	if a.Namespace != "" {
		return a.Namespace
	}
	return a.Name
}

func (a app) GetReleaseName() string {
	if a.Helm != nil && a.Helm.ReleaseName != "" {
		return a.Helm.ReleaseName
	}
	return a.Name
}

func (a app) GetChartPath() string {
	if a.Helm != nil && a.Helm.Path != "" {
		return a.Helm.Path
	}
	return "server"
}

// --- Application generation ---

type appData struct {
	Name               string
	Cluster            string
	Namespace          string
	RepoURL            string
	TargetRevision     string
	ArgoNamespace      string
	ArgoProject        string
	Type               string
	HelmKind           string
	ChartPath          string
	ReleaseName        string
	Chart              string
	HelmRepoURL        string
	HelmTargetRevision string
	ValueFiles         string
}

var appTpl = template.Must(template.New("app").Parse(`# GENERATED FILE - DO NOT EDIT
# Source: clusters/{{ .Cluster }}/apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .Cluster }}-{{ .Name }}
  namespace: {{ .ArgoNamespace }}
  labels:
    homelab.gregarendse/cluster: "{{ .Cluster }}"
    homelab.gregarendse/app: "{{ .Name }}"
spec:
  project: {{ .ArgoProject }}
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ .Namespace }}
  # syncPolicy:
  #   automated:
  #     prune: true
  #     selfHeal: true
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
{{- if eq .Type "rendered" }}
  source:
    repoURL: {{ .RepoURL }}
    targetRevision: {{ .TargetRevision }}
    path: clusters/{{ .Cluster }}/rendered/{{ .Name }}
    directory:
      recurse: true
{{- else if eq .HelmKind "path" }}
  source:
    repoURL: {{ .RepoURL }}
    targetRevision: {{ .TargetRevision }}
    path: {{ .ChartPath }}
    helm:
      releaseName: {{ .ReleaseName }}
{{- if .ValueFiles }}
      valueFiles:
        - {{ .ValueFiles }}
{{- end }}
{{- else if eq .HelmKind "remote" }}
  source:
    repoURL: {{ .HelmRepoURL }}
    targetRevision: {{ .HelmTargetRevision }}
    chart: {{ .Chart }}
    helm:
      releaseName: {{ .ReleaseName }}
{{- end }}
`))

func appToData(a app, cluster string, repoURL, targetRevision, argoNamespace, argoProject string) (appData, error) {
	d := appData{
		Name:           a.Name,
		Cluster:        cluster,
		Namespace:      a.DestNamespace(),
		RepoURL:        repoURL,
		TargetRevision: targetRevision,
		ArgoNamespace:  argoNamespace,
		ArgoProject:    argoProject,
		Type:           a.Type,
	}
	if a.Helm != nil {
		d.HelmKind = a.Helm.Kind
		d.ReleaseName = a.GetReleaseName()
		switch a.Helm.Kind {
		case "path":
			d.ChartPath = a.GetChartPath()
			if len(a.Helm.ValueFiles) > 1 {
				return d, fmt.Errorf("app %s: multiple valueFiles not supported, got %d", a.Name, len(a.Helm.ValueFiles))
			}
			if len(a.Helm.ValueFiles) == 1 {
				d.ValueFiles = "../" + a.Helm.ValueFiles[0]
			}
		case "remote":
			d.Chart = a.Helm.Chart
			d.HelmRepoURL = a.Helm.RepoURL
			d.HelmTargetRevision = a.Helm.TargetRevision
		}
	}
	return d, nil
}

// --- helpers ---

func loadInventory(path string) (*inventory, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var inv inventory
	if err := yaml.Unmarshal(data, &inv); err != nil {
		return nil, fmt.Errorf("parsing %s: %w", path, err)
	}
	return &inv, nil
}

func clusterDirs(clustersDir string) ([]string, error) {
	entries, err := os.ReadDir(clustersDir)
	if err != nil {
		return nil, err
	}
	var dirs []string
	for _, e := range entries {
		if e.IsDir() {
			dirs = append(dirs, e.Name())
		}
	}
	sort.Strings(dirs)
	return dirs, nil
}

// --- cobra commands ---

var argocdClustersDir string
var argocdRepoURL string
var argocdTargetRevision string
var argocdArgoNamespace string
var argocdArgoProject string

var argocdCmd = &cobra.Command{
	Use:   "argocd",
	Short: "Argo CD application manifest helpers",
}

var argocdGenerateCmd = &cobra.Command{
	Use:   "generate",
	Short: "Generate Argo CD Application manifests from cluster inventories",
	RunE: func(cmd *cobra.Command, args []string) error {
		if argocdRepoURL == "" {
			return fmt.Errorf("--repo-url is required")
		}
		clusters, err := clusterDirs(argocdClustersDir)
		if err != nil {
			return err
		}
		for _, cluster := range clusters {
			inv, err := loadInventory(filepath.Join(argocdClustersDir, cluster, "apps.yaml"))
			if err != nil {
				return fmt.Errorf("failed to load inventory for cluster %s: %w", cluster, err)
			}
			renderedDir := filepath.Join(argocdClustersDir, cluster, "rendered")
			if err := os.MkdirAll(renderedDir, 0o755); err != nil {
				return err
			}
			for _, a := range inv.Apps {
				d, err := appToData(a, cluster, argocdRepoURL, argocdTargetRevision, argocdArgoNamespace, argocdArgoProject)
				if err != nil {
					return err
				}
				outPath := filepath.Join(renderedDir, a.Name+".yaml")
				f, err := os.Create(outPath)
				if err != nil {
					return err
				}
				if err := appTpl.Execute(f, d); err != nil {
					f.Close()
					return err
				}
				f.Close()
				fmt.Fprintf(os.Stderr, "Generated %s\n", outPath)
			}
		}
		return nil
	},
}

var argocdListRenderedCmd = &cobra.Command{
	Use:   "list-rendered",
	Short: "List rendered (Nix) apps as TSV: cluster, name, path",
	RunE: func(cmd *cobra.Command, args []string) error {
		clusters, err := clusterDirs(argocdClustersDir)
		if err != nil {
			return err
		}
		for _, cluster := range clusters {
			inv, err := loadInventory(filepath.Join(argocdClustersDir, cluster, "apps.yaml"))
			if err != nil {
				continue
			}
			for _, a := range inv.Apps {
				if a.Type == "rendered" {
					fmt.Printf("%s\t%s\t%s\n", cluster, a.Name, a.Path)
				}
			}
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(argocdCmd)
	argocdCmd.AddCommand(argocdGenerateCmd)
	argocdCmd.AddCommand(argocdListRenderedCmd)

	argocdCmd.PersistentFlags().StringVar(&argocdClustersDir, "clusters-dir", "clusters", "Path to clusters directory")

	argocdGenerateCmd.Flags().StringVar(&argocdRepoURL, "repo-url", "", "Git repository URL")
	argocdGenerateCmd.Flags().StringVar(&argocdTargetRevision, "target-revision", "master", "Git target revision")
	argocdGenerateCmd.Flags().StringVar(&argocdArgoNamespace, "argo-namespace", "argocd", "Argo CD namespace")
	argocdGenerateCmd.Flags().StringVar(&argocdArgoProject, "argo-project", "default", "Argo CD project")
}
