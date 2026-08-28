# Eng

Eng is a private, native iPhone companion for Codex work running on your Mac. It groups threads by the repository they are working in, mirrors conversation and tool activity, lets you send or steer work from the phone, surfaces approvals when the Mac session supports them, and shows live phone/Mac diagnostics.

The repository contains three pieces:

- `EngCore`: the versioned, tested wire protocol and shared models.
- `EngBridge`: a Mac companion that connects to Codex App Server and advertises encrypted nearby and direct Wi-Fi sessions.
- `Eng`: a deliberately small SwiftUI iPhone app with Projects, Thread, and Analytics surfaces, drawn in a classic Windows 9x "analog" style (beveled windows, tab pages, LEDs, and a green-phosphor system monitor) from the `EngApp/Design/Win95.swift` kit.

## Product boundary

Codex App Server is the supported deep-client interface for conversation history, streamed events, turns, steering, and approvals. Eng keeps that interface on the Mac. The phone talks only to the paired bridge. Nearby pairing uses encrypted Apple Multipeer Connectivity; after pairing, an authenticated AES-GCM channel automatically prefers direct Wi-Fi and falls back to nearby.

Ordinary CLI sessions can always be discovered from Codex's local thread store. Live steering and approval handling require the thread to be controllable by the bridge/shared App Server. Eng displays `Observe`, `Message`, or `Live` on every thread so the user can see the real boundary.

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

The generated Xcode project is intentionally ignored; `project.yml` is its source of truth. The debug-only `-eng-demo`, `-eng-analytics`, and `-eng-thread` launch arguments render deterministic project, analytics, and thread states for visual QA without altering release behavior. `-eng-pair-code CODE` automates pairing only in debug builds for repeatable simulator integration tests.

On each bridge launch, enter the short pairing code shown in the Mac terminal. Reconnects to that running bridge are automatic. Analytics retains only the most recent 90 in-memory samples per device. Exact iPhone temperature is not available through Apple’s public API, so Eng reports `ProcessInfo.thermalState` categories instead of degrees.

## Privacy

Eng is local-first. It does not contain an OpenAI API key, copy Codex authentication to the phone, or expose Codex App Server. Its Bonjour TCP listener accepts only frames authenticated and encrypted with a random 256-bit credential delivered inside the paired nearby session. Diagnostic history is short-lived and remains on the two devices.
