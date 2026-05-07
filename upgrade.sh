#!/usr/bin/env bash

set -o errexit  # Used to exit upon error, avoiding cascading errors
set -o nounset  # Treat unset variables as an error
set -o pipefail # Unveils hidden failures
# set -o xtrace   # Print commands and their arguments as they are executed.

application="${1:-}"
user="${2:-}"

function help() {
    echo """
    Usage: ${0} <application>

    Available applications are: $(find applications -mindepth 1 -maxdepth 1 -type d -printf '%f ')
    """
    exit 1
}

[[ -z "${application}" ]] && help || echo "Application: ${application}"
[[ -z "${user}" ]] && user="${application}"
echo "User: ${user}"

[[ ! -d "applications/${application}" ]] && help

if [ ! -d "/mnt/data/${application}" ];
then
    echo "No 'home' directory"
fi

helm upgrade --install "${application}" server --values="applications/${application}/values.yaml" --namespace="${application}" --create-namespace --atomic
