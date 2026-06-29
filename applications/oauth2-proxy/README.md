# oauth2-proxy — Auth0 SSO for the apps that lack native OIDC

The `*arr` apps (Sonarr, Radarr, Prowlarr, …) and most of the other web UIs have
no native OIDC/OAuth support, so they are protected at the edge instead.
`oauth2-proxy` runs once as an OIDC client against Auth0; `ingress-nginx`
delegates authentication to it via `auth-url`/`auth-signin` annotations on each
protected app's Ingress.

```
browser ──▶ ingress-nginx ──(auth subrequest)──▶ oauth2-proxy ──▶ Auth0
                │                                      │
                └────────── app (e.g. Sonarr) ◀────────┘ (only if authenticated)
```

A single login is shared across all protected apps because the session cookie is
scoped to the base domain.

> **Placeholders used in this doc** — substitute your own values:
> - `<BASE_DOMAIN>` — public base domain (e.g. the apex you serve apps under)
> - `<AUTH_HOST>` — the proxy's host, `auth.<BASE_DOMAIN>`
> - `<AUTH0_DOMAIN>` — Auth0 tenant domain, e.g. `<tenant>.<region>.auth0.com`
>
> The committed `values.yaml` and each app's `values.yaml` contain the real
> values; this README intentionally keeps them abstract.

## In-cluster API traffic is unaffected

Forward-auth only applies to traffic that goes **through the ingress**.
In-cluster integrations (Prowlarr → Sonarr/Radarr, download clients, etc.) use
cluster DNS such as `http://sonarr.sonarr:8989` and never touch the ingress, so
they bypass auth entirely. External access to every protected host — including
`/api` — requires an Auth0 login ("lock down everything").

## 1. Auth0 application setup

Create a **Regular Web Application** in the Auth0 tenant (`<AUTH0_DOMAIN>`):

- **Allowed Callback URLs:** `https://<AUTH_HOST>/oauth2/callback`
- **Allowed Logout URLs:** `https://<AUTH_HOST>`

The application's Client ID / Client Secret populate the `oauth2-proxy` Secret
below.

## 2. Create the oauth2-proxy Secret

The Secret is externally managed (kept out of Git / Argo). Keys are named as the
oauth2-proxy chart expects:

```bash
kubectl -n oauth2-proxy create secret generic oauth2-proxy \
  --from-literal=client-id='<auth0-client-id>' \
  --from-literal=client-secret='<auth0-client-secret>' \
  --from-literal=cookie-secret="$(openssl rand -base64 32 | tr -- '+/' '-_')"
```

`cookie-secret` must be a random 32-byte, URL-safe-base64 value; it encrypts the
session cookie. See `oauth2-proxy.example.yaml`. To rotate, update the Secret and
restart: `kubectl -n oauth2-proxy rollout restart deploy/oauth2-proxy`.

## 3. Deploy

`oauth2-proxy` is enrolled in `clusters/trinity/apps.yaml` as a remote Helm
chart with `applications/oauth2-proxy/values.yaml`. Sync it via Argo CD (or
`helm upgrade`) **before** the protected apps so the auth endpoint exists when
they start enforcing it.

## 4. Protect an app

Apps deployed with the shared `server/` chart are protected **automatically**:
the chart injects the forward-auth annotations on any app that defines
`ingress.hosts`. The auth host is configured once in `server/values.yaml`
(`ingress.auth.host`), so the domain isn't repeated across app values.

There is nothing to add per app. To **opt an app out** (internal-only apps, or
apps with their own auth you want to keep), set:

```yaml
ingress:
  auth:
    enabled: false
```

For an app on a different (non-`server`) chart, add the annotations manually:

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/auth-url: "https://<AUTH_HOST>/oauth2/auth"
    nginx.ingress.kubernetes.io/auth-signin: "https://<AUTH_HOST>/oauth2/start?rd=$scheme://$host$escaped_request_uri"
```

`rd=$scheme://$host$escaped_request_uri` must be the **full** original URL
(scheme + host + path). Passing only the path bounces the user back to
`<AUTH_HOST>` after login instead of the app.

## 5. Apps currently protected

Forward-auth is on by default for every `server`-chart app with an ingress
(subdomain-only host; legacy apex-path and dynamic-DNS hosts dropped): sonarr,
radarr, prowlarr, sabnzbd, deluge, tautulli, actual, echo.

**Not protected (no/empty ingress, so nothing is injected):**
- **plex** — uses its own accounts + direct client/app connections; exposed via
  NodePort, not an ingress.
- **wireguard** — VPN (`ingress: {}`), not a web UI.

If you ever give plex/wireguard an ingress, add `ingress.auth.enabled: false` to
keep them out of SSO.

### Disable each app's own login

oauth2-proxy authenticates at the edge, but apps still show their built-in login.
Delegate to the proxy per app:
- **Sonarr/Radarr/Prowlarr:** Settings → General → Security →
  Authentication = **External**, Required = **Disabled for Local Addresses**.
- **sabnzbd:** see `applications/sabnzbd/README.md` (host whitelist + local
  network ranges).
- **tautulli:** Settings → Web Interface → disable HTTP authentication.
- **deluge/actual:** keep their own login (lightweight / data-encryption key).

In-cluster API traffic is unaffected either way.
