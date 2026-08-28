import EngCore
import SwiftUI

struct ProjectsView: View {
  @EnvironmentObject private var store: BridgeStore
  @State private var query = ""
  @State private var activeOnly = false
  @State private var collapsedProjects: Set<String> = []
  @State private var expandedProjects: Set<String> = []
  @Namespace private var threadTransition

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
        "\(visibleProjects.count) shown",
        "\(allThreads.count) threads",
        "\(store.unreadCount) unread",
        "\(store.draftCount) drafts",
        "\(store.pinnedProjectCount) pinned",
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
                pinned: store.isProjectPinned(entry.project.id),
                onToggleCollapse: { toggle(entry.project.id, in: &collapsedProjects) },
                onToggleShowAll: { toggle(entry.project.id, in: &expandedProjects) },
                onTogglePin: { store.toggleProjectPin(entry.project.id) },
                transitionNamespace: threadTransition
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

  private var allThreads: [ThreadSummary] {
    store.projects.flatMap(\.threads).filter { !store.isThreadHidden($0.id) }
  }
  private var liveThreads: [ThreadSummary] { allThreads.filter { $0.controlLevel == .live } }

  /// Projects sorted by most recent thread activity, filtered by the search field and
  /// the Active checkbox. A query that matches the project itself keeps every thread;
  /// otherwise only matching threads are listed.
  private var visibleProjects: [ProjectEntry] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return
      store.projects
      .filter { !store.focusPinnedOnly || store.isProjectPinned($0.id) }
      .compactMap { project -> ProjectEntry? in
        var threads = project.threads.filter { !store.isThreadHidden($0.id) }
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
        guard !threads.isEmpty else { return nil }
        return ProjectEntry(project: project, threads: threads)
      }
      .enumerated()
      .sorted { lhs, rhs in
        let lhsPinned = store.isProjectPinned(lhs.element.id)
        let rhsPinned = store.isProjectPinned(rhs.element.id)
        if lhsPinned != rhsPinned { return lhsPinned && !rhsPinned }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
  }

  private func toggle(_ id: String, in set: inout Set<String>) {
    if set.contains(id) { set.remove(id) } else { set.insert(id) }
  }
}

private struct ProjectEntry: Identifiable {
  let project: ProjectSummary
  let threads: [ThreadSummary]

  var id: String { project.id }
}

private struct ProjectNode: View {
  @EnvironmentObject private var store: BridgeStore
  let project: ProjectSummary
  let threads: [ThreadSummary]
  let collapsed: Bool
  let showsAll: Bool
  let pinned: Bool
  let onToggleCollapse: () -> Void
  let onToggleShowAll: () -> Void
  let onTogglePin: () -> Void
  let transitionNamespace: Namespace.ID

  private var visibleThreads: ArraySlice<ThreadSummary> {
    showsAll ? threads[...] : threads.prefix(ProjectsView.previewThreadLimit)
  }

  private var hiddenCount: Int { threads.count - visibleThreads.count }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 3) {
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
            let activeCount = threads.filter { $0.status == .active || $0.status == .waiting }.count
            if activeCount > 0 {
              Text("\(activeCount) active")
                .font(Win95Font.smallBold)
            }
            let unread = store.unreadCount(in: threads)
            if unread > 0 {
              Text("\(unread) unread")
                .font(Win95Font.smallBold)
                .foregroundStyle(Win95.highlight)
            }
          }
          .padding(.leading, 6)
          .padding(.vertical, 4)
          .contentShape(Rectangle())
        }
        .buttonStyle(Win95RowStyle())

        Button(action: onTogglePin) {
          Image(systemName: pinned ? "pin.fill" : "pin")
            .font(.system(size: 12, weight: .bold))
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(Win95RowStyle())
        .accessibilityLabel(pinned ? "Unpin \(project.name)" : "Pin \(project.name)")
      }
      .padding(.trailing, 3)

      if !collapsed {
        ForEach(visibleThreads) { thread in
          HStack(spacing: 0) {
            NavigationLink {
              ThreadView(thread: thread)
                .navigationTransition(.zoom(sourceID: thread.id, in: transitionNamespace))
            } label: {
              ThreadRow(thread: thread)
                .matchedTransitionSource(id: thread.id, in: transitionNamespace)
            }
            .buttonStyle(Win95RowStyle())
            .frame(maxWidth: .infinity)

            Button {
              store.hideThread(thread.id)
            } label: {
              Image(systemName: "eye.slash")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(Win95RowStyle())
            .accessibilityLabel("Hide \(thread.title)")
          }
          .padding(.trailing, 3)
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
  @EnvironmentObject private var store: BridgeStore
  let thread: ThreadSummary

  var body: some View {
    HStack(spacing: 6) {
      TreeBranch()
      Win95LED(color: thread.status.ledColor, blinking: thread.status.ledBlinks)
      Image(systemName: "doc.text")
        .font(.system(size: 12))
      VStack(alignment: .leading, spacing: 1) {
        Text(thread.title)
          .font(Win95Font.bold)
          .lineLimit(1)
        if !thread.preview.isEmpty {
          Text(
            store.currentActivitySummary(for: thread)
              ?? "\(thread.activityPrefix): \(thread.preview)"
          )
          .font(Win95Font.small)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 4) {
          Image(systemName: thread.controlLevel.presentationSymbol)
            .font(.system(size: 9))
          Text(thread.controlLevel.presentationLabel)
          Text("·")
          Text(thread.status.presentationLabel)
          Text("·")
          if thread.status == .active {
            Text("Live now")
            Text("·")
          }
          Text("Updated")
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
      if store.isThreadUnread(thread.id) {
        Text("NEW")
          .font(Win95Font.smallBold)
          .foregroundStyle(Win95.highlightText)
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(Win95.highlight)
          .accessibilityLabel("Unread")
      }
      if store.hasDraft(thread.id) {
        Text("DRAFT")
          .font(Win95Font.smallBold)
          .foregroundStyle(Win95.text)
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(Win95.warning)
          .accessibilityLabel("Saved draft")
      }
    }
    .padding(.leading, 22)
    .padding(.trailing, 6)
    .padding(.vertical, 5)
    .contentShape(Rectangle())
  }
}

extension ThreadSummary {
  fileprivate var activityPrefix: String {
    switch status {
    case .active: "Current request"
    case .waiting: "Waiting for you"
    case .idle: "Last activity"
    case .notLoaded: "Saved context"
    case .systemError: "Diagnostic"
    }
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
