# GitOps (Argo CD) – per cluster

- CI renders **kubenix/Nix** apps into `clusters/<cluster>/rendered/<app>/`
- CI generates one Argo CD `ApplicationSet` per cluster at `clusters/<cluster>/appset.yaml`
- Each cluster runs its own Argo CD; the ApplicationSet creates all Applications automatically

## Inventory

- `clusters/trinity/apps.yaml`
- `clusters/oci/apps.yaml`

## Bootstrap (per cluster)

Apply the generated ApplicationSet to the cluster:

```bash
kubectl apply -f clusters/<cluster>/appset.yaml
```

Or create a root Application that syncs it:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: trinity-root
  namespace: argocd
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  source:
    repoURL: https://github.com/gregarendse/homelab.git
    targetRevision: master
    path: clusters/trinity
    directory:
      include: "appset.yaml"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

OCI is identical except `path: clusters/oci`.
