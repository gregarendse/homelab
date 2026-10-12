#!/bin/bash

set -o errexit  #   Exit immediately if any command has a non-zero (error) status
set -o nounset  #   When set, a reference to any variable you haven't previously defined - with the exceptions of $* and $@ - is an error, and causes the program to immediately exit.
set -o pipefail #   This setting prevents errors in a pipeline from being masked. If any command in a pipeline fails, that return code will be used as the return code of the whole pipeline. By

# DEBUGGING
set -o xtrace   #   DEBUGGING - Print commands
set -o verbose  #   DEBUGGING - Pint shell input lines as they are read

DEBIAN_FRONTEND=noninteractive

# If the folder `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
KEYRINGS="/etc/apt/keyrings"
mkdir -p -m 755 "${KEYRINGS}"

apt update
apt install --yes \
    apt-transport-https \
    build-essential \
    ca-certificates \
    curl \
    fzf \
    gnupg \
    inotify-tools \
    jq \
    rsync \
    software-properties-common \
    unzip \
    vim \
    wget \
    zip \
    zsh

echo "Setting up kubectl"
KUBERNETES_VERSION="v1.32"
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VERSION}/deb/Release.key" | gpg --dearmor -o "${KEYRINGS}/kubernetes-apt-keyring.gpg" >/dev/null
# allow unprivileged APT programs to read this keyring
chmod 644 "${KEYRINGS}/kubernetes-apt-keyring.gpg"
# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo "deb [signed-by=${KEYRINGS}/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VERSION}/deb/ /" >/etc/apt/sources.list.d/kubernetes.list
# helps tools such as command-not-found to work correctly
chmod 644 /etc/apt/sources.list.d/kubernetes.list

echo "Setting up helm"
HELM_VERSION="v3.18.6"
HELM_ARCHIVE="helm-${HELM_VERSION}-linux-amd64.tar.gz"
curl -fsSLO "https://get.helm.sh/${HELM_ARCHIVE}"
curl -fsSL "https://get.helm.sh/${HELM_ARCHIVE}.sha256sum" | sha256sum --check
tar -xzf "${HELM_ARCHIVE}" linux-amd64/helm
install linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64 "${HELM_ARCHIVE}"

echo "Setting up terraform"
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o "${KEYRINGS}/hashicorp-archive-keyring.gpg" >/dev/null
# allow unprivileged APT programs to read this keyring
chmod 644 "${KEYRINGS}/hashicorp-archive-keyring.gpg"
echo "deb [signed-by=${KEYRINGS}/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" >/etc/apt/sources.list.d/hashicorp.list
# helps tools such as command-not-found to work correctly
chmod 644 /etc/apt/sources.list.d/hashicorp.list

# https://www.talos.dev/v1.11/talos-guides/install/talosctl/
echo "Setting up talosctl"
curl -fsSL https://talos.dev/install | sh

echo "Setting up eza"
curl -fsSL "https://raw.githubusercontent.com/eza-community/eza/main/deb.asc" | gpg --dearmor -o "${KEYRINGS}/gierens.gpg"
chmod 644 /etc/apt/keyrings/gierens.gpg
echo "deb [signed-by=${KEYRINGS}/gierens.gpg] http://deb.gierens.de stable main" | tee /etc/apt/sources.list.d/gierens.list
chmod 644 /etc/apt/sources.list.d/gierens.list

apt update
apt install --yes \
    eza \
    kubectl \
    terraform=1.10.5-1
# Pinning terraform version until this is resolved: https://github.com/hashicorp/terraform/issues/36704

echo "Setting up go-lang"
GO_VERSION="1.24.1"
export GOROOT="/usr/local/go"
wget "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
rm -rf "${GOROOT}"
tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
rm -rf "go${GO_VERSION}.linux-amd64.tar.gz"
export GOBIN=${GOROOT}/bin
export PATH=${PATH}:${GOBIN}
/usr/local/go/bin/go install github.com/k0sproject/k0sctl@latest
# https://github.com/derailed/k9s
/usr/local/go/bin/go install github.com/derailed/k9s@latest
# https://github.com/mikefarah/yq
go install github.com/mikefarah/yq/v4@latest

echo "Setting up zoxide"
ZOXIDE_TMP_DIR=$(mktemp -d)
pushd "${ZOXIDE_TMP_DIR}"
wget https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh
sh ./install.sh --bin-dir=/usr/local/bin --man-dir=/usr/local/share/man
popd
rm -rf ${ZOXIDE_TMP_DIR}

echo "Done"
