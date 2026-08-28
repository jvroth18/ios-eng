import Foundation
import Testing

@testable import EngBridgeCore

struct ExternalThreadControllerTests {
  @Test func acceptsOnlySameUserInteractiveCodexWriters() {
    #expect(
      CodexCLIExternalThreadController.isSafeInteractiveCodexWriter(
        "501 ttys089 /opt/homebrew/bin/codex", expectedUserID: 501))
    #expect(
      !CodexCLIExternalThreadController.isSafeInteractiveCodexWriter(
        "501 ?? /opt/homebrew/bin/codex", expectedUserID: 501))
    #expect(
      !CodexCLIExternalThreadController.isSafeInteractiveCodexWriter(
        "502 ttys089 /opt/homebrew/bin/codex", expectedUserID: 501))
    #expect(
      !CodexCLIExternalThreadController.isSafeInteractiveCodexWriter(
        "501 ttys089 /usr/bin/python3", expectedUserID: 501))
  }

  @Test func queueUsesTheSupportedCodexQueueCommand() async throws {
    let recorder = CommandRecorder()
    let controller = CodexCLIExternalThreadController(
      codexHome: URL(fileURLWithPath: "/tmp/codex-test"),
      userID: 501,
      run: { executable, arguments in
        await recorder.record(executable: executable, arguments: arguments)
        return ShellResult(status: 0, output: "queued", error: "")
      },
      sendSignal: { _, _ in }
    )

    try await controller.queue(
      threadID: "01a0443a-e741-70f2-8738-760a9a5d4332",
      message: "Phone message"
    )

    #expect(
      await recorder.commands == [
        "/usr/bin/env codex queue --thread 01a0443a-e741-70f2-8738-760a9a5d4332 --message Phone message"
      ])
  }
}

private actor CommandRecorder {
  private(set) var commands: [String] = []

  func record(executable: String, arguments: [String]) {
    commands.append(([executable] + arguments).joined(separator: " "))
  }
}
