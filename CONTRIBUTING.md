# Contributing

Thank you for helping improve Eng. Keep changes focused, preserve the local-first
security boundary, and never include credentials, Codex content, device identifiers,
or diagnostic captures in an issue, fixture, commit, or pull request.

Before opening a pull request, run the validations for the area you changed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
cd CloudflareRelay
npm ci
npm audit
npm run check
npm test
npx wrangler deploy --dry-run
```

Generate `Eng.xcodeproj` from `project.yml` with XcodeGen before testing the iOS app.
Do not commit the generated project. Security reports belong in GitHub private
vulnerability reporting as described in [SECURITY.md](SECURITY.md).
