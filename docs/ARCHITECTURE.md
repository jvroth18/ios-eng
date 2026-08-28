# Architecture

## Data path

```text
Codex CLI / IDE threads
          |
          | local App Server protocol + persisted thread store
          v
     EngBridge on Mac
          |
          | encrypted Nearby Auto or authenticated direct local
          | (USB-C/wired preferred, then Wi-Fi)
          v
        Eng on iPhone
```

The bridge is the only component allowed to touch Codex. The phone receives product-level models, not raw rollout files, credentials, environment variables, or unrestricted JSON-RPC.

## Thread discovery and control

The bridge asks Codex App Server for CLI and IDE threads, resolves each working directory to its Git repository root, and groups the result into projects. Project identity is based on canonical repository root; thread identity remains the Codex thread UUID.

Each thread exposes a truthful control level:

- `available`: persisted history is visible and the bridge can attempt to resume the existing thread.
- `Mac Live`: another Mac Codex process owns the writer lock. Eng tails a bounded, allowlisted view of that thread's local event journal and queues phone messages through the installed Codex CLI without trying to acquire a second writer.
- `live`: `thread/resume` succeeded on the bridge connection, so it receives item and turn notifications and may steer or interrupt the active turn, start a turn inside that same thread, and answer supported requests.

Every refresh checks `thread/loaded/list` and resumes loaded threads on the bridge connection. This is what makes an active CLI or IDE thread stream to Eng even when another App Server client created it. A phone selection is also retained as a desired subscription and resumed again after an App Server reconnect. Existing independent sessions therefore become live without duplicating the thread.

The phone command policy is an allowlist. It permits refresh, subscribe, message or steer, model selection, interrupt, supported approval and user-input responses, analytics, and link probes. There is no phone message for `thread/start`, fork, archive, delete, shell execution, or arbitrary App Server JSON-RPC. When the selected existing thread is idle, phone text uses `turn/start` with that thread ID; when it is active, it uses `turn/steer` with the expected turn ID. The bridge obtains the model menu from App Server's paginated `model/list` result and validates every selection before applying `thread/settings/update` to the existing bridge-owned thread. It never invents a static account catalog or changes the owner-controlled model of a `Mac Live` thread.

For a `Mac Live` thread, message delivery uses `codex queue --thread … --message
…`, which preserves the existing owner. Stop mirrors Ctrl-C only when the writer
lock resolves to exactly one same-user interactive `codex` process. The bridge
refuses to signal GUI, noninteractive, ambiguous, or unverified processes.

The external journal reader resolves only the exact rollout file whose UUID
matches the selected thread. It initially reads at most the final 4 MB, then only
newly appended bytes, retaining at most 120 projected items. It accepts observable
`event_msg` records for user/assistant messages, reasoning summaries, commands,
file changes, tools, compaction, web search, and image views. Session metadata,
raw response records, raw or encrypted reasoning, unknown records, and every
other thread are rejected. The selected detail refresh runs once per second;
workspace discovery remains on its slower independent cadence.

Bridge-owned live notifications retain the App Server `itemId` from start through
each delta and completion. The reducer therefore updates the exact plan, command,
tool, file-change, commentary, or final-answer row rather than merging neighboring
messages. Only `reasoning/summaryTextDelta` is product-visible;
`reasoning/textDelta` is deliberately ignored.

## Transport and pairing

The transport boundary is shared by the bridge coordinator and phone store, so Codex mapping, pairing, bounded paging, analytics, and control behavior do not depend on one network implementation.

The fallback `Nearby Auto` transport uses `MCSession` with required encryption. On iOS, Apple may carry that session over infrastructure Wi-Fi, peer-to-peer Wi-Fi, or Bluetooth. The framework does not expose which bearer it selected, so Eng labels the path `Nearby Auto` rather than making an unsupported radio claim.

Protocol v5 carries transport identity, direct-session key material, the account-aware model catalog, and existing-thread model updates. Network Framework discovers the Mac through Bonjour on every eligible local interface. The phone prefers a discovered wired-Ethernet interface—which is how Apple exposes USB Personal Hotspot—then Wi-Fi or another local path. A Curve25519 agreement protects the initial pair exchange; the phone and Mac persistently pin each other's public identities, and accepted sessions rotate to a short-lived random 256-bit AES-GCM credential. Nearby remains the fallback.

A USB-C cable alone is only a trusted device/developer connection and is not a public application data channel. USB-C transport therefore requires Personal Hotspot to expose `iPhone USB` as a network interface. Eng does not use `usbmuxd`, developer port forwarding, private frameworks, or MFi accessory protocols.

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

## Conversation presentation and unread state

The project explorer presents a thread with `fullScreenCover`, so the conversation
owns the phone display until Back or Close dismisses it. Repository metadata remains
in the explorer rather than taking space from the message timeline. Message bodies
are parsed locally into headings, paragraphs, lists, quotes, and fenced code blocks;
inline Markdown supplies emphasis and links. Formatting never changes or executes
the transported content.

Unread tracking compares each thread's latest update timestamp with its previously
observed timestamp. The first workspace is a baseline, unchanged refreshes do not
produce notifications, and activity in the visible conversation stays read. Newer
background activity persists the thread UUID in app preferences, produces an
in-app banner, and appears as project, tab, status-bar, and thread-row counts. Opening
the exact conversation clears its unread state. Removed threads are pruned.

Draft text is keyed by thread UUID in iPhone preferences and is never sent until
the user presses Send, Steer, or Queue. Navigating away or relaunching therefore
preserves unfinished text without mixing drafts between threads. Keyboard appearance
animates the complete conversation window upward while the timeline remains the
flexible region, keeping the composer and surrounding chat context together.

Hidden-thread state is also keyed by thread UUID in iPhone preferences. The project
explorer filters those rows locally and Config provides individual and bulk restore
controls. Hidden activity does not create a visible unread banner or count, but any
saved draft remains recoverable after unhide. No hide action crosses the bridge, so
the Mac thread is never archived, deleted, or otherwise mutated.

## Failure behavior

- Connection loss keeps the last snapshot visible with a stale timestamp and reconnects nearby.
- A supervisor health-checks the loopback App Server, replaces a failed child with bounded exponential backoff, reinitializes the WebSocket exactly once per connection, and restores desired thread subscriptions.
- UI controls use direct App Server methods only after a live `thread/resume` subscription. `Mac Live` controls instead use the separately validated queue and interactive-CLI Stop paths.
- A message is not shown as delivered until the bridge acknowledges its Codex operation.
- Approval and user-input cards retain their request IDs and become terminal after one response.
- Unknown Codex item types degrade to a compact activity entry rather than breaking the stream; unknown journal records are ignored at the stricter external-writer boundary.
- Analytics values carry timestamps and optionals; unavailable signals render as unavailable, not zero.
