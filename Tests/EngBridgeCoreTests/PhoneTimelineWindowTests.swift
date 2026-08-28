import EngCore
import Foundation
import Testing

@testable import EngBridgeCore

struct PhoneTimelineWindowTests {
  @Test func projectionKeepsNewestActivityInsideThePhoneFrameBudget() throws {
    let items = (0..<100).map { index in
      TimelineItem(
        id: "item-\(index)",
        threadID: "thread-1",
        turnID: "turn-1",
        kind: .command,
        state: index == 99 ? .running : .completed,
        title: "Command \(index)",
        body: String(repeating: "output-\(index)-", count: 2_000),
        timestamp: Date(timeIntervalSince1970: Double(index))
      )
    }

    let projected = PhoneTimelineWindow.project(items)
    let detail = ThreadDetail(
      thread: ThreadSummary(
        id: "thread-1",
        title: "Large thread",
        preview: "Preview",
        cwd: "/tmp",
        repositoryRoot: "/tmp",
        source: "cli",
        status: .active,
        controlLevel: .observe,
        activeTurnID: "turn-1",
        updatedAt: .now
      ),
      timeline: projected
    )
    let encoded = try JSONEncoder().encode(BridgeEnvelope(message: .threadDetail(detail)))

    #expect(projected.last?.id == "item-99")
    #expect(projected.count < items.count)
    #expect(encoded.count < 64_000)
  }
}
