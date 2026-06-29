# SABnzbd

Exposed externally at `https://sabnzbd.<BASE_DOMAIN>` behind ingress-nginx, with
**Auth0 SSO enforced by oauth2-proxy** (see `applications/oauth2-proxy/README.md`).
The annotations on this app's Ingress (`applications/sabnzbd/values.yaml`) bounce
unauthenticated browser requests to Auth0; in-cluster callers (*arr apps hitting
`sabnzbd.sabnzbd:8080`) bypass the ingress and are unaffected.

> `<BASE_DOMAIN>` is your public base domain. The real value lives in
> `values.yaml`; this README keeps it abstract.

A few SABnzbd settings are required for it to work correctly behind the reverse
proxy. These live in SABnzbd's own config (`Config → General`), **not** in
`values.yaml`.

## 1. Host whitelist

SABnzbd rejects requests whose `Host` header it doesn't recognize ("Access
denied - Hostname verification failed"). The ingress forwards the external
hostname, so it must be whitelisted.

`Config → General → Host whitelist`:

```
sabnzbd.<BASE_DOMAIN>
```

Add any other names used to reach it (e.g. `sabnzbd.sabnzbd` for cluster DNS) if
you see verification errors.

## 2. Local network ranges (skip internal login)

oauth2-proxy is the gate for WAN access, so SABnzbd's own login is redundant for
browser and in-cluster traffic. Whitelist the cluster pod + service CIDRs so
those requests skip SABnzbd's login. The source IP SABnzbd sees is the
ingress-nginx pod (browser) or the *arr pods (downloads) — all inside the pod
network.

`Config → General → Local network ranges`:

```
10.244.0.0/16,10.96.0.0/12
```

(Pod network `10.244.0.0/16`, service range `10.96.0.0/12` — Flannel/kubeadm
defaults; node `podCIDR` is a `/24` slice of the `/16`.) Verify with:

```bash
kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'             # pod range
kubectl -n sabnzbd get svc sabnzbd -o jsonpath='{.spec.clusterIP}'   # service range
```

## 3. Disable internal login (optional)

With the ranges above covering browser + *arr traffic, you can clear the
`Username`/`Password` under `Config → General → SABnzbd Web Server`. WAN access
remains gated by Auth0/oauth2-proxy. Keep them only if you intend to expose a
route without the oauth2-proxy annotations.

> Note: trusting the pod CIDR means anything routed through nginx is trusted.
> That's fine because the ingress requires Auth0 first — just don't add a SABnzbd
> ingress path without the `auth-url`/`auth-signin` annotations.
