import EngCore
import SwiftUI

struct ProjectsView: View {
  @EnvironmentObject private var store: BridgeStore
  @State private var query = ""
  @State private var activeOnly = false
  @State private var collapsedProjects: Set<String> = []
  @State private var expandedProjects: Set<String> = []

  /// Threads shown per project before the "more" row appears.
  static let previewThreadLimit = 6

  var body: some View {
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        Button("Refresh") {
          store.refresh()
        }
        .buttonStyle(Win95ButtonStyle(compact: true))
        TextField("Find project or thread", text: $query)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .win95Field()
        Win95Checkbox(label: "Active", isOn: $activeOnly)
      }

      Win95StatusBar(items: [
        "\(store.projects.count) projects",
        "\(allThreads.count) threads",
        "\(liveThreads.count) live",
      ])

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if visibleProjects.isEmpty {
            emptyState
          } else {
            ForEach(visibleProjects) { entry in
              ProjectNode(
                project: entry.project,
                threads: entry.threads,
                collapsed: collapsedProjects.contains(entry.project.id),
                showsAll: expandedProjects.contains(entry.project.id) || !query.isEmpty,
                onToggleCollapse: { toggle(entry.project.id, in: &collapsedProjects) },
                onToggleShowAll: { toggle(entry.project.id, in: &expandedProjects) }
              )
            }
          }
        }
        .padding(.vertical, 3)
      }
      .scrollIndicators(.hidden)
      .refreshable { store.refresh() }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .sunkenPaper()
    }
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: store.projects.isEmpty ? "folder" : "magnifyingglass")
        .font(.system(size: 30))
        .foregroundStyle(Win95.shadow)
      Text(store.projects.isEmpty ? "No Codex projects yet" : "No matches")
        .font(Win95Font.bold)
        .foregroundStyle(Win95.text)
      Text(
        store.projects.isEmpty
          ? "Start a thread from your IDE with Scripts/codex-eng. It will appear here."
          : "Try a different search or turn off the Active filter."
      )
      .font(Win95Font.small)
      .foregroundStyle(Win95.text)
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 48)
    .padding(.horizontal, 20)
  }

  private var allThreads: [ThreadSummary] { store.projects.flatMap(\.threads) }
  private var liveThreads: [ThreadSummary] { allThreads.filter { $0.controlLevel == .live } }

  /// Projects sorted by most recent thread activity, filtered by the search field and
  /// the Active checkbox. A query that matches the project itself keeps every thread;
  /// otherwise only matching threads are listed.
  private var visibleProjects: [ProjectEntry] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return
      store.projects
      .compactMap { project -> ProjectEntry? in
        var threads = project.threads
        if activeOnly {
          threads = threads.filter { $0.status == .active || $0.status == .waiting }
        }
        if !needle.isEmpty {
          let projectMatches =
            project.name.lowercased().contains(needle)
            || project.repositoryRoot.lowercased().contains(needle)
          if !projectMatches {
            threads = threads.filter {
              $0.title.lowercased().contains(needle) || $0.preview.lowercased().contains(needle)
            }
          }
        }
        guard !threads.isEmpty || (needle.isEmpty && !activeOnly) else { return nil }
        let sorted = threads.sorted { $0.updatedAt > $1.updatedAt }
        return ProjectEntry(project: project, threads: sorted)
      }
      .sorted { $0.latestActivity > $1.latestActivity }
  }

  private func toggle(_ id: String, in set: inout Set<String>) {
    if set.contains(id) { set.remove(id) } else { set.insert(id) }
  }
}

private struct ProjectEntry: Identifiable {
  let project: ProjectSummary
  let threads: [ThreadSummary]

  var id: String { project.id }
  var latestActivity: Date {
    threads.map(\.updatedAt).max() ?? project.updatedAt
  }
}

private struct ProjectNode: View {
  let project: ProjectSummary
  let threads: [ThreadSummary]
  let collapsed: Bool
  let showsAll: Bool
  let onToggleCollapse: () -> Void
  let onToggleShowAll: () -> Void

  private var visibleThreads: ArraySlice<ThreadSummary> {
    showsAll ? threads[...] : threads.prefix(ProjectsView.previewThreadLimit)
  }

  private var hiddenCount: Int { threads.count - visibleThreads.count }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(action: onToggleCollapse) {
        HStack(spacing: 6) {
          TreeExpander(expanded: !collapsed)
          Image(systemName: "folder.fill")
            .font(.system(size: 13))
            .foregroundStyle(Win95.folder)
            .overlay(Image(systemName: "folder").font(.system(size: 13)).foregroundStyle(.black))
          Text(project.name)
            .font(Win95Font.bold)
          Text(project.repositoryRoot)
            .font(Win95Font.monoSmall)
            .lineLimit(1)
            .truncationMode(.head)
            .opacity(0.7)
          Spacer(minLength: 4)
          if project.activeThreadCount > 0 {
            Text("\(project.activeThreadCount) active")
              .font(Win95Font.smallBold)
          }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(Win95RowStyle())

      if !collapsed {
        ForEach(visibleThreads) { thread in
          NavigationLink {
            ThreadView(thread: thread)
          } label: {
            ThreadRow(thread: thread)
          }
          .buttonStyle(Win95RowStyle())
        }
        if hiddenCount > 0 || (showsAll && threads.count > ProjectsView.previewThreadLimit) {
          Button(action: onToggleShowAll) {
            HStack(spacing: 6) {
              TreeBranch()
              Text(
                hiddenCount > 0
                  ? "Show \(hiddenCount) more thread\(hiddenCount == 1 ? "" : "s")…"
                  : "Show fewer threads"
              )
              .font(Win95Font.small)
              .underline()
              Spacer()
            }
            .padding(.leading, 22)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
          }
          .buttonStyle(Win95RowStyle())
        }
      }
    }
  }
}

private struct ThreadRow: View {
  let thread: ThreadSummary

  var body: some View {
    HStack(spacing: 6) {
      TreeBranch()
      Win95LED(color: thread.status.ledColor, blinking: thread.status.ledBlinks)
      Image(systemName: "doc.text")
        .font(.system(size: 12))
      VStack(alignment: .leading, spacing: 1) {
        Text(thread.title)
          .font(Win95Font.body)
          .lineLimit(1)
        HStack(spacing: 4) {
          Image(systemName: thread.controlLevel.presentationSymbol)
            .font(.system(size: 9))
          Text(thread.controlLevel.presentationLabel)
          Text("·")
          Text(thread.status.presentationLabel)
          Text("·")
          Text(thread.updatedAt, style: .relative)
        }
        .font(Win95Font.small)
        .opacity(0.75)
        .lineLimit(1)
      }
      Spacer(minLength: 4)
      if thread.needsAttention {
        Image(systemName: "exclamationmark.triangle.fill")
          .symbolRenderingMode(.palette)
          .foregroundStyle(.black, Win95.warning)
          .font(.system(size: 13))
      }
    }
    .padding(.leading, 22)
    .padding(.trailing, 6)
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }
}

/// Dotted Explorer-style tree connector.
private struct TreeBranch: View {
  var body: some View {
    Canvas { context, size in
      var vertical = Path()
      vertical.move(to: CGPoint(x: 0.5, y: 0))
      vertical.addLine(to: CGPoint(x: 0.5, y: size.height))
      var horizontal = Path()
      horizontal.move(to: CGPoint(x: 0, y: size.height / 2))
      horizontal.addLine(to: CGPoint(x: size.width, y: size.height / 2))
      let style = StrokeStyle(lineWidth: 1, dash: [1, 1])
      context.stroke(vertical, with: .color(Win95.shadow), style: style)
      context.stroke(horizontal, with: .color(Win95.shadow), style: style)
    }
    .frame(width: 10, height: 20)
  }
}
