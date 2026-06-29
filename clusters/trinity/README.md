# Bootstrapping Argo CD on trinity

`trinity` is the on-prem home-lab cluster. Unlike the OCI cluster (which installs
Argo CD via Terraform in `infrastructure/kubernetes/argocd.tf`), trinity is
bootstrapped manually with Helm. After that, Argo CD watches
`clusters/trinity/rendered/` on `master` and manages every app.

## TLS / cert-manager note (important on trinity)

trinity serves ingress through **ingress-nginx** (IngressClass `public`). The
`letsencrypt-prod` ClusterIssuer's HTTP-01 solver must target `public` — if it's
set to `traefik` (a leftover from the old Traefik setup), cert-manager creates
the ACME challenge Ingress with the wrong class, nginx never serves
`/.well-known/acme-challenge/...`, and **new** certificates never issue (existing
hosts keep working because their cert is already cached in a Secret).

The corrected issuer is tracked at `clusters/trinity/cluster-issuer.yaml`. Verify
the email + account-key name match your existing account, then apply it:

```bash
# Preserve your existing ACME account key name (avoids re-registration):
kubectl get clusterissuer letsencrypt-prod \
  -o jsonpath='{.spec.acme.privateKeySecretRef.name}'; echo

kubectl apply -f clusters/trinity/cluster-issuer.yaml

# Re-trigger any stuck challenges so they recreate with the nginx class:
kubectl -n argocd delete challenges.acme.cert-manager.io --all
```

Also ensure the ArgoCD hostname is a **single-level** subdomain
(`trinity-argocd.arendse.nom.za`, not `trinity.argocd.arendse.nom.za`) when the
record is Cloudflare-proxied — Cloudflare's Universal SSL wildcard only covers one
label, so a two-level proxied host fails the TLS handshake at the edge.

## 1. Install Argo CD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --version 9.4.15 \
  --namespace argocd \
  --create-namespace \
  --atomic \
  --values clusters/trinity/argocd.yaml
```

(Version pinned to match the OCI install in `infrastructure/kubernetes/argocd.tf`.)

## 2. Apply the root Application

This points Argo CD at the pre-rendered Application manifests in
`clusters/trinity/rendered/` (read from `master` on GitHub).

```bash
kubectl apply -f clusters/trinity/root.yaml
```

Argo will create one child Application per file in `rendered/` (actual, deluge,
sonarr, oauth2-proxy, …).

## 3. Log in

Get the initial admin password and open the UI at
`https://trinity.argocd.arendse.nom.za`:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
# user: admin
```

Change the password after first login (User Info → Update Password), then the
initial secret can be deleted.

## SSO via Auth0 (native OIDC)

Argo CD authenticates users against Auth0 directly using its **native OIDC**
support (configured in `configs.cm.oidc.config` in `argocd.yaml`). It is **not**
put behind oauth2-proxy — forward-auth would break the Argo CLI/API/gRPC, and
native OIDC also gives RBAC role mapping. The built-in `admin` account stays as a
break-glass fallback.

> `<BASE_DOMAIN>` = your public base domain, `<AUTH0_DOMAIN>` = the Auth0 tenant
> domain. Real values live in `argocd.yaml`.

### Auth0 application

Create a **Regular Web Application** in the Auth0 tenant (`<AUTH0_DOMAIN>`):

- **Allowed Callback URLs:**
  `https://trinity.argocd.<BASE_DOMAIN>/auth/callback`, `http://localhost:8085/auth/callback`
  (the second one is for `argocd login --sso` from the CLI)
- **Allowed Logout URLs:** `https://trinity.argocd.<BASE_DOMAIN>`

### Secret

The client credentials are pulled from an externally-managed Secret (kept out of
Git). It **must** carry the `app.kubernetes.io/part-of: argocd` label for the
`$argocd-auth0:clientID` / `$argocd-auth0:clientSecret` references in
`argocd.yaml` to resolve:

```bash
kubectl -n argocd create secret generic argocd-auth0 \
  --from-literal=clientID='<auth0-client-id>' \
  --from-literal=clientSecret='<auth0-client-secret>'
kubectl -n argocd label secret argocd-auth0 app.kubernetes.io/part-of=argocd
```

After creating/rotating the Secret, restart the server and repo-server:

```bash
kubectl -n argocd rollout restart deploy/argocd-server
```

### RBAC

`configs.rbac` in `argocd.yaml` matches on the `email` claim and grants
`role:admin` to a single email (`policy.default: ''` denies everyone else). Add
more lines to `policy.csv` to grant access to other users.

## Auto-sync is off by default

`root.yaml` and the rendered child apps leave `syncPolicy.automated` commented
out, so apps show as **OutOfSync** until you Sync them manually (UI button or
`argocd app sync <name>`). To enable hands-off GitOps later, uncomment the
`automated` block (`prune: true`, `selfHeal: true`) in `root.yaml` and re-apply.

## Important: Argo reads from `master`, not your working tree

Argo CD pulls manifests and chart sources from
`https://github.com/gregarendse/homelab.git` `master`. **Commit and push** before
syncing — local changes are invisible to Argo until they land on `master`.

## Relationship to the manual `upgrade.sh` flow

`./upgrade.sh <app>` does a direct `helm upgrade` from your laptop and is fine for
quick iteration. Once Argo manages an app, prefer syncing through Argo so the two
don't fight over the release (Argo's `selfHeal`, if enabled, will revert manual
changes back to what's on `master`).
