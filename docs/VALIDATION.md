# Validation record

Validated on August 28, 2026 with Xcode 26.5, Swift 6, Codex CLI, an iPhone 17 Pro simulator, and Jordan's paired iPhone 17 Pro.

## Contracts and unit coverage

- `swift format lint --strict` passes across app, bridge, shared sources, tests, and scripts.
- `swift test` passes 43 tests in 14 suites.
- Coverage includes protocol round trips, encrypted-pairing gates, Git-root grouping, App Server event and request mapping, public Mac telemetry, link classification, a real 64 KB probe payload, lossless workspace paging, App Server supervision, subscription recovery, active-turn steering, idle existing-thread turns, and the phone command allowlist.
- The paging stress fixture carries 245 threads, keeps every encoded frame below the Multipeer Connectivity resource ceiling, and reassembles without loss.

## Native app build and installation

- Xcode simulator tests pass 22 tests with 0 failures on iPhone 17 Pro.
- A Release `iphoneos` build succeeds with Apple Development signing and automatic provisioning for bundle `dev.jvroth.eng`.
- The last installed Release artifact before the active-writer repair was `Eng` version `0.2.0` (build `2`).
- The configuration release `Eng` version `0.4.0` (build `4`) was built with Apple Development signing, installed on the paired physical iPhone, launched with `devicectl`, and read back as a live `/Eng.app/Eng` process.
- The oversized-thread repair release `Eng` version `0.4.1` (build `5`) was built with Apple Development signing, installed on the paired physical iPhone, launched with `devicectl`, and read back at its new `/Eng.app/Eng` installation path.
- `devicectl` launches the installed bundle and reads back its live `/Eng.app/Eng` process.

## August 28 Codex activity mirror

- A phone-sent message is inserted into the selected thread immediately as a pending `You` timeline item, before the bridge acknowledges the request.
- The pending item is reconciled against the corresponding App Server user event or refreshed thread detail so the confirmed message does not appear twice.
- Synchronous transport failures preserve the user's text in the timeline and mark it `Failed` instead of silently removing it.
- The thread surface shows `Thinking` as soon as a message is sent, then derives `Writing response`, `Updating plan`, `Running command`, `Editing files`, `Using tool`, or approval/input waiting states from the actual streamed App Server timeline.
- The activity mirror presents observable Codex operations only; it does not fabricate or expose private chain-of-thought.
- After installing and launching version `0.2.0` (build `2`) on the physical iPhone, the bridge recorded a fresh encrypted Nearby pairing, Wi-Fi phone diagnostics, and a measured 172.2 ms / 0.76 MB/s link sample. Both `/readyz` and `/healthz` returned HTTP 200, and the post-launch log window contained no App Server connection error.

## August 28 active-writer repair

- A live protocol probe proved `thread/turns/list` returns the observable transcript while `thread/resume` is rejected because another Codex process owns the writer lock.
- Selecting that thread now falls back to `Mac Live`, sends a bounded recent timeline frame, and polls for changes every three seconds instead of presenting the active-writer error.
- Loaded external writers are remembered after the first active-writer response, so periodic workspace refresh and subscription recovery do not repeatedly retry `thread/resume` or create an App Server reconnect loop.
- Phone messages for `Mac Live` threads use the installed `codex queue` command and never create or resume a duplicate thread.
- Stop mirrors Ctrl-C only when the writer lock identifies exactly one same-user interactive Codex CLI process. GUI, noninteractive, ambiguous, and unverified owners fail closed.
- Core tests cover active-writer fallback, bounded timeline projection, queued messages, external Stop routing, complete owned-process-tree shutdown, and writer-process validation. The simulator suite passes 22 tests with 0 failures.

## August 28 oversized-thread and stable-order repair

- The reproduced failure was an oversized full-history App Server WebSocket response, not an oversized phone-authored message. A persisted turn containing large command output exceeded Foundation's default inbound WebSocket ceiling before Eng could project it.
- Historical `thread/turns/list` requests now use the installed App Server's supported `summary` items view. The loopback Mac client has an explicit 16 MB guarded receive ceiling for legitimate live events, and every mapped live timeline event is projected before phone transport.
- Workspace refresh preserves the existing project order and each project's existing thread order while applying current status, summary, timestamps, and control state. New entries appear once and removed entries disappear; routine five-second refreshes no longer reshuffle the visible list.
- Regression tests assert the summary request and stable ordering across status/time changes, additions, and removals. Core tests pass 43 tests in 14 suites and the iPhone simulator passes 22 tests in 3 suites.
- A live initialized App Server probe requested the exact formerly failing thread `01a0443a-e741-70f2-8738-760a9a5d4332` with `itemsView: summary` and received all 12 requested turn summaries without disconnecting.
- Desktop companion 3.8 (build 11) was installed with an embedded bridge hash matching the tested release binary. Its fresh App Server on port 54496 returned HTTP 200 from `/readyz` and `/healthz`.
- Eng 0.4.1 reconnected from the physical iPhone over the encrypted direct-local route, received all 912 threads in 10 bounded frames, and reported nominal thermal state. The post-launch log window contained one App Server connection, no `Message too long`, and no bridge-operation failure or reconnect loop.

## August 28 phone configuration and focus

- The Config tab persists Automatic, USB-C-first, Wi-Fi-first, and Nearby-only data-route preferences. The same route picker remains available while searching so a saved choice cannot strand configuration behind pairing.
- Direct-link selection honors the preferred Network Framework interface, Nearby remains the recovery path for direct modes, and deliberate route changes suppress stale connection callbacks from restarting a disabled route.
- Folder pins and the pinned-only focus filter persist across launches; pinned projects sort ahead of other recent work.
- Thread rows show a two-line request/activity summary. Once a thread has streamed, its observable current operation such as Thinking, Running command, or Writing response replaces the request fallback.
- Thread timestamps are explicitly labeled as last updated. Active work separately says Live now; no elapsed-open duration is inferred.
- iOS does not expose a public app control for USB data with charging disabled. Eng changes its data route only and points users to the system Charge Limit setting where supported.
- Desktop companion 3.7 (build 10) was installed with the bridge hash matching the current release build. Its App Server returned HTTP 200 from both `/readyz` and `/healthz` on fresh port 51231.
- Eng 0.4.0 reconnected from the physical iPhone over the encrypted direct-local route, reported nominal thermal state and Wi-Fi diagnostics, and measured the 64 KB bridge probe at 70.5 ms round trip and 1.86 MB/s payload goodput.
- The post-launch log window refreshed 911 threads across 170 projects without another active-writer error. Quitting the preceding desktop build removed its bridge wrapper, Node child, native App Server, runtime record, and listener on port 49577 before the next launch.

## Live Codex mirror

- The bridge starts the installed Codex App Server on loopback and discovers the complete paginated history, not a fixed first-page sample.
- The latest repair-validation scan grouped 895 threads into 165 repository projects and transferred them in 9 bounded workspace frames.
- A CLI session created through `Scripts/codex-eng` appeared under the `ios-eng` repository in the phone UI.
- CLI-to-phone streaming was verified with `CLI_MIRROR_READY`.
- Phone-to-CLI turn creation was verified with `PHONE_TO_CLI_OK` and read back in the CLI.
- Active-turn steering was verified from the phone with `STEER_FROM_PHONE` in the same CLI turn.
- Active-turn interrupt was invoked from the phone while a 120-second shell command was running. The CLI reported `Conversation interrupted`, the command process ended, and the forbidden completion response was not produced.
- Choice and free-form App Server input requests are both represented by the shared protocol and phone UI. Approval responses preserve the originating JSON-RPC request identifier.

## August 27 live-stream repair

- A two-client probe created a Mac-side test thread, completed its first turn, resumed the existing thread from an independent App Server connection, and then started a second turn from the creator.
- The subscriber received 13 matching notifications, including `turn/started`, `item/started`, `item/completed`, `item/agentMessage/delta`, and `turn/completed`; the delta stream contained `LIVE_STREAM_OK`. The exact test thread was archived afterward.
- Terminating only the bridge-owned App Server child left the bridge running. The supervisor started a replacement child, and both loopback `/readyz` and `/healthz` returned HTTP 200.
- Unit tests prove that phone selection invokes `thread/resume`, reconnect restores desired subscriptions, an active existing turn uses `turn/steer`, and an idle existing thread uses `turn/start` without ever invoking `thread/start`.
- Policy tests prove that phone messages cannot create, fork, archive, or delete a thread and cannot invoke arbitrary App Server methods.

## Analytics and product QA

- The Analytics tab renders separate Phone and MacBook cards, recent charts, a connection-quality card, and sample timestamps.
- Both samplers report CPU, memory, app resident memory, disk, battery/power, uptime, network interface, and byte rates from public APIs.
- The nearby link measurement uses a 64 KB request/response payload to calculate round-trip latency and goodput rather than presenting an inferred Wi-Fi label as speed.
- The installed Release app paired from the physical iPhone over the encrypted nearby session while the full 893-thread workspace was available. The bridge read back a real phone sample of 16.5% CPU, nominal thermal state, and Wi-Fi, then measured the 64 KB probe at 478.2 ms round trip and 0.27 MB/s payload goodput.
- Phone temperature in degrees is intentionally unavailable: Apple's public iOS API exposes thermal-pressure categories. Eng displays nominal/fair/serious/critical and does not use private APIs or invent a degree value.
- Projects, thread, Analytics, connection, empty, and error states were rendered and visually inspected at iPhone dimensions. Dynamic status text and controls are exposed to accessibility where the system surface supports it.

## Operational boundary

The Codex WebSocket remains bound to `127.0.0.1`. The phone never receives Codex credentials and connects through an encrypted Multipeer Connectivity session gated by a short-lived six-digit code. Diagnostic history is held in memory and capped at 90 samples per device.
