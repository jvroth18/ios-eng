# Eng

Eng is a private, native iPhone companion for Codex work running on your Mac. It groups threads by the repository they are working in, mirrors conversation and tool activity, lets you send or steer work from the phone, surfaces approvals when the Mac session supports them, and shows live phone/Mac diagnostics.

The repository contains three pieces:

- `EngCore`: the versioned, tested wire protocol and shared models.
- `EngBridge`: a Mac companion that connects to Codex App Server and advertises an encrypted nearby session.
- `Eng`: a deliberately small SwiftUI iPhone app with Projects, Thread, and Analytics surfaces.

## Product boundary

Codex App Server is the supported deep-client interface for conversation history, streamed events, turns, steering, and approvals. Eng keeps that interface on the Mac. The phone talks only to the paired bridge over an encrypted Apple Multipeer Connectivity session.

Ordinary CLI sessions can always be discovered from Codex's local thread store. Live steering and approval handling require the thread to be controllable by the bridge/shared App Server. Eng displays `Observe`, `Message`, or `Live` on every thread so the user can see the real boundary.

## Status

This repository is being delivered in validated, incremental commits:

1. Shared mirror and telemetry contract.
2. Mac bridge, Codex integration, diagnostics, and CLI workflow.
3. Native iPhone app and Analytics view.
4. End-to-end simulator/device validation and installation handoff.

See [Architecture](docs/ARCHITECTURE.md) and [Acceptance](docs/ACCEPTANCE.md).

## Development

Requirements: Xcode 26+, Swift 6, XcodeGen 2.46+, and a current authenticated Codex CLI.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The generated Xcode project is intentionally ignored. Once `project.yml` lands, regenerate it with `xcodegen generate` before opening it in Xcode.

## Privacy

Eng is local-first. It does not contain an OpenAI API key, copy Codex authentication to the phone, or open a LAN HTTP/WebSocket port. Pairing and traffic use an encrypted nearby session. Diagnostic history is short-lived and remains on the two devices.

