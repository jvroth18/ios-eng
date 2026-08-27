# Acceptance matrix

This file keeps the original goal testable instead of allowing the implementation to redefine it.

| Requirement | Authoritative evidence required |
| --- | --- |
| New `ios-eng` folder and GitHub repository | Local clean `main`, `origin` URL, and matching local/remote commit hash |
| Native application installable from Xcode on Jordan's iPhone | Signed generic/device build, `devicectl` install, launch read-back, and visible app identity |
| Connects to active Codex work on the Mac | Live bridge smoke against the installed Codex CLI plus a real CLI-created test thread |
| Open projects correspond to the repository where each thread runs | App Server `cwd` fixtures and live Git-root grouping evidence |
| Full bidirectional mirror | History read, streamed agent delta, phone message/new turn, active-turn steer, interrupt, approval/input response, and Mac-side read-back where supported |
| Beautifully simple | Rendered simulator/device screenshots of Projects, Thread, pairing/empty/error states, and accessibility checks |
| Analytics for iPhone and MacBook | Live CPU/memory/disk/power/thermal/interface/throughput/latency samples with timestamps from both devices |
| Honest temperature behavior | Public thermal-state categories; no degree value or private API in source |
| Incremental implementation | Separate validated commits pushed after contract, bridge, app, and final end-to-end phases |

Simulator success alone does not satisfy the install, device telemetry, nearby transport, or live Codex requirements.

