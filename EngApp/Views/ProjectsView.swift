import EngCore
import SwiftUI

struct ProjectsView: View {
  @EnvironmentObject private var store: BridgeStore

  var body: some View {
    NavigationStack {
      ZStack {
        EngCanvas()
        ScrollView {
          LazyVStack(spacing: 16) {
            summaryHeader
            if store.projects.isEmpty {
              emptyState
            } else {
              ForEach(store.projects) { project in
                ProjectCard(project: project)
              }
            }
          }
          .padding(.horizontal, 18)
          .padding(.bottom, 28)
        }
        .refreshable { store.refresh() }
      }
      .toolbarBackground(.hidden, for: .navigationBar)
      .navigationTitle("Eng")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { ConnectionPill() }
      }
    }
  }

  private var summaryHeader: some View {
    HStack(spacing: 10) {
      SummaryChip(value: "\(store.projects.count)", label: "Projects")
      SummaryChip(value: "\(allThreads.count)", label: "Threads")
      SummaryChip(value: "\(liveThreads.count)", label: "Live")
    }
    .padding(.vertical, 4)
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "rectangle.stack.badge.play")
        .font(.system(size: 38))
        .foregroundStyle(EngDesign.accent)
      Text("No Codex projects yet")
        .font(.title3.weight(.semibold))
      Text(
        "Start a thread from your IDE with Scripts/codex-eng. It will appear here automatically."
      )
      .font(.subheadline)
      .foregroundStyle(EngDesign.muted)
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 52)
    .glassCard()
  }

  private var allThreads: [ThreadSummary] { store.projects.flatMap(\.threads) }
  private var liveThreads: [ThreadSummary] { allThreads.filter { $0.controlLevel == .live } }
}

private struct SummaryChip: View {
  let value: String
  let label: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.title3.weight(.bold).monospacedDigit())
      Text(label)
        .font(.caption2.weight(.medium))
        .foregroundStyle(EngDesign.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
    .overlay { RoundedRectangle(cornerRadius: 18).stroke(EngDesign.border) }
  }
}

private struct ProjectCard: View {
  let project: ProjectSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack(alignment: .top, spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 14)
            .fill(EngDesign.accent.opacity(0.18))
          Image(systemName: "shippingbox.fill")
            .foregroundStyle(EngDesign.accent)
        }
        .frame(width: 44, height: 44)

        VStack(alignment: .leading, spacing: 4) {
          Text(project.name)
            .font(.headline)
          Text(project.repositoryRoot)
            .font(.caption2.monospaced())
            .foregroundStyle(EngDesign.muted)
            .lineLimit(1)
        }
        Spacer()
        if project.activeThreadCount > 0 {
          Text("\(project.activeThreadCount) active")
            .font(.caption2.weight(.bold))
            .foregroundStyle(EngDesign.cyan)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(EngDesign.cyan.opacity(0.12), in: Capsule())
        }
      }

      Divider().overlay(EngDesign.border)

      VStack(spacing: 5) {
        ForEach(project.threads.prefix(6)) { thread in
          NavigationLink {
            ThreadView(thread: thread)
          } label: {
            ThreadRow(thread: thread)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .glassCard(padding: 16)
  }
}

private struct ThreadRow: View {
  let thread: ThreadSummary

  var body: some View {
    HStack(spacing: 11) {
      StatusDot(
        color: thread.status.presentationColor,
        pulsing: thread.status == .active
      )
      VStack(alignment: .leading, spacing: 3) {
        Text(thread.title)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        HStack(spacing: 6) {
          Label(
            thread.controlLevel.presentationLabel,
            systemImage: thread.controlLevel.presentationSymbol)
          Text("·")
          Text(thread.updatedAt, style: .relative)
        }
        .font(.caption2)
        .foregroundStyle(EngDesign.muted)
      }
      Spacer()
      if thread.needsAttention {
        Image(systemName: "exclamationmark.bubble.fill")
          .foregroundStyle(EngDesign.amber)
      }
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(EngDesign.muted)
    }
    .padding(.vertical, 9)
    .contentShape(Rectangle())
  }
}
