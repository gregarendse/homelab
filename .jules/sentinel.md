### Risk Acceptance — Container Image Tags (:latest)

**Finding:** Container workloads using `:latest` tags or `imagePullPolicy: Always` (e.g. `unifi`, `hermes`).
**Learning:** The repository owner explicitly risk-accepts using `:latest` / floating tags for container images across workloads to benefit from automated updates.
**Prevention:** Do not flag or fix `:latest` container tags as security vulnerabilities in future Sentinel runs unless explicitly requested.
