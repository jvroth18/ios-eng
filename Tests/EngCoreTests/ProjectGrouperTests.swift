import Foundation
import Testing

@testable import EngCore

struct ProjectGrouperTests {
  @Test func groupsByRepositoryAndPrioritizesAttention() throws {
    let older = Date(timeIntervalSince1970: 100)
    let newer = Date(timeIntervalSince1970: 200)
    let records = [
      CodexThreadRecord(
        id: "idle",
        name: "Refactor",
        preview: "Refactor",
        cwd: "/work/relay/apps/web",
        repositoryRoot: "/work/relay",
        source: "cli",
        status: .idle,
        controlLevel: .message,
        updatedAt: newer
      ),
      CodexThreadRecord(
        id: "waiting",
        preview: "Deploy safely\nwith read-back",
        cwd: "/work/relay",
        repositoryRoot: "/work/relay/",
        source: "vscode",
        status: .waiting,
        controlLevel: .live,
        activeTurnID: "turn-2",
        needsAttention: true,
        updatedAt: older
      ),
      CodexThreadRecord(
        id: "other",
        preview: "Build mobile app",
        cwd: "/work/ios-eng",
        repositoryRoot: "/work/ios-eng",
        source: "cli",
        status: .notLoaded,
        controlLevel: .observe,
        updatedAt: newer
      ),
    ]

    let projects = ProjectGrouper.group(records)
    #expect(projects.map(\.name) == ["relay", "ios-eng"])
    let relay = try #require(projects.first)
    #expect(relay.threads.map(\.id) == ["waiting", "idle"])
    #expect(relay.threads[0].title == "Deploy safely")
    #expect(relay.activeThreadCount == 1)
  }

  @Test func projectIdentityIsDeterministicAndPathSensitive() {
    let first = ProjectGrouper.stableProjectID(for: "/work/relay/")
    #expect(first == ProjectGrouper.stableProjectID(for: "/work/relay"))
    #expect(first != ProjectGrouper.stableProjectID(for: "/work/relay-web"))
  }
}
