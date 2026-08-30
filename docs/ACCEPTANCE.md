# Acceptance matrix

This file keeps the original goal testable instead of allowing the implementation to redefine it.

| Requirement | Authoritative evidence required |
| --- | --- |
| New `ios-eng` folder and GitHub repository | Local clean `main`, `origin` URL, and matching local/remote commit hash |
| Native application installable from Xcode on Jordan's iPhone | Signed generic/device build, `devicectl` install, launch read-back, and visible app identity |
| Connects to active Codex work on the Mac | Live bridge smoke against the installed Codex CLI plus a real CLI-created test thread |
| Open projects correspond to the repository where each thread runs | App Server `cwd` fixtures and live Git-root grouping evidence |
| Full bidirectional mirror | History read, real `thread/resume`, streamed agent/tool/file/plan deltas, phone turn within an existing thread, active-turn steer, interrupt, approval/input response, and Mac-side read-back where supported |
| Active Mac writer | Selecting a thread owned by another Codex process opens a bounded `Mac Live` transcript instead of raising an active-writer error; phone text queues into the owner and Stop is available only for a verified interactive CLI writer |
| Phone cannot create or delete threads | Explicit command allowlist, no create/fork/archive/delete protocol cases or UI, and tests asserting no `thread/start` call while existing-thread interaction remains available |
| Active Mac threads stream to the phone | Loaded-thread discovery, bridge-side resume, connection-scoped subscriptions, two-client live notification probe, and recovery resubscription tests |
| Stop, model, keyboard, and draft controls | Always-present guarded Stop action, App Server account model catalog plus exact existing-thread settings update, whole-window keyboard animation, and independent persisted per-thread draft tests and indicators |
| Reversible thread hiding | Explicit phone-local Hide action, persisted hidden UUIDs, quiet hidden activity, preserved drafts, Config Unhide and Unhide all controls, and no archive/delete bridge command |
| Beautifully simple | Rendered simulator/device screenshots of Projects, Thread, pairing/empty/error states, and accessibility checks |
| Analytics for iPhone and MacBook | Live CPU/memory/disk/power/thermal/interface/throughput/latency samples with timestamps from both devices |
| Bluetooth and Wi-Fi nearby operation | Apple Nearby Auto transport with required encryption, explicit supported-bearer copy, and no unsupported claim about the selected radio |
| USB-C local operation | Public Network Framework path over Apple’s `iPhone USB` Personal Hotspot interface, wired-interface preference and honest bearer label, with no private USB or developer forwarding API |
| Fast secure remote path | Transport-neutral protocol, authenticated direct-local implementation, and host-key-verified SSH tunnel without exposing App Server or Codex credentials |
| Hosted open-source remote path | Apache-2.0 Cloudflare Worker, one Durable Object per random channel, distinct role credentials, opaque bounded WebSocket routing, revocation, runtime tests, and reproducible deployment workflow |
| Honest temperature behavior | Public thermal-state categories; no degree value or private API in source |
| Incremental implementation | Separate validated commits pushed after contract, bridge, app, and final end-to-end phases |

Simulator success alone does not satisfy the install, device telemetry, nearby transport, or live Codex requirements.
