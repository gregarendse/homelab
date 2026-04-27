#!/usr/bin/env bash

set -o noclobber  # Avoid overlay files (echo "hi" > foo)
set -o errexit    # Used to exit upon error, avoiding cascading errors
set -o pipefail   # Unveils hidden failures
set -o nounset    # Exposes unset variables

# Change to the script directory
cd "$(dirname "$0")"

declare -a EXTRA_TLS_SANS=()
if [[ -n "${K3S_EXTRA_TLS_SANS:-}" ]]; then
    IFS=' ' read -r -a EXTRA_TLS_SANS <<< "${K3S_EXTRA_TLS_SANS}"
    echo "Additional TLS SANs: ${EXTRA_TLS_SANS[*]}"
fi

function fetch_manifests() {
    local RELEASE="v1.33.0"
    local manifests=(
        "oci-cloud-controller-manager-rbac.yaml"
        "oci-cloud-controller-manager.yaml"
        "oci-csi-node-rbac.yaml"
        "oci-csi-controller-driver.yaml"
        "oci-csi-node-driver.yaml"
        "storage-class.yaml"
    )

    mkdir -p manifests

    for manifest in "${manifests[@]}"; do
        if [[ -f "manifests/${manifest}" ]]; then
            echo "Manifest manifests/${manifest} already exists, skipping download"
            continue
        fi
        curl -sL "https://github.com/oracle/oci-cloud-controller-manager/releases/download/${RELEASE}/${manifest}" -o "manifests/${manifest}"
    done

    # Fetch CSI snapshot CRDs
    local snapshot_crds=(
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml"
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml"
        "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml"
    )
    for crd in "${snapshot_crds[@]}"; do
        local filename=$(basename "$crd")
        if [[ -f "manifests/${filename}" ]]; then
            echo "CRD manifests/${filename} already exists, skipping download"
            continue
        fi
        curl -sL "$crd" -o "manifests/${filename}"
    done
}

# If the user passes the --fetch-manifests argument, fetch the manifests and exit.
if [[ "${1:-}" == "--fetch-manifests" ]]; then
    echo "Fetching manifests"
    fetch_manifests
    exit 0
fi

function build_k3s_config() {
  local tailscale_addr="$1"
  local user="$2"

  echo "Fetching instance metadata from ${tailscale_addr}"
  local METADATA_JSON=$(ssh ${user}@${tailscale_addr} "curl -s -H 'Authorization: Bearer Oracle' 'http://169.254.169.254/opc/v2/instance/'")
  local REGION=$(echo "${METADATA_JSON}" | jq --raw-output '.region')
  local SHAPE=$(echo "${METADATA_JSON}" | jq --raw-output '.shape')
  local INSTANCE_ID=$(echo "${METADATA_JSON}" | jq --raw-output '.id')
  local AVAILABILITY_DOMAIN=$(echo "$METADATA_JSON" | jq --raw-output '.availabilityDomain')
  AVAILABILITY_DOMAIN=${AVAILABILITY_DOMAIN##*:}
  local FAULT_DOMAIN=$(echo "$METADATA_JSON" | jq --raw-output '.faultDomain')
  local NODE_EXTERNAL_IP=$(ssh ${user}@${tailscale_addr} ip addr show |grep -A 3 'enp0' | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)

    local tls_sans=(
        "kubernetes.arendse.nom.za"
        "${tailscale_addr}"
        "${NODE_EXTERNAL_IP}"
    )
    if [[ ${#EXTRA_TLS_SANS[@]} -gt 0 ]]; then
        tls_sans+=("${EXTRA_TLS_SANS[@]}")
    fi

    local tls_san_yaml=""
    for san in "${tls_sans[@]}"; do
        tls_san_yaml+="- ${san}"$'\n'
    done
    tls_san_yaml=${tls_san_yaml%$'\n'}

# "Failed to scrape node" err="Get \"https://10.100.1.148:10250/metrics/resource\": tls: failed to verify certificate: x509: certificate is valid for 127.0.0.1, 100.105.108.104, fd7a:115c:a1e0::a001:6c74, not 10.100.1.148" node="ubuntu-4"
# "Failed to scrape node" err="Get \"https://10.100.1.211:10250/metrics/resource\": dial tcp 10.100.1.211:10250: connect: no route to host" node="ubuntu-3"

  echo "Building k3s config for instance ${INSTANCE_ID} in ${REGION}, ${AVAILABILITY_DOMAIN}, ${FAULT_DOMAIN}, shape ${SHAPE}"
  ssh ${USER}@${TAILSCALE_ADDR} sudo mkdir -p /etc/rancher/k3s
  ssh ${USER}@${TAILSCALE_ADDR} 'sudo tee /etc/rancher/k3s/config.yaml > /dev/null' <<EOF
---
flannel-backend: none
disable-network-policy: true
tls-san:
${tls_san_yaml}
disable-cloud-controller: true
kube-controller-manager-arg:
- cloud-provider=external
kubelet-arg:
- cloud-provider=external
- provider-id=${INSTANCE_ID}
node-label:
- topology.kubernetes.io/region=${REGION}
- topology.kubernetes.io/zone=${AVAILABILITY_DOMAIN}
- oci/region=${REGION}
- oci/az=${AVAILABILITY_DOMAIN}
- oci/fd=${FAULT_DOMAIN}
- oci/shape=${SHAPE}
EOF

    echo "Configuring iptables rules for intra-cluster and service traffic on ${TAILSCALE_ADDR}"
    ssh ${USER}@${TAILSCALE_ADDR} sudo tee /etc/iptables/rules.custom.v4 > /dev/null <<EOF
# CLOUD_IMG: This file was created/modified by the Cloud Image build process
# iptables configuration for Oracle Cloud Infrastructure

# See the Oracle-Provided Images section in the Oracle Cloud Infrastructure
# documentation for security impact of modifying or removing these rule

*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [463:49013]
:InstanceServices - [0:0]
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 2377 -j ACCEPT

-A INPUT -p tcp -m state --state NEW -m tcp --dport 2379 -j ACCEPT -m comment --comment "etcd server client API"
-A INPUT -p tcp -m state --state NEW -m tcp --dport 10258 -j ACCEPT -m comment --comment "OCI cloud controller manager"
-A INPUT -p tcp -m state --state NEW -m tcp --dport 10250 -j ACCEPT -m comment --comment "k3s-server kubelet"
-A INPUT -p tcp -m state --state NEW -m tcp --dport 6443 -j ACCEPT -m comment --comment "Kubernetes API server"
-A INPUT -p tcp -m state --state NEW -m tcp --dport 30000:32767 -j ACCEPT -m comment --comment "NodePort services"

-A INPUT -s 10.100.0.0/16 -j ACCEPT -m comment --comment "Allow traffic from VCN"
-A FORWARD -s 10.100.0.0/16 -j ACCEPT -m comment --comment "Allow traffic from VCN"

-A INPUT -s 100.64.0.0/10 -j ACCEPT -m comment --comment "Allow traffic from Tailscale"
-A FORWARD -s 100.64.0.0/10 -j ACCEPT -m comment --comment "Allow traffic from Tailscale"

-A INPUT -j REJECT --reject-with icmp-host-prohibited

-A FORWARD -j REJECT --reject-with icmp-host-prohibited

-A OUTPUT -d 169.254.0.0/16 -j InstanceServices

-A InstanceServices -d 169.254.0.2/32 -p tcp -m owner --uid-owner 0 -m tcp --dport 3260 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.2.0/24 -p tcp -m owner --uid-owner 0 -m tcp --dport 3260 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.4.0/24 -p tcp -m owner --uid-owner 0 -m tcp --dport 3260 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.5.0/24 -p tcp -m owner --uid-owner 0 -m tcp --dport 3260 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.0.2/32 -p tcp -m tcp --dport 80 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.169.254/32 -p udp -m udp --dport 53 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.169.254/32 -p tcp -m tcp --dport 53 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.0.3/32 -p tcp -m owner --uid-owner 0 -m tcp --dport 80 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.0.4/32 -p tcp -m tcp --dport 80 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.169.254/32 -p tcp -m tcp --dport 80 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.169.254/32 -p udp -m udp --dport 67 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.169.254/32 -p udp -m udp --dport 69 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.169.254/32 -p udp --dport 123 -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j ACCEPT
-A InstanceServices -d 169.254.0.0/16 -p tcp -m tcp -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j REJECT --reject-with tcp-reset
-A InstanceServices -d 169.254.0.0/16 -p udp -m udp -m comment --comment "See the Oracle-Provided Images section in the Oracle Cloud Infrastructure documentation for security impact of modifying or removing this rule" -j REJECT --reject-with icmp-port-unreachable

COMMIT
EOF
    ssh ${USER}@${TAILSCALE_ADDR} "sudo iptables-restore < /etc/iptables/rules.custom.v4"
}

USER="ubuntu"
K8S_VERSION=" v1.33.5+k3s1"
declare -a TAILSCALE_ADDRS
TAILSCALE_ADDRS+=($(tailscale status --peers --json | jq -r '.Peer | to_entries[] | select( .value.HostName | startswith("ubuntu") ) | select(.value.Online == true) | .value.TailscaleIPs[0]' | xargs))
echo "Tailscale IPs: ${TAILSCALE_ADDRS[@]}"

# If the parameter --reinstall is given, first uninstall k3s on all nodes.
if [[ "${1:-}" == "--reinstall" ]]; then
  echo "Reinstall mode: Uninstalling k3s on all nodes"
    for TAILSCALE_ADDR in "${TAILSCALE_ADDRS[@]}"; do
        echo "Uninstalling k3s on ${TAILSCALE_ADDR}"
        ssh ${USER}@${TAILSCALE_ADDR} sudo /usr/local/bin/k3s-uninstall.sh || echo "k3s not installed on ${TAILSCALE_ADDR}, continuing"
    done
fi

# ------------------------------------------------------------------------------
# Install k3s on the first node, then join the other nodes to the cluster.
# ------------------------------------------------------------------------------

TAILSCALE_ADDR="${TAILSCALE_ADDRS[0]}"
echo "Installing k3s on ${TAILSCALE_ADDR}"
build_k3s_config "${TAILSCALE_ADDR}" "$USER"
k3sup install \
    --ip "${TAILSCALE_ADDR}" \
    --user "$USER" \
    --cluster \
    --no-extras \
    --k3s-extra-args "--advertise-address ${TAILSCALE_ADDR}" \
    --local-path $HOME/.kube/config
# ------------------------------------------------------------------------------
# Join the other nodes to the cluster.
# ------------------------------------------------------------------------------

TAILSCALE_ADDR="${TAILSCALE_ADDRS[1]}"
echo "Installing k3s on ${TAILSCALE_ADDR}"
build_k3s_config "${TAILSCALE_ADDR}" "$USER"
k3sup join \
    --ip="${TAILSCALE_ADDR}" \
    --user="$USER" \
    --server \
    --server-ip="${TAILSCALE_ADDRS[0]}" \
    --no-extras \
    --k3s-extra-args="" \

echo "Setting up OCI cloud controller manager"
kubectl create secret generic oci-cloud-controller-manager \
     --namespace=kube-system \
     --from-file=cloud-provider.yaml=config.yaml \
     || echo "Secret oci-cloud-controller-manager already exists, skipping creation"

kubectl apply -f manifests/oci-cloud-controller-manager-rbac.yaml
kubectl apply -f manifests/oci-cloud-controller-manager.yaml

echo "Installing Cilium"
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.18.2 \
   --namespace=kube-system \
   --set operator.replicas=1


kubectl port-forward -n kube-system svc/cilium-operator 9090:9090 &