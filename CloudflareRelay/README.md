# Eng Relay for Cloudflare

This package is the open-source hosted transport for Eng. A Cloudflare Worker
authenticates provisioning and connection requests. One SQLite-backed Durable Object
coordinates the phone and Mac WebSockets for each channel and hibernates while idle.
It routes opaque binary frames and does not receive Eng's Curve25519/AES-GCM keys.

## Security model

- A high-entropy Worker secret authorizes channel creation and revocation.
- Provisioning returns different 256-bit credentials for phone and bridge roles.
- Only SHA-256 credential digests are persisted in the Durable Object.
- Channel identifiers are random UUIDs; every connection still requires its
  role-specific credential.
- Cross-channel and cross-role authentication are rejected.
- Frames are binary-only, non-empty, and limited to 2 MiB.
- A newer connection replaces the older connection for the same channel role.
- No API lists channels, reads frames, or returns stored credential digests.
- Revocation closes active sockets and deletes the channel configuration.
- Responses disable caching and MIME sniffing.

Cloudflare can observe account, network, channel, timing, and frame-size metadata.
It cannot decrypt the Eng envelopes carried inside frames. Do not add application
payload logging, plaintext queues, Codex credentials, or App Server access here.

## Deploy

Requirements: Node.js 22+, a Cloudflare account, and Wrangler authentication.

```sh
cd CloudflareRelay
npm ci
npm run check
npm test
npx wrangler login
openssl rand -base64 48 | npx wrangler secret put ADMIN_TOKEN
npm run deploy
```

Use a dedicated Cloudflare account or Worker subdomain for production. Never commit
`ADMIN_TOKEN`, `.dev.vars`, provisioned channel files, or Wrangler credentials.

For repeatable deployments, create a protected GitHub environment named
`cloudflare-production`, add least-privilege `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID` secrets, and run the manual **Deploy Cloudflare Relay**
workflow. The administrator token remains a Wrangler secret and is not a GitHub
Actions input.

## Provision one user/Mac channel

Keep the administrator token in a password manager or deployment secret store:

```sh
ENG_RELAY_ADMIN_TOKEN='your-admin-token' \
  npm run provision -- https://eng-relay.example.workers.dev /secure/eng-jordan
```

The command writes mode-0600 `phone-channel.json` and `bridge-channel.json` files and
does not print either token. Transfer the phone values through a trusted local path,
then enter the Worker URL, channel UUID, and phone token in Eng Config. Point
`ENG_RELAY_CREDENTIALS` at the bridge file when starting `eng-bridge`.

## Revoke a channel

```sh
curl --fail --request DELETE \
  --header "Authorization: Bearer $ENG_RELAY_ADMIN_TOKEN" \
  "https://eng-relay.example.workers.dev/v1/channels/CHANNEL_UUID"
```

After revocation, remove the remote configuration from the phone. Provision a new
channel rather than reusing either old credential.

## Validate a contribution

```sh
npm ci
npm audit
npm run check
npm test
npx wrangler deploy --dry-run
```

Tests execute inside Cloudflare's Workers runtime and cover admin authentication,
one-time role-scoped provisioning, cross-role/cross-channel rejection, binary frame
routing, and isolated revocation.
