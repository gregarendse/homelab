#!/bin/sh

# set -o errexit  #   Exit immediately if any command has a non-zero (error) status
# set -o nounset  #   When set, a reference to any variable you haven't previously defined - with the exceptions of $* and $@ - is an error, and causes the program to immediately exit.
# set -o pipefail #   This setting prevents errors in a pipeline from being masked. If any command in a pipeline fails, that return code will be used as the return code of the whole pipeline. By

# DEBUGGING
# set -o xtrace   #   DEBUGGING - Print commands
# set -o verbose  #   DEBUGGING - Pint shell input lines as they are read


if [ ! -d "${HOME}/.ssh" ]; then
    mkdir -p ${HOME}/.ssh
fi

ssh-keyscan github.com >> "${HOME}/.ssh/known_hosts"

echo "${FILE_SSH_ID_ED25519}" | base64 --decode > "${HOME}/.ssh/id_ed25519"
chmod 400 ${HOME}/.ssh/id_ed25519

echo "${FILE_SSH_ID_RSA}" | base64 --decode > "${HOME}/.ssh/id_rsa"
chmod 400 ${HOME}/.ssh/id_rsa

if [ ! -d "${HOME}/.oci" ]; then
    mkdir -p ${HOME}/.oci
fi

echo "${FILE_OCI_KEY}" | base64 --decode > "${HOME}/.oci/oci_api_key.pem"
chmod 400 ${HOME}/.oci/oci_api_key.pem


if [ ! -d "${HOME}/.kube" ]; then
    mkdir -p ${HOME}/.kube
fi

echo "${FILE_KUBE_CONFIG}" | base64 --decode > "${HOME}/.kube/config"
chmod 600 ${HOME}/.kube/config

export TF_VAR_tenancy_ocid="${OCI_TENANCY_OCID}"
export TF_VAR_user_ocid="${OCI_USER_OCID}"
export TF_VAR_fingerprint="${OCI_FINGERPRINT}"
export TF_VAR_region="${OCI_REGION}"
export TF_VAR_tailscale_oauth_client_id="${TS_OAUTH_CLIENT_ID}"
export TF_VAR_tailscale_oauth_client_secret="${TS_OAUTH_CLIENT_SECRET}"
export TF_VAR_tailscale_tailnet="${TS_TAILNET}"
export TF_VAR_public_key_path="${HOME}/.ssh/id_ed25519.pub"

cat <<EOF > "${HOME}/.oci/config"
[DEFAULT]
user=${OCI_USER_OCID}
fingerprint=${OCI_FINGERPRINT}
key_file=${HOME}/.oci/oci_api_key.pem
tenancy=${OCI_TENANCY_OCID}
region=${OCI_REGION}
EOF
