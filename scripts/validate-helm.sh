#!/usr/bin/env bash
#
# Validate the shared "server" Helm chart and every app that renders it.
#
# What it does:
#   1. `helm lint` the shared server/ chart with each app's values.
#   2. `helm template` each path-type Helm app declared in clusters/*/apps.yaml
#      and pipe the rendered manifests through kubeconform for schema validation.
#
# This catches the classes of error that previously only surfaced at deploy
# time: malformed templates, bad value overrides, and manifests that don't
# match the Kubernetes API schema.
#
# Requirements: helm, yq, kubeconform (see scripts/README-validation.md).
#
# Usage:
#   scripts/validate-helm.sh                 # validate all helm apps
#   scripts/validate-helm.sh plex sonarr     # validate only the named apps

set -o errexit
set -o nounset
set -o pipefail

# Resolve repo root regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# Kubernetes version to validate manifests against. Keep in sync with the
# cluster (kubenix apps target 1.28 — see AGENTS.md).
KUBE_VERSION="${KUBE_VERSION:-1.28.0}"

# Schema locations for kubeconform. The default location covers built-in
# Kubernetes APIs; the CRDs-catalog covers common custom resources (VPA,
# cert-manager, Traefik, Argo CD, ...). Unknown CRDs are skipped rather than
# failing the build.
CRD_SCHEMAS="https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

# --- dependency checks ------------------------------------------------------

for tool in helm yq kubeconform; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "ERROR: required tool '${tool}' is not installed or not on PATH." >&2
    exit 127
  fi
done

# --- discover apps ----------------------------------------------------------

# Emits TSV rows: name<TAB>namespace<TAB>chartPath<TAB>valuesFile for every
# path-type Helm app across all cluster inventories.
discover_apps() {
  local inventory
  for inventory in clusters/*/apps.yaml; do
    [[ -e "${inventory}" ]] || continue
    yq -r '
      .apps[]
      | select(.type == "helm" and .helm.kind == "path")
      | [.name, (.namespace // .name), .helm.path, (.helm.valueFiles[0] // "")]
      | @tsv
    ' "${inventory}"
  done
}

# Optional positional args restrict validation to the named apps.
declare -a ONLY_APPS=("$@")

app_selected() {
  local name="$1"
  [[ ${#ONLY_APPS[@]} -eq 0 ]] && return 0
  local a
  for a in "${ONLY_APPS[@]}"; do
    [[ "${a}" == "${name}" ]] && return 0
  done
  return 1
}

# --- validation -------------------------------------------------------------

failures=0
checked=0

while IFS=$'\t' read -r name namespace chart values; do
  [[ -z "${name}" ]] && continue
  app_selected "${name}" || continue

  if [[ ! -f "${values}" ]]; then
    echo "ERROR: ${name}: values file '${values}' not found" >&2
    failures=$((failures + 1))
    continue
  fi

  echo "==> ${name} (chart=${chart}, namespace=${namespace})"

  # 1. helm lint — catches template/values problems early with clear messages.
  if ! helm lint "${chart}" --values "${values}" >/tmp/helm-lint.out 2>&1; then
    echo "    helm lint FAILED:" >&2
    sed 's/^/      /' /tmp/helm-lint.out >&2
    failures=$((failures + 1))
    continue
  fi

  # 2. helm template + kubeconform — catches schema violations.
  if ! helm template "${name}" "${chart}" \
        --namespace "${namespace}" \
        --values "${values}" >/tmp/helm-template.out 2>/tmp/helm-template.err; then
    echo "    helm template FAILED:" >&2
    sed 's/^/      /' /tmp/helm-template.err >&2
    failures=$((failures + 1))
    continue
  fi

  if ! kubeconform \
        -strict \
        -summary \
        -kubernetes-version "${KUBE_VERSION}" \
        -schema-location default \
        -schema-location "${CRD_SCHEMAS}" \
        -ignore-missing-schemas \
        /tmp/helm-template.out; then
    echo "    kubeconform FAILED for ${name}" >&2
    failures=$((failures + 1))
    continue
  fi

  checked=$((checked + 1))
done < <(discover_apps)

echo
if [[ ${failures} -gt 0 ]]; then
  echo "Helm validation FAILED: ${failures} app(s) with errors (${checked} passed)." >&2
  exit 1
fi

echo "Helm validation passed: ${checked} app(s) validated."
