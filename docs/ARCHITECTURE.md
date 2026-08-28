# Architecture

## Data path

```text
Codex CLI / IDE threads
          |
          | local App Server protocol + persisted thread store
          v
     EngBridge on Mac
          |
          | encrypted Nearby Auto or authenticated direct Wi-Fi
          v
        Eng on iPhone
```

The bridge is the only component allowed to touch Codex. The phone receives product-level models, not raw rollout files, credentials, environment variables, or unrestricted JSON-RPC.

## Thread discovery and control

The bridge asks Codex App Server for CLI and IDE threads, resolves each working directory to its Git repository root, and groups the result into projects. Project identity is based on canonical repository root; thread identity remains the Codex thread UUID.

Each thread exposes a truthful control level:

- `available`: persisted history is visible and the bridge can attempt to resume the existing thread.
- `live`: `thread/resume` succeeded on the bridge connection, so it receives item and turn notifications and may steer or interrupt the active turn, start a turn inside that same thread, and answer supported requests.

Every refresh checks `thread/loaded/list` and resumes loaded threads on the bridge connection. This is what makes an active CLI or IDE thread stream to Eng even when another App Server client created it. A phone selection is also retained as a desired subscription and resumed again after an App Server reconnect. Existing independent sessions therefore become live without duplicating the thread.

The phone command policy is an allowlist. It permits refresh, subscribe, message or steer, interrupt, supported approval and user-input responses, analytics, and link probes. There is no phone message for `thread/start`, fork, archive, delete, shell execution, or arbitrary App Server JSON-RPC. When the selected existing thread is idle, phone text uses `turn/start` with that thread ID; when it is active, it uses `turn/steer` with the expected turn ID.

## Transport and pairing

The transport boundary is shared by the bridge coordinator and phone store, so Codex mapping, pairing, bounded paging, analytics, and control behavior do not depend on one network implementation.

The default `Nearby Auto` transport uses `MCSession` with required encryption. On iOS, Apple may carry that session over infrastructure Wi-Fi, peer-to-peer Wi-Fi, or Bluetooth. The framework does not expose which bearer it selected, so Eng labels the path `Nearby Auto` rather than making an unsupported Bluetooth or Wi-Fi claim. Each bridge process presents a short-lived pairing code on its first phone connection; reconnects to that running process reuse the validated device identity.

Protocol v4 carries transport identity and a short-lived direct-transport bootstrap. After nearby pairing, the Mac sends a random 256-bit credential inside the encrypted `MCSession`. Network Framework then discovers the Mac through Bonjour, enables peer-to-peer Wi-Fi, and encrypts and authenticates every bounded TCP frame with AES-GCM. Direct Wi-Fi becomes preferred when ready and the nearby session remains the fallback.

The SSH path is specified in [SSH Pipe](SSH-PIPE.md). It must verify the server host key and use public-key authentication; accepting any host key, exposing App Server, or storing a password in app preferences is outside the product boundary.

Pairing never transmits Codex login material. Protocol frames are bounded and typed; unknown versions and malformed payloads are rejected. Codex App Server remains bound to loopback for every transport.

## Analytics

Both devices sample only public, user-space signals:

- CPU utilization and logical core count
- used/total memory and the app's resident memory
- free/total disk
- battery state, charge, and low-power mode where available
- uptime
- active network interface and byte throughput
- measured bridge round-trip latency and payload goodput using a real bounded 64 KB request/response probe
- `ProcessInfo.thermalState`

iOS does not expose an exact device temperature to a normal app. Eng therefore reports Apple's thermal pressure categories (`nominal`, `fair`, `serious`, `critical`) and never fabricates degrees. Mac temperature follows the same public-API boundary; privileged tools are intentionally excluded.

## Failure behavior

- Connection loss keeps the last snapshot visible with a stale timestamp and reconnects nearby.
- A supervisor health-checks the loopback App Server, replaces a failed child with bounded exponential backoff, reinitializes the WebSocket exactly once per connection, and restores desired thread subscriptions.
- UI controls remain unavailable until the bridge has proven a live `thread/resume` subscription; a persisted status guess is not treated as connectivity.
- A message is not shown as delivered until the bridge acknowledges its Codex operation.
- Approval and user-input cards retain their request IDs and become terminal after one response.
- Unknown Codex events degrade to a compact activity entry rather than breaking the stream.
- Analytics values carry timestamps and optionals; unavailable signals render as unavailable, not zero.
