# ios-eng working agreements

- Implement in coherent phases. Validate, commit, push, and verify the remote hash after every phase.
- `project.yml` is the source of truth for the Xcode project. Regenerate with `xcodegen generate`; do not commit the generated `.xcodeproj`.
- Keep the phone transport private. Never persist Codex credentials, browser cookies, approval tokens, or conversation data outside the Mac and paired iPhone.
- Use only public Apple APIs. Report thermal state honestly; never label an estimate as a temperature reading.
- Treat ordinary observed CLI sessions and bridge-controlled sessions differently. The UI must expose the actual control level.
- A simulator build proves compilation and layout only. Keep simulator, signed-device build, installation, launch, and live Mac bridge evidence separate.

