# Security Policy

Do not open a public issue containing a channel credential, administrator token,
device key, endpoint secret, Codex content, or diagnostic capture. Revoke affected
channels immediately and rotate the Worker `ADMIN_TOKEN` if it may be exposed.

For a private vulnerability report, use GitHub's private vulnerability reporting
for this repository. Include the affected commit, reproduction steps, impact, and a
proposed mitigation if known. Do not test against deployments you do not own.

The security boundary intentionally excludes Cloudflare-visible connection metadata.
It includes role and channel authorization, bounded opaque routing, device/Mac key
pinning, and end-to-end confidentiality and integrity of `BridgeEnvelope` content.
Codex App Server, login material, cookies, environment variables, and rollout files
must remain on the Mac.
