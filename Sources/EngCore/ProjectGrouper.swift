import Foundation

public enum ProjectGrouper {
  public static func group(_ records: [CodexThreadRecord]) -> [ProjectSummary] {
    let grouped = Dictionary(grouping: records) { record in
      normalizedRoot(record.repositoryRoot ?? record.cwd)
    }

    return grouped.map { root, records in
      let threads =
        records
        .map { summary(from: $0, root: root) }
        .sorted(by: threadOrdering)
      let newest = threads.map(\.updatedAt).max() ?? .distantPast
      let origin = records.compactMap(\.gitOrigin).first
      return ProjectSummary(
        id: stableProjectID(for: root),
        name: projectName(for: root),
        repositoryRoot: root,
        gitOrigin: origin,
        threads: threads,
        updatedAt: newest
      )
    }
    .sorted { lhs, rhs in
      if lhs.activeThreadCount != rhs.activeThreadCount {
        return lhs.activeThreadCount > rhs.activeThreadCount
      }
      if lhs.updatedAt != rhs.updatedAt {
        return lhs.updatedAt > rhs.updatedAt
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  public static func stableProjectID(for repositoryRoot: String) -> String {
    // Deterministic FNV-1a keeps local paths out of navigation IDs without adding a dependency.
    let bytes = normalizedRoot(repositoryRoot).utf8
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in bytes {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }

  private static func summary(from record: CodexThreadRecord, root: String) -> ThreadSummary {
    let trimmedName = record.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedPreview = record.preview.trimmingCharacters(in: .whitespacesAndNewlines)
    let title =
      (trimmedName?.isEmpty == false ? trimmedName : nil)
      ?? firstLine(of: trimmedPreview)
      ?? "Untitled thread"

    return ThreadSummary(
      id: record.id,
      title: title,
      preview: trimmedPreview,
      cwd: record.cwd,
      repositoryRoot: root,
      source: record.source,
      status: record.status,
      controlLevel: record.controlLevel,
      activeTurnID: record.activeTurnID,
      needsAttention: record.needsAttention,
      updatedAt: record.updatedAt
    )
  }

  private static func threadOrdering(_ lhs: ThreadSummary, _ rhs: ThreadSummary) -> Bool {
    let lhsRank = statusRank(lhs.status)
    let rhsRank = statusRank(rhs.status)
    if lhsRank != rhsRank { return lhsRank < rhsRank }
    if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
    return lhs.updatedAt > rhs.updatedAt
  }

  private static func statusRank(_ status: ThreadRuntimeStatus) -> Int {
    switch status {
    case .waiting: 0
    case .active: 1
    case .idle: 2
    case .systemError: 3
    case .notLoaded: 4
    }
  }

  private static func firstLine(of value: String) -> String? {
    value.split(whereSeparator: \.isNewline).first.map(String.init)
  }

  private static func normalizedRoot(_ path: String) -> String {
    let standardized = NSString(string: path).standardizingPath
    if standardized.count > 1, standardized.hasSuffix("/") {
      return String(standardized.dropLast())
    }
    return standardized
  }

  private static func projectName(for root: String) -> String {
    let name = URL(fileURLWithPath: root).lastPathComponent
    return name.isEmpty ? "Mac" : name
  }
}
