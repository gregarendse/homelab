### 2024-05-24 — MongoDB Hardening (NetworkPolicy, SecurityContext, Resources)

**Finding:** MongoDB was running without a NetworkPolicy (accessible to any pod in the cluster), had no resource limits defined, and was running with default (privileged/root) security settings.

**Learning:** The repository uses 'kubenix' for manifest generation. Since the 'nix' build tool is unavailable in the execution environment, changes to Nix source files in `applications/` must be manually mirrored in the compact single-line JSON manifests in `clusters/oci/rendered/`. Furthermore, the 'kubenix/hash' label must be updated for ArgoCD to detect the changes.

**Prevention:** Always add a 'name' label to namespaces in Nix and rendered manifests to facilitate cross-namespace NetworkPolicy selectors. Use 'jq -c' to maintain manifest formatting and include security rationale comments in Nix source files.
