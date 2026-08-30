# Eng

Eng is a private, native iPhone companion for Codex work running on your Mac. It groups threads by the repository they are working in, mirrors conversation and tool activity, lets you send or steer work from the phone, surfaces approvals when the Mac session supports them, and shows live phone/Mac diagnostics.

The repository contains four pieces:

- `EngCore`: the versioned, tested wire protocol and shared models.
- `EngBridge`: a Mac companion that connects to Codex App Server and advertises encrypted nearby and direct-local sessions.
- `EngRelay`: a self-hosted, loopback-by-default opaque frame relay for remote access.
- `Eng`: a deliberately small SwiftUI iPhone app with Projects, Thread, Analytics, and Config surfaces, drawn in a classic Windows 9x "analog" style (beveled windows, tab pages, LEDs, and a green-phosphor system monitor) from the `EngApp/Design/Win95.swift` kit.

## Product boundary

Codex App Server is the supported deep-client interface for conversation history, streamed events, turns, steering, and approvals. Eng keeps that interface on the Mac. The phone talks only to the paired bridge. The authenticated AES-GCM direct channel prefers an Apple-exposed USB-C/wired network path, then local or peer-to-peer Wi-Fi, and falls back to encrypted Apple Nearby.

Ordinary CLI sessions can always be discovered from Codex's local thread store. Live steering and approval handling require the thread to be controllable by the bridge/shared App Server. Eng displays `Observe`, `Message`, or `Live` on every thread so the user can see the real boundary.

If another Codex CLI owns a thread, Eng opens it as `Mac Live` instead of failing
on the single-writer lock. The bridge tails an allowlisted, read-only view of the
owner's local event journal once per second, merges it with App Server summaries,
uses Codex's supported `queue` command for phone messages, and can mirror Ctrl-C
for Stop only after verifying the lock belongs to a same-user interactive Codex
CLI. Noninteractive and GUI-owned sessions remain visible and queueable, but
must be stopped from their Mac window.

Historical thread reads use App Server's display-summary view, while live events
retain current command/tool activity inside a strict phone projection. This
prevents large persisted command output from disconnecting App Server. Once the
phone has displayed a workspace, refreshes update entries in place instead of
continually re-sorting projects and threads around the screen.

Live rows retain App Server item identity, so commentary and final-answer text,
plans, commands, file edits, tools, web activity, and compaction update the same
stable row throughout their lifecycle. Eng displays observable reasoning summaries
when Codex emits them, but never forwards raw or encrypted private reasoning.

Opening a thread presents a dedicated full-screen conversation without the project
tabs or repository metadata panel. Assistant and user messages render headings,
emphasis, links, lists, quotes, and fenced code blocks. Background activity marks
the exact thread unread, shows an in-app banner plus project/thread badges, persists
across launches, and clears when that conversation is opened.

The conversation toolbar keeps Stop visible and enables it only when the selected
thread has an interruptible turn. Drafts are saved independently per thread, survive
navigation and relaunch, and appear as thread-row and toolbar indicators. Opening
the keyboard animates the entire conversation window upward. For bridge-owned live
threads, the Model menu is populated from the signed-in Codex account and changes
the model for subsequent turns in that existing thread; a `Mac Live` thread remains
truthfully controlled by its owning Mac process.

Each project thread row also has an eye-slash control that hides the thread only
from this iPhone. Hidden threads remain intact on the Mac, keep their drafts, stay
out of visible unread/draft counts, and can be restored individually or together
from Config. Hiding never sends an archive or delete operation to Codex.

## Status

This repository was delivered in validated, incremental commits:

1. Shared mirror and telemetry contract.
2. Mac bridge, Codex integration, diagnostics, and CLI workflow.
3. Native iPhone app and Analytics view.
4. End-to-end simulator/device validation and installation handoff.

See [Architecture](docs/ARCHITECTURE.md), [Acceptance](docs/ACCEPTANCE.md), and
[Validation](docs/VALIDATION.md).

## Development

Requirements: Xcode 26+, Swift 6, XcodeGen 2.46+, and a current authenticated Codex CLI.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run eng-bridge
```

Keep the bridge running, then start a fully mirrored Codex CLI thread from another IDE terminal:

```sh
./Scripts/codex-eng -C /path/to/repository
```

`swift run eng-bridge --smoke` validates the installed Codex protocol, thread discovery, Git grouping, and Mac telemetry without advertising to a phone.

Generate and validate the native app with:

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Eng.xcodeproj -scheme Eng \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
open Eng.xcodeproj
```

The generated Xcode project is intentionally ignored; `project.yml` is its source of truth. The debug-only `-eng-demo`, `-eng-analytics`, `-eng-config`, and `-eng-thread` launch arguments render deterministic project, analytics, configuration, and thread states for visual QA without altering release behavior. `-eng-pair-code CODE` automates pairing only in debug builds for repeatable simulator integration tests.

The first phone opened during the bridge pairing window is remembered automatically. The short Mac-terminal code remains available for a replacement phone; normal reconnects do not require it. For USB-C, enable iPhone Personal Hotspot and connect the trusted cable so Apple exposes an `iPhone USB` network interface to Network Framework. Analytics retains only the most recent 90 in-memory samples per device. Exact iPhone temperature is not available through Apple’s public API, so Eng reports `ProcessInfo.thermalState` categories instead of degrees.

The Config tab persists a connection preference (`Automatic`, `USB-C first`,
`Wi-Fi first`, `Nearby only`, or `Remote only`) and pinned focus folders. USB-C and Wi-Fi
preferences keep Nearby available as a recovery path. iOS does not expose an
app API that keeps USB-C data active while disabling charging, so Eng controls
only its data route and never presents a charging switch it cannot enforce.

## Self-hosted remote access

Remote access does not require another iPhone app. Create a private channel on the
relay host, keep the generated file secret, and run the relay behind an HTTPS reverse
proxy:

```sh
swift run eng-relay issue --output /secure/path/eng-channel.json
swift run eng-relay serve --credentials /secure/path/eng-channel.json --port 8787
```

The listener binds `127.0.0.1` unless `--public-bind` is explicitly supplied. Keep
it on loopback and forward only HTTPS requests from the reverse proxy. Copy the HTTPS
URL, channel UUID, and Base64 token from the credential file into Eng's Config tab.
The token is stored in iPhone Keychain.

Start the Mac bridge with the same channel and public HTTPS URL:

```sh
ENG_RELAY_URL=https://eng-relay.example.com \
ENG_RELAY_CREDENTIALS=/secure/path/eng-channel.json \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run eng-bridge
```

Both devices make outbound HTTPS requests, so no inbound home-router port is needed.
Local USB-C/Wi-Fi remains preferred in Automatic mode. The relay receives only public
pairing material and bounded AES-GCM ciphertext; Codex App Server remains on Mac
loopback. Revoke access by issuing a new channel and replacing both configurations.

The running bridge publishes its owned loopback port and process identifier to
`~/Library/Application Support/EngBridge/runtime.json`. `Scripts/codex-eng`
uses that state instead of assuming port 47321, rejects stale ownership records,
and still honors an explicit `IOS_ENG_CODEX_PORT` override.

## Privacy

Eng is local-first. It does not contain an OpenAI API key, copy Codex authentication to the phone, or expose Codex App Server. Its Bonjour TCP listener and optional remote relay path perform Curve25519 key agreement, pin both device identities, and accept only authenticated AES-GCM frames. Remote channel tokens stay in the relay's protected credential file and iPhone Keychain. Diagnostic history is short-lived and remains on the two devices.
