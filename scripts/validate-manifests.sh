#!/usr/bin/env bash
#
# Validate Nix/kubenix-managed Kubernetes manifests against the API schema.
#
# Each kubenix app under applications/<app>/ builds to a result.json file that
# contains a Kubernetes List (or a single object). This script:
#   1. Optionally (re)builds each app with `nix build` when --build is passed
#      (or when the result.json is missing).
#   2. Normalises the List into individual manifests.
#   3. Runs kubeconform to confirm every manifest matches the API schema.
#
# This catches schema mistakes in the .nix definitions before they reach Argo
# CD / the cluster.
#
# Requirements: yq, kubeconform (and nix when using --build).
#
# Usage:
#   scripts/validate-manifests.sh                  # validate existing result.json files
#   scripts/validate-manifests.sh --build          # nix build every app first
#   scripts/validate-manifests.sh pihole ollama    # validate only the named apps
#   scripts/validate-manifests.sh --build pihole   # build + validate one app

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

KUBE_VERSION="${KUBE_VERSION:-1.28.0}"
CRD_SCHEMAS="https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

# --- argument parsing -------------------------------------------------------

BUILD=0
declare -a ONLY_APPS=()
for arg in "$@"; do
  case "${arg}" in
    --build) BUILD=1 ;;
    -*) echo "ERROR: unknown flag '${arg}'" >&2; exit 2 ;;
    *) ONLY_APPS+=("${arg}") ;;
  esac
done

# --- dependency checks ------------------------------------------------------

required_tools=(yq kubeconform)
[[ ${BUILD} -eq 1 ]] && required_tools+=(nix)
for tool in "${required_tools[@]}"; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "ERROR: required tool '${tool}' is not installed or not on PATH." >&2
    exit 127
  fi
done

# --- discover kubenix apps --------------------------------------------------

# A kubenix app is an applications/<app>/ directory containing a flake.nix.
discover_apps() {
  local flake
  for flake in applications/*/flake.nix; do
    [[ -e "${flake}" ]] || continue
    basename "$(dirname "${flake}")"
  done
}

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

while read -r app; do
  [[ -z "${app}" ]] && continue
  app_selected "${app}" || continue

  app_dir="applications/${app}"
  result="${app_dir}/result.json"

  if [[ ${BUILD} -eq 1 || ! -f "${result}" ]]; then
    echo "==> ${app}: nix build"
    rm -f "${result}"
    if ! ( cd "${app_dir}" && nix build --out-link result.json ) >/tmp/nix-build.out 2>&1; then
      echo "    nix build FAILED:" >&2
      sed 's/^/      /' /tmp/nix-build.out >&2
      failures=$((failures + 1))
      continue
    fi
  fi

  if [[ ! -f "${result}" ]]; then
    echo "ERROR: ${app}: ${result} not found (pass --build to generate it)" >&2
    failures=$((failures + 1))
    continue
  fi

  echo "==> ${app}: validating ${result}"

  # Normalise: a kubenix build is either a List (.items) or a single object.
  # `(.items // [.]) | .[]` yields each object; split_doc separates them into a
  # multi-document YAML stream that kubeconform reads from stdin.
  if ! yq -p=json -o=yaml '(.items // [.]) | .[] | split_doc' "${result}" >/tmp/nix-manifests.yaml 2>/tmp/nix-yq.err; then
    echo "    failed to normalise ${result}:" >&2
    sed 's/^/      /' /tmp/nix-yq.err >&2
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
        /tmp/nix-manifests.yaml; then
    echo "    kubeconform FAILED for ${app}" >&2
    failures=$((failures + 1))
    continue
  fi

  checked=$((checked + 1))
done < <(discover_apps)

echo
if [[ ${failures} -gt 0 ]]; then
  echo "Manifest validation FAILED: ${failures} app(s) with errors (${checked} passed)." >&2
  exit 1
fi

echo "Manifest validation passed: ${checked} app(s) validated."
