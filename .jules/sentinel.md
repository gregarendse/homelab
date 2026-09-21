
### 2026-09-21 — Pin Hermes Agent Image Tag

**Finding:** `applications/hermes/hermes.nix` was using `nousresearch/hermes-agent:latest` with `imagePullPolicy: Always`.
**Learning:** Using mutable `:latest` tags with `imagePullPolicy: Always` introduces supply-chain vulnerabilities and non-deterministic deployments in GitOps workflows.
**Prevention:** Always pin image tags to explicit version releases (e.g. `v2026.9.14`) and ensure `imagePullPolicy: IfNotPresent` is set for rendered workloads.
