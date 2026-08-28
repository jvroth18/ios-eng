import SwiftUI

struct ConfigView: View {
  @EnvironmentObject private var store: BridgeStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        connectionGroup
        focusGroup
        hiddenThreadsGroup
        timeGroup
      }
      .padding(6)
    }
    .scrollIndicators(.hidden)
    .background(Win95.face)
  }

  private var connectionGroup: some View {
    Win95GroupBox(title: "Connection route") {
      VStack(alignment: .leading, spacing: 7) {
        ForEach(ConnectionPreference.allCases) { preference in
          Button {
            store.connectionPreference = preference
          } label: {
            HStack(alignment: .top, spacing: 7) {
              Image(
                systemName: store.connectionPreference == preference
                  ? "circle.inset.filled" : "circle"
              )
              .font(.system(size: 13))
              VStack(alignment: .leading, spacing: 2) {
                Text(preference.label)
                  .font(Win95Font.bold)
                Text(preference.detail)
                  .font(Win95Font.small)
                  .fixedSize(horizontal: false, vertical: true)
              }
              Spacer(minLength: 0)
            }
            .foregroundStyle(Win95.text)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }

        Text("Current data route: \(store.activePathLabel)")
          .font(Win95Font.monoSmall)
          .padding(5)
          .frame(maxWidth: .infinity, alignment: .leading)
          .sunkenPaper()

        Text(
          "iOS does not provide an app control that keeps USB-C data enabled while turning charging off. Eng changes only its data route. Use Settings > Battery > Charging to set the iPhone's Charge Limit when available."
        )
        .font(Win95Font.small)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var focusGroup: some View {
    Win95GroupBox(title: "Focus folders") {
      VStack(alignment: .leading, spacing: 8) {
        Win95Checkbox(label: "Only show pinned folders", isOn: $store.focusPinnedOnly)

        if store.projects.isEmpty {
          Text("Connect to the Mac to choose folders.")
            .font(Win95Font.small)
        } else {
          VStack(spacing: 0) {
            ForEach(store.projects) { project in
              HStack(spacing: 7) {
                Image(systemName: "folder.fill")
                  .foregroundStyle(Win95.folder)
                VStack(alignment: .leading, spacing: 1) {
                  Text(project.name)
                    .font(Win95Font.bold)
                    .lineLimit(1)
                  Text(project.repositoryRoot)
                    .font(Win95Font.monoSmall)
                    .lineLimit(1)
                    .truncationMode(.head)
                }
                Spacer(minLength: 5)
                Button(store.isProjectPinned(project.id) ? "Unpin" : "Pin") {
                  store.toggleProjectPin(project.id)
                }
                .buttonStyle(Win95ButtonStyle(compact: true))
              }
              .padding(5)
              if project.id != store.projects.last?.id {
                Rectangle().fill(Win95.shadow).frame(height: 1)
              }
            }
          }
          .sunkenPaper()
        }
      }
    }
  }

  private var timeGroup: some View {
    Win95GroupBox(title: "Thread time") {
      Text(
        "Thread times mean last updated, not time open. A running thread is labeled Live now; the relative time tells you when Eng last received activity."
      )
      .font(Win95Font.small)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var hiddenThreadsGroup: some View {
    Win95GroupBox(title: "Hidden threads (\(store.hiddenThreadCount))") {
      VStack(alignment: .leading, spacing: 8) {
        Text(
          "Hidden threads stay on your Mac and can be restored here. Eng never archives or deletes them."
        )
        .font(Win95Font.small)
        .fixedSize(horizontal: false, vertical: true)

        if store.hiddenThreads.isEmpty {
          Text("No hidden threads.")
            .font(Win95Font.small)
            .foregroundStyle(Win95.shadow)
        } else {
          VStack(spacing: 0) {
            ForEach(store.hiddenThreads) { thread in
              HStack(spacing: 7) {
                Image(systemName: "eye.slash")
                  .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 1) {
                  Text(thread.title)
                    .font(Win95Font.bold)
                    .lineLimit(1)
                  Text(thread.repositoryRoot)
                    .font(Win95Font.monoSmall)
                    .lineLimit(1)
                    .truncationMode(.head)
                }
                Spacer(minLength: 5)
                Button("Unhide") { store.unhideThread(thread.id) }
                  .buttonStyle(Win95ButtonStyle(compact: true))
              }
              .padding(5)
              if thread.id != store.hiddenThreads.last?.id {
                Rectangle().fill(Win95.shadow).frame(height: 1)
              }
            }
          }
          .sunkenPaper()

          Button("Unhide all") { store.unhideAllThreads() }
            .buttonStyle(Win95ButtonStyle(compact: true))
        }
      }
    }
  }
}
