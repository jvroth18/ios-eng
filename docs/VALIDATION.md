# Validation record

Validated on August 27, 2026 with Xcode 26.5, Swift 6, Codex CLI, an iPhone 17 Pro simulator, and Jordan's paired iPhone 17 Pro.

## Contracts and unit coverage

- `swift format lint --strict` passes across app, bridge, shared sources, tests, and scripts.
- `swift test` passes 18 tests in 6 suites.
- Coverage includes protocol round trips, encrypted-pairing gates, Git-root grouping, App Server event and request mapping, public Mac telemetry, link classification, a real 64 KB probe payload, and lossless workspace paging.
- The paging stress fixture carries 245 threads, keeps every encoded frame below the Multipeer Connectivity resource ceiling, and reassembles without loss.

## Native app build and installation

- Xcode simulator tests pass 2 presentation tests in 1 suite on iPhone 17 Pro.
- A Release `iphoneos` build succeeds with Apple Development signing and automatic provisioning for bundle `dev.jvroth.eng`.
- The exact Release artifact installs on the paired physical iPhone as `Eng` version `0.1.0` (build `1`).
- `devicectl` launches the installed bundle and reads back its live `/Eng.app/Eng` process.

## Live Codex mirror

- The bridge starts the installed Codex App Server on loopback and discovers the complete paginated history, not a fixed first-page sample.
- The latest full scan grouped 893 threads into 165 repository projects and transferred them in 9 bounded workspace frames.
- A CLI session created through `Scripts/codex-eng` appeared under the `ios-eng` repository in the phone UI.
- CLI-to-phone streaming was verified with `CLI_MIRROR_READY`.
- Phone-to-CLI turn creation was verified with `PHONE_TO_CLI_OK` and read back in the CLI.
- Active-turn steering was verified from the phone with `STEER_FROM_PHONE` in the same CLI turn.
- Active-turn interrupt was invoked from the phone while a 120-second shell command was running. The CLI reported `Conversation interrupted`, the command process ended, and the forbidden completion response was not produced.
- Choice and free-form App Server input requests are both represented by the shared protocol and phone UI. Approval responses preserve the originating JSON-RPC request identifier.

## Analytics and product QA

- The Analytics tab renders separate Phone and MacBook cards, recent charts, a connection-quality card, and sample timestamps.
- Both samplers report CPU, memory, app resident memory, disk, battery/power, uptime, network interface, and byte rates from public APIs.
- The nearby link measurement uses a 64 KB request/response payload to calculate round-trip latency and goodput rather than presenting an inferred Wi-Fi label as speed.
- The installed Release app paired from the physical iPhone over the encrypted nearby session while the full 893-thread workspace was available. The bridge read back a real phone sample of 16.5% CPU, nominal thermal state, and Wi-Fi, then measured the 64 KB probe at 478.2 ms round trip and 0.27 MB/s payload goodput.
- Phone temperature in degrees is intentionally unavailable: Apple's public iOS API exposes thermal-pressure categories. Eng displays nominal/fair/serious/critical and does not use private APIs or invent a degree value.
- Projects, thread, Analytics, connection, empty, and error states were rendered and visually inspected at iPhone dimensions. Dynamic status text and controls are exposed to accessibility where the system surface supports it.

## Operational boundary

The Codex WebSocket remains bound to `127.0.0.1`. The phone never receives Codex credentials and connects through an encrypted Multipeer Connectivity session gated by a short-lived six-digit code. Diagnostic history is held in memory and capped at 90 samples per device.
