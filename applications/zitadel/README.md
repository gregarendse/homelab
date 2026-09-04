# Zitadel Cloud — OIDC provider PoC

A proof-of-concept to trial **[Zitadel Cloud](https://zitadel.com/)** as an
alternative OIDC identity provider to the current Auth0 setup, without disturbing
anything that already works.

## What this PoC deploys

Zitadel itself is **fully hosted by Zitadel Cloud** — there is nothing to run in
the cluster for it. The only in-cluster pieces are a small, isolated test rig:

| Component | Namespace | Host | Purpose |
|---|---|---|---|
| `oauth2-proxy-zitadel` | `oauth2-proxy-zitadel` | `auth-zitadel.arendse.nom.za` | A **second** oauth2-proxy, pointed at Zitadel Cloud. Independent of the Auth0 proxy. |
| `zitadel-echo` | `zitadel-echo` | `zitadel-echo.arendse.nom.za` | Throwaway `http-echo` app whose edge auth points at the Zitadel proxy. |

```
browser ─▶ ingress-nginx ─(auth subrequest)─▶ oauth2-proxy-zitadel ─▶ Zitadel Cloud
                │                                       │
                └──────── zitadel-echo ◀────────────────┘ (only if authenticated)
```

The production `oauth2-proxy` (Auth0) and every app it protects are **untouched**.
Only `zitadel-echo` exercises Zitadel. When you're done, tear the rig down (see
[Teardown](#5-teardown)) — no lasting changes to the existing SSO.

## 1. Set up Zitadel Cloud

1. Create an account and a **new instance** at <https://zitadel.cloud/>. Note the
   instance URL — it looks like `https://my-instance-abc123.zitadel.cloud`. This
   is your **OIDC issuer** (discovery lives at
   `<issuer>/.well-known/openid-configuration`).
2. In the Console, create (or use the default) **Organization** and **Project**.
3. Inside the project, create a new **Application**:
   - **Type:** Web
   - **Authentication Method:** `POST` or `BASIC` (i.e. a confidential client
     with a client secret — oauth2-proxy is a confidential client).
   - **Grant type:** Authorization Code (default for Web).
   - **Redirect URI:** `https://auth-zitadel.arendse.nom.za/oauth2/callback`
   - **Post Logout URI:** `https://auth-zitadel.arendse.nom.za`
4. Save, then copy the generated **Client ID** and **Client Secret**.
5. Make sure your test user has an **email set and verified** (oauth2-proxy keys
   the allow-list off `email`). Any user in the org works for the PoC.

> Zitadel returns `email`/`profile` claims in the ID token, which is all
> oauth2-proxy needs — no extra API/audience configuration is required for this
> flow.

## 2. Point the proxy at your issuer

Edit `applications/oauth2-proxy-zitadel/values.yaml` and replace the placeholder
issuer with your instance URL:

```yaml
extraArgs:
  oidc-issuer-url: https://my-instance-abc123.zitadel.cloud
```

## 3. Create the proxy Secret

Same shape as the Auth0 proxy's Secret — kept out of Git and out of Argo's
managed objects:

```bash
kubectl -n oauth2-proxy-zitadel create secret generic oauth2-proxy-zitadel \
  --from-literal=client-id='<zitadel-client-id>' \
  --from-literal=client-secret='<zitadel-client-secret>' \
  --from-literal=cookie-secret="$(openssl rand -base64 32 | tr -- '+/' '-_')"
```

`cookie-secret` must be a random 32-byte, URL-safe-base64 value. To rotate later,
update the Secret and `kubectl -n oauth2-proxy-zitadel rollout restart deploy/oauth2-proxy-zitadel`.

## 4. Deploy & test

Both apps are enrolled in `clusters/trinity/apps.yaml` and rendered under
`clusters/trinity/rendered/`, so Argo CD will pick them up on merge. To deploy
directly instead:

```bash
# The isolated Zitadel proxy (REMOTE oauth2-proxy chart — NOT the server chart,
# so do not use ./upgrade.sh for this one). With --repo the chart arg is just
# the chart name.
helm upgrade --install oauth2-proxy-zitadel oauth2-proxy \
  --repo https://oauth2-proxy.github.io/manifests --version 10.7.0 \
  --namespace oauth2-proxy-zitadel --create-namespace \
  --values applications/oauth2-proxy-zitadel/values.yaml

# The test app uses the shared server chart, so ./upgrade.sh is correct here.
./upgrade.sh zitadel-echo
```

Then, in a browser, open **https://zitadel-echo.arendse.nom.za**. You should be
redirected to the Zitadel Cloud login, and after signing in, land on the
`http-echo` response. That confirms the full Zitadel → oauth2-proxy → app flow.

Quick checks if something misbehaves:

```bash
# Proxy reached Zitadel's discovery doc on startup?
kubectl -n oauth2-proxy-zitadel logs deploy/oauth2-proxy-zitadel | grep -i oidc

# Discovery endpoint resolves from your machine?
curl -s https://my-instance-abc123.zitadel.cloud/.well-known/openid-configuration | jq .issuer
```

Common gotchas:
- **Redirect URI mismatch** — the URI in Zitadel must exactly equal
  `https://auth-zitadel.arendse.nom.za/oauth2/callback`.
- **`issuer did not match`** — `oidc-issuer-url` must be the exact instance base
  URL with no trailing path and no trailing slash.
- **403 after login** — the user has no email, or `email-domain` is too strict.

## Promote to production (optional)

If the PoC succeeds and you want Zitadel to replace Auth0 for the *real* apps,
you don't keep this rig — you just repoint the production proxy:

1. Register a second redirect URI on the Zitadel app (or a new app):
   `https://auth.arendse.nom.za/oauth2/callback`.
2. In `applications/oauth2-proxy/values.yaml`, change `oidc-issuer-url` to the
   Zitadel issuer and `redirect-url` to `https://auth.arendse.nom.za/oauth2/callback`.
3. Update the existing `oauth2-proxy` Secret with the Zitadel client id/secret.
4. `kubectl -n oauth2-proxy rollout restart deploy/oauth2-proxy`.

To roll back, revert those two values and restore the Auth0 client credentials.

## 5. Teardown

```bash
helm uninstall oauth2-proxy-zitadel -n oauth2-proxy-zitadel
helm uninstall zitadel-echo -n zitadel-echo
kubectl delete namespace oauth2-proxy-zitadel zitadel-echo
```

Then remove the two `zitadel-echo` / `oauth2-proxy-zitadel` entries from
`clusters/trinity/apps.yaml`, delete `applications/oauth2-proxy-zitadel/` and
`applications/zitadel-echo/`, regenerate the rendered manifests
(`src/go/ci` → `ci argocd generate ...`), and delete the corresponding
`clusters/trinity/rendered/*.yaml` files. Nothing about the Auth0 setup changes.
