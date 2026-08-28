import EngCore
import Foundation
import Testing

@testable import EngBridgeCore

struct PhoneCommandPolicyTests {
  @Test func allowsOnlyExistingThreadInteractionAndDiagnostics() {
    let allowed: [BridgeMessage] = [
      .refresh(RefreshRequest()),
      .subscribe(ThreadSubscription(threadID: "existing-thread")),
      .sendMessage(SendMessageRequest(threadID: "existing-thread", text: "Continue")),
      .setThreadModel(
        SetThreadModelRequest(threadID: "existing-thread", model: "gpt-5.6-terra")),
      .interrupt(InterruptRequest(threadID: "existing-thread", turnID: "active-turn")),
      .approvalResponse(ApprovalResponse(requestID: "approval", decision: .accept)),
      .userInputResponse(UserInputResponse(requestID: "input", answers: ["q": "answer"])),
      .analytics(AnalyticsSnapshot(phone: nil, mac: nil, link: LinkTelemetry())),
      .ping(Ping(sequence: 1, clientSentAt: Date(), payloadBytes: 1)),
    ]
    #expect(allowed.allSatisfy(PhoneCommandPolicy.permits))

    let serverOnly: [BridgeMessage] = [
      .workspaceSnapshot(WorkspaceSnapshot(bridgeName: "Mac", projects: [])),
      .threadDetail(
        ThreadDetail(
          thread: ThreadSummary(
            id: "existing-thread", title: "Existing", preview: "", cwd: "/tmp",
            repositoryRoot: "/tmp", source: "cli", status: .idle, controlLevel: .live,
            updatedAt: Date()),
          timeline: [])),
      .timelineEvent(
        TimelineItem(
          id: "item", threadID: "existing-thread", kind: .system, state: .completed,
          title: "Event", body: "", timestamp: Date())),
      .error(BridgeError(code: "server", message: "server only", recoverable: false)),
    ]
    #expect(serverOnly.allSatisfy { !PhoneCommandPolicy.permits($0) })
  }
}
