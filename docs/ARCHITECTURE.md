# Architecture

## Data path

```text
Codex CLI / IDE threads
          |
          | local App Server protocol + persisted thread store
          v
     EngBridge on Mac
          |
          | encrypted MultipeerConnectivity session + pairing code
          v
        Eng on iPhone
```

The bridge is the only component allowed to touch Codex. The phone receives product-level models, not raw rollout files, credentials, environment variables, or unrestricted JSON-RPC.

## Thread discovery and control

The bridge asks Codex App Server for CLI and IDE threads, resolves each working directory to its Git repository root, and groups the result into projects. Project identity is based on canonical repository root; thread identity remains the Codex thread UUID.

Each thread exposes one of three truthful control levels:

- `observe`: history and persisted changes can be mirrored.
- `message`: the bridge can enqueue a user message for the owning CLI session.
- `live`: the bridge is subscribed to the owning App Server and can stream deltas, steer an active turn, start a new turn, interrupt, and answer supported requests.

For a full live mirror, CLI sessions use the bridge's shared local App Server workflow. Existing independent CLI sessions remain visible and can be upgraded without duplicating the thread.

## Transport and pairing

The nearby transport uses `MCSession` with required encryption. A first connection must present the short pairing code displayed by the Mac bridge. Pairing never transmits Codex login material. Protocol frames are bounded and typed; unknown versions and malformed payloads are rejected.

## Analytics

Both devices sample only public, user-space signals:

- CPU utilization and logical core count
- used/total memory and the app's resident memory
- free/total disk
- battery state, charge, and low-power mode where available
- uptime
- active network interface and byte throughput
- measured bridge round-trip latency and payload goodput
- `ProcessInfo.thermalState`

iOS does not expose an exact device temperature to a normal app. Eng therefore reports Apple's thermal pressure categories (`nominal`, `fair`, `serious`, `critical`) and never fabricates degrees. Mac temperature follows the same public-API boundary; privileged tools are intentionally excluded.

## Failure behavior

- Connection loss keeps the last snapshot visible with a stale timestamp and reconnects nearby.
- A message is not shown as delivered until the bridge acknowledges its Codex operation.
- Approval and user-input cards retain their request IDs and become terminal after one response.
- Unknown Codex events degrade to a compact activity entry rather than breaking the stream.
- Analytics values carry timestamps and optionals; unavailable signals render as unavailable, not zero.

