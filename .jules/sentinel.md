
### 2025-05-15 — Plaintext Secret in Git (Pi-hole)

**Finding:** The Pi-hole administrative password was stored in plaintext within `applications/pihole/pihole.nix` and subsequently rendered into `clusters/oci/rendered/pihole/result.json`.

**Learning:** While Kubenix makes it easy to define all resources in Nix, it also makes it easy to accidentally include secrets if not careful. The repository uses a pattern of manual secret creation for other sensitive services (like ExternalDNS and Grafana), but Pi-hole was an outlier.

**Prevention:** Always use `existingSecret` or refer to secrets that are created out-of-band for any sensitive data. Check rendered manifests specifically for `kind: Secret` with `stringData` or `data` populated with non-template values.
