#!/usr/bin/env bash
#
# list-auth0-ids.sh — print the IDs of every Auth0 tenant object, so you can
# fill them into the `import` blocks in imports-pending.tf before running
# `terraform plan -generate-config-out=...`.
#
# Requires: curl, jq. Uses the same Management-API M2M app as Terraform.
#
# Usage (values come from your .auto.tfvars — pass them via env):
#
#   AUTH0_DOMAIN=arendse.uk.auth0.com \
#   AUTH0_CLIENT_ID=<m2m-client-id> \
#   AUTH0_CLIENT_SECRET=<m2m-client-secret> \
#   ./list-auth0-ids.sh
#
# The M2M app needs read scopes on the Management API:
#   read:clients, read:connections, read:resource_servers, read:client_grants
#
set -euo pipefail

: "${AUTH0_DOMAIN:?set AUTH0_DOMAIN, e.g. arendse.uk.auth0.com}"
: "${AUTH0_CLIENT_ID:?set AUTH0_CLIENT_ID (the Terraform M2M app client id)}"
: "${AUTH0_CLIENT_SECRET:?set AUTH0_CLIENT_SECRET (the Terraform M2M app client secret)}"

for bin in curl jq; do
    command -v "$bin" >/dev/null 2>&1 || {
        echo "error: '$bin' is required" >&2
        exit 1
    }
done

token="$(
    curl -fsS --request POST \
        --url "https://${AUTH0_DOMAIN}/oauth/token" \
        --header 'content-type: application/json' \
        --data "{\"client_id\":\"${AUTH0_CLIENT_ID}\",\"client_secret\":\"${AUTH0_CLIENT_SECRET}\",\"audience\":\"https://${AUTH0_DOMAIN}/api/v2/\",\"grant_type\":\"client_credentials\"}" |
        jq -r .access_token
)"

if [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "error: failed to obtain a Management API token — check the M2M credentials" >&2
    exit 1
fi

api() { curl -fsS --header "authorization: Bearer ${token}" "https://${AUTH0_DOMAIN}/api/v2/$1"; }

printf '\n== Clients (auth0_client) ==\n'
printf 'CLIENT_ID\tNAME\n'
api "clients?fields=client_id,name&include_fields=true&per_page=100" |
    jq -r '.[] | "\(.client_id)\t\(.name)"'

printf '\n== Connections (auth0_connection / auth0_connection_clients) ==\n'
printf 'CONNECTION_ID\tSTRATEGY\tNAME\tENABLED_CLIENTS\n'
api "connections?fields=id,name,strategy,enabled_clients&include_fields=true&per_page=100" |
    jq -r '.[] | "\(.id)\t\(.strategy)\t\(.name)\t\((.enabled_clients // []) | length) client(s)"'

printf '\n== Resource Servers / APIs (auth0_resource_server) ==\n'
printf 'ID\tIS_SYSTEM\tIDENTIFIER\tNAME\n'
api "resource-servers?fields=id,name,identifier,is_system&include_fields=true&per_page=100" |
    jq -r '.[] | "\(.id)\t\(.is_system // false)\t\(.identifier)\t\(.name)"'

printf '\n== Client Grants (auth0_client_grant) ==\n'
printf 'GRANT_ID\tCLIENT_ID\tAUDIENCE\n'
api "client-grants?per_page=100" |
    jq -r '.[] | "\(.id)\t\(.client_id)\t\(.audience)"'

printf '\nTip: system resource servers (IS_SYSTEM=true) generally should NOT be imported.\n'
