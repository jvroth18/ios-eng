import EngCore
import SwiftUI

struct ThreadView: View {
  @EnvironmentObject private var store: BridgeStore
  let thread: ThreadSummary

  @State private var draft = ""
  @FocusState private var composerFocused: Bool

  var body: some View {
    ZStack {
      EngCanvas()
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 14) {
            ThreadContextCard(thread: displayedThread)

            if let detail = displayedDetail {
              ForEach(detail.pendingActions) { action in
                PendingActionCard(action: action)
              }

              if detail.timeline.isEmpty {
                emptyTimeline
              } else {
                ForEach(detail.timeline) { item in
                  TimelineRow(item: item)
                    .id(item.id)
                }
              }
            } else {
              ProgressView("Loading thread")
                .tint(EngDesign.cyan)
                .foregroundStyle(EngDesign.muted)
                .padding(.vertical, 60)
            }

            Color.clear.frame(height: 1).id("thread-end")
          }
          .padding(.horizontal, 15)
          .padding(.top, 8)
          .padding(.bottom, 10)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: displayedDetail?.timeline.count) { _, _ in
          withAnimation(.easeOut(duration: 0.24)) {
            proxy.scrollTo("thread-end", anchor: .bottom)
          }
        }
      }
    }
    .navigationTitle(displayedThread.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(EngDesign.canvas.opacity(0.94), for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if let turnID = displayedThread.activeTurnID,
          displayedThread.controlLevel == .live
        {
          Button(role: .destructive) {
            store.interrupt(threadID: displayedThread.id, turnID: turnID)
          } label: {
            Image(systemName: "stop.circle.fill")
          }
          .accessibilityLabel("Interrupt current turn")
        }
      }
    }
    .safeAreaInset(edge: .bottom) { composer }
    .task(id: thread.id) { store.subscribe(to: thread) }
  }

  private var displayedDetail: ThreadDetail? {
    guard store.threadDetail?.thread.id == thread.id else { return nil }
    return store.threadDetail
  }

  private var displayedThread: ThreadSummary { displayedDetail?.thread ?? thread }

  private var emptyTimeline: some View {
    VStack(spacing: 12) {
      Image(systemName: "text.bubble")
        .font(.title)
        .foregroundStyle(EngDesign.accent)
      Text("This thread has no visible messages yet.")
        .font(.subheadline)
        .foregroundStyle(EngDesign.muted)
    }
    .padding(.vertical, 48)
  }

  private var composer: some View {
    VStack(spacing: 7) {
      HStack(alignment: .bottom, spacing: 10) {
        TextField("Message Codex", text: $draft, axis: .vertical)
          .lineLimit(1...5)
          .focused($composerFocused)
          .padding(.horizontal, 14)
          .padding(.vertical, 11)
          .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 18))

        Button {
          let message = draft
          draft = ""
          composerFocused = false
          store.sendMessage(message, to: displayedThread.id)
        } label: {
          ZStack {
            Circle().fill(EngDesign.accent)
            if store.isSending {
              ProgressView().tint(.white)
            } else {
              Image(
                systemName: displayedThread.activeTurnID == nil
                  ? "arrow.up" : "arrow.trianglehead.turn.up.right.diamond.fill"
              )
              .font(.headline.weight(.bold))
              .foregroundStyle(.white)
            }
          }
          .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(canSend ? 1 : 0.45)
      }

      HStack(spacing: 5) {
        Image(systemName: displayedThread.controlLevel.presentationSymbol)
        Text(controlHint)
        Spacer()
      }
      .font(.caption2)
      .foregroundStyle(EngDesign.muted)
      .padding(.horizontal, 3)
    }
    .padding(.horizontal, 13)
    .padding(.top, 10)
    .padding(.bottom, 5)
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) { Divider().overlay(EngDesign.border) }
  }

  private var canSend: Bool { displayedThread.controlLevel == .live && !store.isSending }

  private var controlHint: String {
    switch displayedThread.controlLevel {
    case .live:
      displayedThread.activeTurnID == nil
        ? "Starts a new turn in this existing thread" : "Steers the active turn"
    case .message: "Connecting this existing thread for live control"
    case .observe: "Read-only mirror for this thread"
    }
  }
}

private struct ThreadContextCard: View {
  let thread: ThreadSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        HStack(spacing: 7) {
          StatusDot(color: thread.status.presentationColor, pulsing: thread.status == .active)
          Text(thread.status.presentationLabel)
            .font(.caption.weight(.bold))
        }
        Spacer()
        Label(
          thread.controlLevel.presentationLabel, systemImage: thread.controlLevel.presentationSymbol
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(thread.controlLevel == .live ? EngDesign.cyan : EngDesign.muted)
      }

      Text(thread.cwd)
        .font(.caption2.monospaced())
        .foregroundStyle(EngDesign.muted)
        .lineLimit(2)
      Text(
        "\(thread.source.uppercased()) · Updated \(thread.updatedAt.formatted(.relative(presentation: .named)))"
      )
      .font(.caption2.weight(.medium))
      .foregroundStyle(EngDesign.muted)
    }
    .glassCard(padding: 15)
  }
}

private struct TimelineRow: View {
  let item: TimelineItem

  var body: some View {
    switch item.kind {
    case .user, .assistant:
      MessageBubble(item: item)
    case .reasoning, .plan, .command, .fileChange, .tool, .approval, .system, .error:
      ActivityCard(item: item)
    }
  }
}

private struct MessageBubble: View {
  let item: TimelineItem

  var body: some View {
    HStack {
      if item.kind == .user { Spacer(minLength: 48) }
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 6) {
          Text(item.kind == .user ? "You" : "Codex")
            .font(.caption2.weight(.bold))
          if item.state == .running {
            ProgressView().controlSize(.mini).tint(.white)
          }
        }
        .foregroundStyle(item.kind == .user ? Color.white.opacity(0.82) : EngDesign.cyan)

        Text(item.body.isEmpty ? "…" : item.body)
          .font(.body)
          .textSelection(.enabled)
          .lineSpacing(3)
      }
      .padding(.horizontal, 15)
      .padding(.vertical, 12)
      .background {
        if item.kind == .user {
          RoundedRectangle(cornerRadius: 20, style: .continuous).fill(EngDesign.accent)
        } else {
          RoundedRectangle(cornerRadius: 20, style: .continuous).fill(EngDesign.raised)
        }
      }
      .overlay {
        if item.kind == .assistant {
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(EngDesign.border)
        }
      }
      if item.kind == .assistant { Spacer(minLength: 30) }
    }
  }
}

private struct ActivityCard: View {
  let item: TimelineItem
  @State private var expanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      if !item.body.isEmpty {
        Text(item.body)
          .font(.caption.monospaced())
          .foregroundStyle(Color.white.opacity(0.72))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 10)
      }
    } label: {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .foregroundStyle(color)
          .frame(width: 22)
        VStack(alignment: .leading, spacing: 2) {
          Text(item.title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Text(item.state.rawValue.capitalized)
            .font(.caption2)
            .foregroundStyle(EngDesign.muted)
        }
        Spacer()
        if item.state == .running { ProgressView().controlSize(.small).tint(color) }
      }
    }
    .tint(EngDesign.muted)
    .padding(13)
    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 17))
    .overlay { RoundedRectangle(cornerRadius: 17).stroke(EngDesign.border) }
  }

  private var symbol: String {
    switch item.kind {
    case .reasoning: "brain.head.profile"
    case .plan: "checklist"
    case .command: "terminal.fill"
    case .fileChange: "doc.badge.gearshape"
    case .tool: "wrench.and.screwdriver.fill"
    case .approval: "hand.raised.fill"
    case .error: "exclamationmark.triangle.fill"
    default: "circle.dotted"
    }
  }

  private var color: Color {
    item.kind == .error
      ? EngDesign.coral : (item.state == .running ? EngDesign.cyan : EngDesign.muted)
  }
}

private struct PendingActionCard: View {
  @EnvironmentObject private var store: BridgeStore
  let action: PendingAction
  @State private var answers: [String: String] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 9) {
        Image(
          systemName: action.kind == .userInput ? "questionmark.bubble.fill" : "hand.raised.fill"
        )
        .foregroundStyle(EngDesign.amber)
        Text(action.title)
          .font(.headline)
      }
      Text(action.detail)
        .font(.subheadline)
        .foregroundStyle(Color.white.opacity(0.76))
        .lineLimit(8)
        .textSelection(.enabled)

      if action.kind == .userInput, !action.questions.isEmpty {
        VStack(spacing: 12) {
          ForEach(action.questions) { question in
            PendingQuestionView(
              question: question,
              answer: Binding(
                get: { answers[question.id, default: ""] },
                set: { answers[question.id] = $0 }
              )
            )
          }
          Button {
            store.answerUserInput(requestID: action.id, answers: answers)
          } label: {
            Text("Send answer")
              .font(.subheadline.weight(.bold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
              .background(EngDesign.accent, in: RoundedRectangle(cornerRadius: 13))
          }
          .buttonStyle(.plain)
          .disabled(!allQuestionsAnswered)
          .opacity(allQuestionsAnswered ? 1 : 0.45)
        }
      } else if action.options.isEmpty {
        Text("Answer this request from the Mac session.")
          .font(.caption)
          .foregroundStyle(EngDesign.muted)
      } else {
        VStack(spacing: 8) {
          ForEach(action.options) { option in
            Button {
              answer(option)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(option.label).font(.subheadline.weight(.semibold))
                  if let detail = option.detail {
                    Text(detail).font(.caption).foregroundStyle(EngDesign.muted)
                  }
                }
                Spacer()
                Image(systemName: "chevron.right")
              }
              .padding(12)
              .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .padding(16)
    .background(EngDesign.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))
    .overlay { RoundedRectangle(cornerRadius: 22).stroke(EngDesign.amber.opacity(0.32)) }
  }

  private func answer(_ option: PendingActionOption) {
    if let decision = ApprovalDecision(rawValue: option.id) {
      store.answerApproval(requestID: action.id, decision: decision)
    }
  }

  private var allQuestionsAnswered: Bool {
    !action.questions.isEmpty
      && action.questions.allSatisfy {
        !(answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
  }
}

private struct PendingQuestionView: View {
  let question: PendingQuestion
  @Binding var answer: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(question.prompt)
        .font(.subheadline.weight(.semibold))
      if question.options.isEmpty {
        TextField("Your answer", text: $answer, axis: .vertical)
          .lineLimit(1...4)
          .padding(11)
          .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
      } else {
        ForEach(question.options) { option in
          Button {
            answer = option.label
          } label: {
            HStack {
              Image(systemName: answer == option.label ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(answer == option.label ? EngDesign.cyan : EngDesign.muted)
              VStack(alignment: .leading, spacing: 2) {
                Text(option.label).font(.subheadline.weight(.semibold))
                if let detail = option.detail {
                  Text(detail).font(.caption).foregroundStyle(EngDesign.muted)
                }
              }
              Spacer()
            }
            .padding(11)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
          }
          .buttonStyle(.plain)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
