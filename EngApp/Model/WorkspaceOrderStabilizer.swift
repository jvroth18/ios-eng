import EngCore

enum WorkspaceOrderStabilizer {
  static func apply(
    _ updated: WorkspaceSnapshot,
    preserving previous: WorkspaceSnapshot?
  ) -> WorkspaceSnapshot {
    guard let previous else { return updated }

    let updatedProjects = Dictionary(uniqueKeysWithValues: updated.projects.map { ($0.id, $0) })
    let previousProjectIDs = previous.projects.map(\.id)
    let projectIDs = stableIDs(previous: previousProjectIDs, updated: updated.projects.map(\.id))
    let previousProjects = Dictionary(uniqueKeysWithValues: previous.projects.map { ($0.id, $0) })

    let projects = projectIDs.compactMap { projectID -> ProjectSummary? in
      guard let project = updatedProjects[projectID] else { return nil }
      guard let oldProject = previousProjects[projectID] else { return project }
      let threadsByID = Dictionary(uniqueKeysWithValues: project.threads.map { ($0.id, $0) })
      let threadIDs = stableIDs(
        previous: oldProject.threads.map(\.id), updated: project.threads.map(\.id))
      return ProjectSummary(
        id: project.id,
        name: project.name,
        repositoryRoot: project.repositoryRoot,
        gitOrigin: project.gitOrigin,
        threads: threadIDs.compactMap { threadsByID[$0] },
        updatedAt: project.updatedAt
      )
    }

    return WorkspaceSnapshot(
      bridgeName: updated.bridgeName,
      projects: projects,
      generatedAt: updated.generatedAt
    )
  }

  private static func stableIDs(previous: [String], updated: [String]) -> [String] {
    let current = Set(updated)
    let retained = previous.filter(current.contains)
    let retainedSet = Set(retained)
    return retained + updated.filter { !retainedSet.contains($0) }
  }
}
