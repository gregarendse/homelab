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

// --- ApplicationSet generation ---

type appSetElement struct {
	Name               string
	Namespace          string
	Type               string
	HelmKind           string
	ChartPath          string
	ReleaseName        string
	Chart              string
	HelmRepoURL        string
	HelmTargetRevision string
	ValueFiles         string
}

type appSetData struct {
	Cluster        string
	Elements       []appSetElement
	RepoURL        string
	TargetRevision string
	ArgoNamespace  string
	ArgoProject    string
}

// Uses <% %> delimiters for generation-time templating.
// {{ }} passes through literally as Argo CD ApplicationSet Go template expressions.
var appSetTpl = template.Must(template.New("appset").Delims("<%", "%>").Parse(`# GENERATED FILE - DO NOT EDIT
# Source: clusters/<% .Cluster %>/apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: <% .Cluster %>-apps
  namespace: <% .ArgoNamespace %>
  labels:
    homelab.gregarendse/cluster: "<% .Cluster %>"
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=zero"]
  generators:
    - list:
        elements:
<%- range .Elements %>
          - name: <% .Name %>
            namespace: <% .Namespace %>
            type: <% .Type %>
<%- if .HelmKind %>
            helmKind: <% .HelmKind %>
<%- end %>
<%- if .ReleaseName %>
            releaseName: <% .ReleaseName %>
<%- end %>
<%- if .ChartPath %>
            chartPath: <% .ChartPath %>
<%- end %>
<%- if .Chart %>
            chart: <% .Chart %>
<%- end %>
<%- if .HelmRepoURL %>
            helmRepoURL: <% .HelmRepoURL %>
<%- end %>
<%- if .HelmTargetRevision %>
            helmTargetRevision: <% .HelmTargetRevision %>
<%- end %>
<%- if .ValueFiles %>
            valueFiles: <% .ValueFiles %>
<%- end %>
<%- end %>
  template:
    metadata:
      name: <% .Cluster %>-{{.name}}
      namespace: <% .ArgoNamespace %>
      labels:
        homelab.gregarendse/cluster: "<% .Cluster %>"
        homelab.gregarendse/app: "{{.name}}"
    spec:
      project: <% .ArgoProject %>
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{.namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ApplyOutOfSyncOnly=true
      source:
        {{- if eq .type "rendered" }}
        repoURL: <% .RepoURL %>
        targetRevision: <% .TargetRevision %>
        path: clusters/<% .Cluster %>/rendered/{{.name}}
        directory:
          recurse: true
        {{- else if eq .helmKind "path" }}
        repoURL: <% .RepoURL %>
        targetRevision: <% .TargetRevision %>
        path: "{{.chartPath}}"
        helm:
          releaseName: "{{.releaseName}}"
          {{- if .valueFiles }}
          valueFiles:
            - "{{.valueFiles}}"
          {{- end }}
        {{- else if eq .helmKind "remote" }}
        repoURL: "{{.helmRepoURL}}"
        targetRevision: "{{.helmTargetRevision}}"
        chart: "{{.chart}}"
        helm:
          releaseName: "{{.releaseName}}"
        {{- end }}
`))

func appToElement(a app) (appSetElement, error) {
	e := appSetElement{
		Name:      a.Name,
		Namespace: a.DestNamespace(),
		Type:      a.Type,
	}
	if a.Helm != nil {
		e.HelmKind = a.Helm.Kind
		e.ReleaseName = a.GetReleaseName()
		switch a.Helm.Kind {
		case "path":
			e.ChartPath = a.GetChartPath()
			if len(a.Helm.ValueFiles) > 1 {
				return e, fmt.Errorf("app %s: multiple valueFiles not supported, got %d", a.Name, len(a.Helm.ValueFiles))
			}
			if len(a.Helm.ValueFiles) == 1 {
				e.ValueFiles = "../" + a.Helm.ValueFiles[0]
			}
		case "remote":
			e.Chart = a.Helm.Chart
			e.HelmRepoURL = a.Helm.RepoURL
			e.HelmTargetRevision = a.Helm.TargetRevision
		}
	}
	return e, nil
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
	Short: "Generate Argo CD ApplicationSet from cluster inventories",
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
			var elements []appSetElement
			for _, a := range inv.Apps {
				e, err := appToElement(a)
				if err != nil {
					return err
				}
				elements = append(elements, e)
			}
			outPath := filepath.Join(argocdClustersDir, cluster, "appset.yaml")
			f, err := os.Create(outPath)
			if err != nil {
				return err
			}
			defer f.Close()
			if err := appSetTpl.Execute(f, appSetData{
				Cluster:        cluster,
				Elements:       elements,
				RepoURL:        argocdRepoURL,
				TargetRevision: argocdTargetRevision,
				ArgoNamespace:  argocdArgoNamespace,
				ArgoProject:    argocdArgoProject,
			}); err != nil {
				return err
			}
			fmt.Fprintf(os.Stderr, "Generated %s\n", outPath)
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
