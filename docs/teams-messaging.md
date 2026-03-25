# Teams Messaging from AKS Pods

> How Squad pods send Microsoft Teams messages without app registrations, client secrets, or admin consent.

## Overview

Squad pods send status messages, alerts, and notifications to a Teams channel. Messages appear as the bot user **"DK8S Bot"**. The flow uses ROPC (Resource Owner Password Credential) to obtain a delegated Microsoft Graph token, which can send messages as a user — something app-only tokens cannot do.

## ROPC Flow

```
Pod (with Workload Identity)
  → mounts CSI volume → gets bot password from Key Vault
  → POST to Azure AD token endpoint (ROPC grant)
  → receives delegated access token
  → POST to Graph API /teams/{id}/channels/{id}/messages
  → message appears in Teams as "DK8S Bot"
```

### Step 1: Retrieve Bot Password

The bot password is stored in Azure Key Vault (`kv-squad-agents`) and synced to the pod via the CSI driver as a Kubernetes Secret (`squad-kv-secrets`). Inside the pod, it's available as an environment variable or mounted file.

### Step 2: Request Delegated Token via ROPC

```bash
curl -s -X POST \
  "https://login.microsoftonline.com/<your-tenant-id>/oauth2/v2.0/token" \
  -d "grant_type=password" \
  -d "client_id=d3590ed6-52b3-4102-aeff-aad2292ab01c" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "username=<your-bot-upn>" \
  -d "password=$(cat /mnt/secrets-store/dk8s-autobot-password)"
```

| Parameter | Value | Notes |
|-----------|-------|-------|
| `grant_type` | `password` | ROPC grant type |
| `client_id` | `d3590ed6-52b3-4102-aeff-aad2292ab01c` | Microsoft Office first-party app ID (well-known, public) |
| `scope` | `https://graph.microsoft.com/.default` | Request Graph API permissions |
| `username` | `<your-bot-upn>` | Bot account UPN (e.g., `dk8s-autobot@yourtenant.onmicrosoft.com`) |
| `password` | From Key Vault | Retrieved via CSI mount at `/mnt/secrets-store/dk8s-autobot-password` |

**Why this app ID?** Using the Microsoft Office well-known first-party app ID (`d3590ed6-52b3-4102-aeff-aad2292ab01c`) avoids creating a custom app registration and needing admin consent for delegated permissions. The Office app already has the necessary Graph permissions pre-consented.

### Step 3: Send Teams Message

```bash
# Extract the access token from the ROPC response
TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/<your-tenant-id>/oauth2/v2.0/token" \
  -d "grant_type=password" \
  -d "client_id=d3590ed6-52b3-4102-aeff-aad2292ab01c" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "username=<your-bot-upn>" \
  -d "password=$(cat /mnt/secrets-store/dk8s-autobot-password)" \
  | jq -r '.access_token')

# Send message to Teams channel
curl -s -X POST \
  "https://graph.microsoft.com/v1.0/teams/<your-team-id>/channels/<your-channel-id>/messages" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "body": {
      "contentType": "html",
      "content": "<b>Squad Alert:</b> Ralph completed monitoring cycle. 3 issues found."
    }
  }'
```

## Required Permissions

The bot account's delegated token (via ROPC + Microsoft Office app ID) uses these Graph API permissions:

| Permission | Type | Purpose |
|------------|------|---------|
| `ChannelMessage.Send` | Delegated | Send messages to Teams channels |
| `Chat.ReadWrite` | Delegated | Read/write chat messages (for 1:1 bot chats) |
| `Team.ReadBasic.All` | Delegated | Read team metadata to resolve team/channel IDs |
| `User.Read` | Delegated | Read bot's own profile |

These permissions are pre-consented for the Microsoft Office app ID. No custom app registration or admin consent flow is needed.

## Required Key Vault Secrets

| Secret | Stored In | Used For |
|--------|-----------|----------|
| `dk8s-autobot-password` | `kv-squad-agents` | Bot account password for ROPC token exchange |
| `gh-token` | `kv-squad-agents` | GitHub PAT for Copilot CLI (not used for Teams) |

Both secrets are synced to Kubernetes Secret `squad-kv-secrets` via the CSI driver.

## Full Curl Example (From Inside a Pod)

```bash
#!/bin/bash
# send-teams-message.sh — Send a message to Teams from inside a Squad pod
# All credentials come from Key Vault via CSI driver mount

TENANT_ID="<your-tenant-id>"
BOT_UPN="<your-bot-upn>"
TEAM_ID="<your-team-id>"
CHANNEL_ID="<your-channel-id>"

# Microsoft Office well-known app ID (public, not a secret)
CLIENT_ID="d3590ed6-52b3-4102-aeff-aad2292ab01c"

# Get bot password from CSI mount
BOT_PASSWORD=$(cat /mnt/secrets-store/dk8s-autobot-password)

# Step 1: Get delegated token via ROPC
TOKEN_RESPONSE=$(curl -s -X POST \
  "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
  -d "grant_type=password" \
  -d "client_id=${CLIENT_ID}" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "username=${BOT_UPN}" \
  -d "password=${BOT_PASSWORD}")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ "$ACCESS_TOKEN" = "null" ] || [ -z "$ACCESS_TOKEN" ]; then
  echo "ERROR: Failed to get token"
  echo "$TOKEN_RESPONSE" | jq '.error_description'
  exit 1
fi

# Step 2: Send message
MESSAGE="$1"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "https://graph.microsoft.com/v1.0/teams/${TEAM_ID}/channels/${CHANNEL_ID}/messages" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"body\": {
      \"contentType\": \"html\",
      \"content\": \"${MESSAGE}\"
    }
  }")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "201" ]; then
  echo "Message sent successfully"
else
  echo "ERROR: HTTP ${HTTP_CODE}"
  echo "$BODY" | jq '.error'
fi
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `AADSTS50126: Invalid username or password` | Bot password wrong or expired | Update secret in Key Vault, CSI will re-sync |
| `AADSTS50076: MFA required` | Bot account has MFA enforced | Exclude bot from Conditional Access MFA policy |
| `AADSTS700016: Application not found` | Wrong client ID | Use `d3590ed6-52b3-4102-aeff-aad2292ab01c` (Microsoft Office) |
| `403 Forbidden` on Graph call | Bot not a member of the Team | Add bot account to the Team |
| CSI mount empty | Workload Identity not configured | Check SA annotation, FIC subject, pod label |

## Security Considerations

- **Bot account should be a service account** with minimal permissions — not a real user
- **Exclude from MFA** via Conditional Access policy (ROPC cannot handle MFA)
- **Password rotation**: Update Key Vault secret; CSI re-syncs automatically on next pod mount
- **Token lifetime**: ROPC tokens are short-lived (~1 hour). Pods should request new tokens per operation, not cache them
- **Audit**: All Graph API calls are logged in Azure AD sign-in logs under the bot account
