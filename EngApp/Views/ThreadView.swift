import EngCore
import SwiftUI

struct ThreadView: View {
  @EnvironmentObject private var store: BridgeStore
  @Environment(\.dismiss) private var dismiss
  let thread: ThreadSummary

  @State private var draft = ""
  @State private var followsTail = true
  @FocusState private var composerFocused: Bool

  var body: some View {
    ZStack {
      Win95.desktop.ignoresSafeArea()
      Win95Window(title: displayedThread.title, icon: "doc.text.fill", onClose: { dismiss() }) {
        VStack(spacing: 5) {
          toolbar
          if let activity {
            activityBar(activity)
          }
          timeline
          composer
          Win95StatusBar(items: [
            "\(displayedThread.status.presentationLabel)",
            displayedThread.controlLevel.presentationLabel,
            displayedThread.source.uppercased(),
          ])
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
      }
      .padding(6)
    }
    .toolbar(.hidden, for: .navigationBar)
    .navigationBarBackButtonHidden(true)
    .task(id: thread.id) { store.subscribe(to: thread) }
    .onDisappear { store.closeThread(threadID: thread.id) }
  }

  private var displayedDetail: ThreadDetail? {
    guard store.threadDetail?.thread.id == thread.id else { return nil }
    return store.threadDetail
  }

  private var displayedThread: ThreadSummary { displayedDetail?.thread ?? thread }

  private var activity: ThreadActivityPresentation? {
    ThreadActivityPresentation.current(
      thread: displayedThread,
      timeline: displayedDetail?.timeline ?? [],
      pendingActions: displayedDetail?.pendingActions ?? [],
      isSending: store.isSending
    )
  }

  /// Changes whenever the visible tail of the conversation changes, including body
  /// growth of a streaming item that keeps its id.
  private var tailSignature: String {
    let timeline = displayedDetail?.timeline ?? []
    let pending = displayedDetail?.pendingActions.count ?? 0
    return "\(timeline.count):\(timeline.last?.body.count ?? 0):\(pending)"
  }

  private var toolbar: some View {
    HStack(spacing: 6) {
      Button {
        dismiss()
      } label: {
        Label("Back", systemImage: "arrowshape.left.fill")
      }
      .buttonStyle(Win95ButtonStyle(compact: true))

      if let turnID = displayedThread.activeTurnID,
        displayedThread.controlLevel == .live || displayedThread.controlLevel == .observe
      {
        Button {
          store.interrupt(threadID: displayedThread.id, turnID: turnID)
        } label: {
          Label("Stop", systemImage: "stop.fill")
        }
        .buttonStyle(Win95ButtonStyle(compact: true))
        .accessibilityLabel("Interrupt current turn")
      }

      Spacer(minLength: 4)

      HStack(spacing: 6) {
        Win95LED(
          color: displayedThread.status.ledColor,
          blinking: false
        )
        Text(displayedThread.status.presentationLabel)
          .font(Win95Font.small)
          .foregroundStyle(Win95.text)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .bevel(.status)
    }
  }

  private func activityBar(_ activity: ThreadActivityPresentation) -> some View {
    HStack(spacing: 7) {
      Win95LED(
        color: activity.isActive ? Win95.ledGreen : Win95.warning,
        blinking: activity.isActive
      )
      Image(systemName: activity.symbol)
        .font(.system(size: 12, weight: .semibold))
      Text(activity.title)
        .font(Win95Font.bold)
      if let detail = activity.detail {
        Text(detail)
          .font(Win95Font.small)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .foregroundStyle(Win95.text)
    .padding(.horizontal, 7)
    .frame(minHeight: 27)
    .bevel(.status)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      [activity.title, activity.detail].compactMap { $0 }.joined(separator: ": ")
    )
  }

  private var timeline: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          if let detail = displayedDetail {
            ForEach(detail.pendingActions) { action in
              PendingActionDialog(action: action)
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
            HStack(spacing: 8) {
              Image(systemName: "hourglass")
              Text("Loading thread…")
            }
            .font(Win95Font.body)
            .foregroundStyle(Win95.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
          }
          Color.clear.frame(height: 1).id("thread-end")
        }
        .padding(6)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
      .onScrollGeometryChange(for: Bool.self) { geometry in
        geometry.contentOffset.y + geometry.containerSize.height
          >= geometry.contentSize.height - 48
      } action: { _, nearTail in
        followsTail = nearTail
      }
      .onChange(of: tailSignature) { _, _ in
        // Only follow new content when the reader is already at the tail, so scrolling
        // up to read history is not yanked back by a streaming turn.
        guard followsTail else { return }
        proxy.scrollTo("thread-end", anchor: .bottom)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .sunkenPaper()
  }

  private var emptyTimeline: some View {
    VStack(spacing: 8) {
      Image(systemName: "text.bubble")
        .font(.system(size: 26))
        .foregroundStyle(Win95.shadow)
      Text("This thread has no visible messages yet.")
        .font(Win95Font.small)
        .foregroundStyle(Win95.text)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 6) {
      TextField("Type a message to Codex", text: $draft, axis: .vertical)
        .lineLimit(1...5)
        .focused($composerFocused)
        .win95Field()

      Button(sendLabel) {
        let message = draft
        draft = ""
        composerFocused = false
        store.sendMessage(message, to: displayedThread.id)
      }
      .buttonStyle(Win95ButtonStyle(isDefault: true))
      .disabled(!canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  private var canSend: Bool {
    (displayedThread.controlLevel == .live || displayedThread.controlLevel == .observe)
      && !store.isSending
  }

  private var sendLabel: String {
    if store.isSending { return "Sending…" }
    if displayedThread.controlLevel == .observe { return "Queue" }
    return displayedThread.activeTurnID == nil ? "Send" : "Steer"
  }

}

private struct TimelineRow: View {
  let item: TimelineItem

  var body: some View {
    switch item.kind {
    case .user, .assistant:
      MessageLine(item: item)
    case .reasoning, .plan, .command, .fileChange, .tool, .approval, .system, .error:
      ActivityRow(item: item)
    }
  }
}

private struct MessageLine: View {
  let item: TimelineItem

  private var isUser: Bool { item.kind == .user }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(messageAuthor)
          .font(Win95Font.bold)
        Text(item.timestamp.formatted(date: .omitted, time: .shortened))
          .font(Win95Font.small)
          .opacity(0.7)
        if item.state == .running {
          Text("…")
            .font(Win95Font.bold)
        } else if item.state == .pending {
          Text("Sending…")
            .font(Win95Font.small)
            .opacity(0.8)
        } else if item.state == .failed {
          Text("Failed")
            .font(Win95Font.small)
            .foregroundStyle(Win95.ledRed)
        }
      }
      FormattedMessageBody(text: item.body.isEmpty ? "…" : item.body)
    }
    .foregroundStyle(isUser ? Win95.highlightText : Win95.text)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(isUser ? Win95.highlight : Color.clear)
  }

  private var messageAuthor: String {
    if isUser { return "You" }
    return item.assistantPhase == .commentary ? "Codex update" : "Codex"
  }
}

private struct FormattedMessageBody: View {
  let text: String

  private var blocks: [ThreadMessageBlock] { ThreadMessageFormatter.blocks(from: text) }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        blockView(block)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .textSelection(.enabled)
    .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private func blockView(_ block: ThreadMessageBlock) -> some View {
    switch block {
    case .paragraph(let value):
      inlineMarkdown(value).font(Win95Font.body)
    case .heading(let level, let value):
      inlineMarkdown(value)
        .font(level == 1 ? .system(size: 17, weight: .bold) : Win95Font.bold)
    case .bullet(let value):
      HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text("•").font(Win95Font.bold)
        inlineMarkdown(value).font(Win95Font.body)
      }
    case .numbered(let marker, let value):
      HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text(marker).font(Win95Font.bold)
        inlineMarkdown(value).font(Win95Font.body)
      }
    case .quote(let value):
      HStack(alignment: .top, spacing: 7) {
        Rectangle().fill(Win95.shadow).frame(width: 3)
        inlineMarkdown(value).font(Win95Font.body).italic()
      }
    case .code(_, let value):
      ScrollView(.horizontal) {
        Text(value)
          .font(Win95Font.mono)
          .foregroundStyle(Win95.text)
          .padding(7)
      }
      .scrollIndicators(.hidden)
      .bevel(.sunken)
      .accessibilityLabel("Code block")
    }
  }

  private func inlineMarkdown(_ value: String) -> Text {
    guard
      let attributed = try? AttributedString(
        markdown: value,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    else { return Text(value) }
    return Text(attributed)
  }
}

private struct ActivityRow: View {
  let item: TimelineItem
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        expanded.toggle()
      } label: {
        HStack(spacing: 6) {
          TreeExpander(expanded: expanded)
          Image(systemName: symbol)
            .font(.system(size: 12))
            .foregroundStyle(item.kind == .error ? Win95.ledRed : Win95.text)
            .frame(width: 16)
          Text(item.title)
            .font(Win95Font.body)
            .lineLimit(1)
          Spacer(minLength: 4)
          if item.state == .running {
            Win95LED(color: Win95.ledGreen, blinking: false)
          }
          Text(item.state.rawValue.capitalized)
            .font(Win95Font.small)
            .opacity(0.75)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(Win95RowStyle())

      if expanded, !item.body.isEmpty {
        Text(item.body)
          .font(Win95Font.mono)
          .foregroundStyle(Win95.text)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(6)
          .bevel(.sunken)
          .padding(.leading, 22)
          .padding(.trailing, 6)
      }
    }
  }

  private var symbol: String {
    switch item.kind {
    case .reasoning: "brain"
    case .plan: "list.bullet.clipboard"
    case .command: "terminal"
    case .fileChange: "doc.badge.gearshape"
    case .tool: "wrench.and.screwdriver"
    case .approval: "hand.raised"
    case .error: "xmark.octagon.fill"
    default: "circle"
    }
  }
}

private struct PendingActionDialog: View {
  @EnvironmentObject private var store: BridgeStore
  let action: PendingAction
  @State private var answers: [String: String] = [:]

  var body: some View {
    Win95Window(title: dialogTitle, icon: "hand.raised.fill") {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 10) {
          Image(
            systemName: action.kind == .userInput
              ? "questionmark.circle.fill" : "exclamationmark.triangle.fill"
          )
          .symbolRenderingMode(.palette)
          .foregroundStyle(.black, Win95.warning)
          .font(.system(size: 28))
          VStack(alignment: .leading, spacing: 4) {
            Text(action.title)
              .font(Win95Font.bold)
              .foregroundStyle(Win95.text)
            Text(action.detail)
              .font(Win95Font.body)
              .foregroundStyle(Win95.text)
              .lineLimit(8)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        if action.kind == .userInput, !action.questions.isEmpty {
          ForEach(action.questions) { question in
            PendingQuestionView(
              question: question,
              answer: Binding(
                get: { answers[question.id, default: ""] },
                set: { answers[question.id] = $0 }
              )
            )
          }
          HStack {
            Spacer()
            Button("Send answer") {
              store.answerUserInput(requestID: action.id, answers: answers)
            }
            .buttonStyle(Win95ButtonStyle(isDefault: true))
            .disabled(!allQuestionsAnswered)
          }
        } else if action.options.isEmpty {
          Text("Answer this request from the Mac session.")
            .font(Win95Font.small)
            .foregroundStyle(Win95.text)
        } else {
          VStack(spacing: 6) {
            ForEach(action.options) { option in
              Button {
                answer(option)
              } label: {
                VStack(spacing: 1) {
                  Text(option.label)
                  if let detail = option.detail {
                    Text(detail).font(Win95Font.small)
                  }
                }
                .frame(maxWidth: .infinity)
              }
              .buttonStyle(
                Win95ButtonStyle(isDefault: option.id == ApprovalDecision.accept.rawValue))
            }
          }
        }
      }
      .padding(8)
    }
    .padding(.vertical, 4)
  }

  private var dialogTitle: String {
    switch action.kind {
    case .commandApproval: "Command approval"
    case .fileApproval: "File approval"
    case .permissions: "Permission request"
    case .userInput: "Codex needs input"
    }
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
    Win95GroupBox(title: question.prompt) {
      if question.options.isEmpty {
        TextField("Your answer", text: $answer, axis: .vertical)
          .lineLimit(1...4)
          .win95Field()
      } else {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(question.options) { option in
            Button {
              answer = option.label
            } label: {
              HStack(alignment: .top, spacing: 6) {
                Image(systemName: answer == option.label ? "smallcircle.filled.circle" : "circle")
                  .font(.system(size: 12))
                  .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                  Text(option.label).font(Win95Font.body)
                  if let detail = option.detail {
                    Text(detail).font(Win95Font.small).opacity(0.75)
                  }
                }
                Spacer()
              }
              .foregroundStyle(Win95.text)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}
