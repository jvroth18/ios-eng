# SSH pipe design

## Decision

SSH is a remote transport option, not the default local path. It carries the same bounded, typed bridge frames through a TCP forward. Codex App Server remains bound to loopback on the Mac and is never the forwarded service.

The first implementation should use SwiftNIO SSH through a maintained high-level client layer. SwiftNIO SSH supplies the protocol, modern cryptography, authentication hooks, and direct/reverse TCP forwarding, but describes itself as building blocks rather than a ready-made production client. Adding it directly to the phone app before the trust UI and Keychain lifecycle exist would create an unsafe half-implementation.

## Required security contract

- Generate an Ed25519 client key in the iPhone Keychain. The private key is non-exportable to app preferences, logs, analytics, or protocol messages.
- Show the Mac host's SHA-256 Ed25519 fingerprint during enrollment and require an explicit match. Never use an accept-any-host-key callback.
- Authorize only the generated public key on the Mac. Password and keyboard-interactive authentication are unsupported.
- Forward only the Eng bridge endpoint. Never forward the Codex App Server port, credentials, cookies, rollout files, or a shell.
- Retain AES-GCM frame protection inside SSH. This preserves the paired-device authorization boundary and makes a tunnel-routing mistake fail closed.
- Store host, port, username, pinned fingerprint, and public-key reference only. Secrets live in Keychain.
- Revoke by deleting the Mac `authorized_keys` entry and the phone Keychain key, then require nearby pairing again.

## Topology

```text
Eng iPhone -- SSH direct-tcpip --> Mac sshd -- loopback --> Eng secure-frame listener
                                                        X Codex App Server
```

For an internet path, the user supplies a reachable SSH host through their VPN or private network. Eng does not enable Remote Login, change firewall rules, create router port forwards, or modify `authorized_keys` automatically.

## Delivery gates

1. Host-key pinning tests reject first-use substitution and changed keys.
2. Keychain tests prove no private key or password enters preferences/logs.
3. The forwarded destination is allowlisted to the Eng listener only.
4. Device validation covers connect, reconnect, cancellation, credential expiry, and revocation.
5. Analytics labels the path `SSH Tunnel`; it never guesses the underlying radio.
