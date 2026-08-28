import EngCore
import Foundation
import Testing

@testable import Eng

struct WorkspaceOrderStabilizerTests {
  @Test func refreshUpdatesContentWithoutReorderingExistingProjectsOrThreads() {
    let previous = WorkspaceSnapshot(
      bridgeName: "Mac",
      projects: [
        project("a", threads: [thread("a1", status: .idle), thread("a2", status: .active)]),
        project("b", threads: [thread("b1", status: .idle)]),
      ]
    )
    let updated = WorkspaceSnapshot(
      bridgeName: "Mac",
      projects: [
        project("b", threads: [thread("b1", status: .active)]),
        project(
          "a",
          threads: [
            thread("a2", status: .idle), thread("a1", status: .active),
            thread("a3", status: .active),
          ]),
        project("c", threads: [thread("c1", status: .active)]),
      ]
    )

    let result = WorkspaceOrderStabilizer.apply(updated, preserving: previous)

    #expect(result.projects.map(\.id) == ["a", "b", "c"])
    #expect(result.projects[0].threads.map(\.id) == ["a1", "a2", "a3"])
    #expect(result.projects[0].threads[0].status == .active)
    #expect(result.projects[1].threads[0].status == .active)
  }

  @Test func removedEntriesDisappearWithoutDisturbingSurvivorOrder() {
    let previous = WorkspaceSnapshot(
      bridgeName: "Mac",
      projects: [
        project("a", threads: [thread("a1"), thread("a2"), thread("a3")]),
        project("b", threads: [thread("b1")]),
        project("c", threads: [thread("c1")]),
      ]
    )
    let updated = WorkspaceSnapshot(
      bridgeName: "Mac",
      projects: [
        project("c", threads: [thread("c1")]),
        project("a", threads: [thread("a3"), thread("a1")]),
      ]
    )

    let result = WorkspaceOrderStabilizer.apply(updated, preserving: previous)

    #expect(result.projects.map(\.id) == ["a", "c"])
    #expect(result.projects[0].threads.map(\.id) == ["a1", "a3"])
  }

  private func project(_ id: String, threads: [ThreadSummary]) -> ProjectSummary {
    ProjectSummary(
      id: id,
      name: "Project \(id)",
      repositoryRoot: "/tmp/\(id)",
      threads: threads,
      updatedAt: .now
    )
  }

  private func thread(
    _ id: String,
    status: ThreadRuntimeStatus = .idle
  ) -> ThreadSummary {
    ThreadSummary(
      id: id,
      title: "Thread \(id)",
      preview: "Preview",
      cwd: "/tmp",
      repositoryRoot: "/tmp",
      source: "cli",
      status: status,
      controlLevel: .message,
      updatedAt: .now
    )
  }
}
