# Direct OCI <-> Trinity WireGuard tunnel

Adds a direct WireGuard link between the `oci` cluster and `trinity`, so
`oci` no longer has to route through `home` (IPSec) to reach Trinity. `home`'s
IPSec link to OCI is unchanged.

```
OCI <--IPSec--> Home                OCI <--WireGuard--> Trinity   (new)
Home <--WireGuard--> Trinity        (unchanged)
```

## Why it looks like this

- OCI's `oci` cluster nodes run in an instance pool with **no public IP**
  (`assign_public_ip = false` in `compute.tf`), so the tunnel's public side has
  to be the existing NLB (`infrastructure/network/nlb.tf`), not a node
  directly.
- Reaching Trinity has to work for *any* pod on `oci`, not just one — that
  needs a real IP-forwarding gateway, which means the WireGuard interface has
  to live in a node's host network namespace, not an ordinary pod network
  namespace. That in turn means picking **one specific node** to run it.
- Because only that one node actually listens on UDP 51820, the NLB backend
  is pinned to that single instance (`var.wireguard_gateway_instance_name`)
  rather than registered against the whole pool — see the comment header in
  `infrastructure/network/wireguard-trinity.tf` for what goes wrong otherwise
  (OCI's FIVE_TUPLE hashing can deterministically route Trinity's fixed
  5-tuple to an instance with nothing listening, silently blackholing the
  tunnel).

**Known limitation:** if OCI ever recycles that specific pool instance
(instance pools can replace members), the pin breaks until you redo the two
manual steps below against the new instance/node. For a homelab pool this
should be rare, but it's a real gap — not something this PR tries to solve
with full automation (that's Cilium Egress Gateway territory, which felt like
too much machinery for one link).

## Apply order

1. `cd infrastructure/network && terraform apply` — creates the NLB
   listener/backend and the security-list rule. Note the output:
   ```
   terraform output wireguard_gateway_instance_private_ip
   terraform output wireguard_public_endpoint
   ```
2. Find the k8s node behind that instance and label it (one-time; only ever
   needs re-running if the pinned instance is replaced):
   ```
   kubectl --context oci get nodes -o wide   # match InternalIP to the instance's private IP
   kubectl --context oci label node <node-name> homelab.arendse.nom.za/wireguard-gateway=true
   ```
3. Generate keys (if you haven't already) and create the Secret — **not**
   managed by Terraform, so the private key never touches TF state, matching
   the convention in `applications/openclaw/openclaw.nix`:
   ```
   wg genkey | tee oci_wg_private.key | wg pubkey > oci_wg_public.key
   wg genkey | tee trinity_wg_private.key | wg pubkey > trinity_wg_public.key
   ```
   Build `wg0.conf` for the OCI side:
   ```ini
   [Interface]
   PrivateKey = <contents of oci_wg_private.key>
   Address = 10.90.0.1/30
   ListenPort = 51820
   PostUp   = sysctl -w net.ipv4.ip_forward=1
   PostUp   = ip route add <trinity_pod_cidr> dev wg0
   PostUp   = ip route add <trinity_svc_cidr> dev wg0
   PostDown = ip route del <trinity_pod_cidr> dev wg0
   PostDown = ip route del <trinity_svc_cidr> dev wg0

   [Peer]
   PublicKey = <contents of trinity_wg_public.key>
   AllowedIPs = 10.90.0.2/32, <trinity_pod_cidr>, <trinity_svc_cidr>
   PersistentKeepalive = 25
   ```
   Then:
   ```
   kubectl --context oci create namespace wireguard-trinity --dry-run=client -o yaml | kubectl apply -f -
   kubectl --context oci create secret generic wireguard-trinity-keys \
     --namespace wireguard-trinity \
     --from-file=wg0.conf=./wg0.conf
   ```
4. `cd infrastructure/kubernetes && terraform apply` — set
   `TF_VAR_wireguard_gateway_private_ip`, `TF_VAR_trinity_pod_cidr`,
   `TF_VAR_trinity_svc_cidr`, and the same
   `TF_VAR_wireguard_gateway_instance_name` used in step 1. Creates the
   Deployment and the route-propagation DaemonSet.
5. On Trinity (not Terraform-managed — on-prem, out of this repo's scope):
   ```ini
   [Interface]
   PrivateKey = <contents of trinity_wg_private.key>
   Address = 10.90.0.2/30
   PostUp   = sysctl -w net.ipv4.ip_forward=1
   PostUp   = ip route add <oci_pod_cidr> dev wg0
   PostUp   = ip route add <oci_svc_cidr> dev wg0
   PostDown = ip route del <oci_pod_cidr> dev wg0
   PostDown = ip route del <oci_svc_cidr> dev wg0

   [Peer]
   PublicKey = <contents of oci_wg_public.key>
   Endpoint = <wireguard_public_endpoint output from step 1>
   AllowedIPs = 10.90.0.1/32, <oci_pod_cidr>, <oci_svc_cidr>
   PersistentKeepalive = 25
   ```
   ```
   sudo systemctl enable --now wg-quick@wg0
   ```

## Verifying

```
kubectl --context oci -n wireguard-trinity get pods -o wide   # should be on the labeled node
kubectl --context oci -n wireguard-trinity logs deploy/wireguard-trinity
```
On the gateway node or on Trinity:
```
sudo wg show
```
From any pod in `oci` (not just the gateway node) to check the route
propagation DaemonSet worked:
```
kubectl --context oci run -it --rm wg-test --image=busybox --restart=Never -- ping <a trinity pod IP>
```

## 10.90.0.0/30 addressing

Placeholder tunnel subnet — swap for whatever doesn't collide with your VCN
CIDR, Tailscale's CGNAT range (100.64.0.0/10), or either cluster's pod/service
CIDRs.

## Always Free impact

None. No new compute, no new block storage — the gateway pod runs on
capacity you already have. The NLB listener/backend set and the security
list rule are both free (OCI doesn't charge per-hour or per-byte for
Site-to-Site VPN or NLB listeners within the existing NLB).
