import EngCore
import SwiftUI

struct ConnectionView: View {
  @EnvironmentObject private var store: BridgeStore
  @FocusState private var codeFocused: Bool

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack {
          Spacer(minLength: 0)
          setupWindow
            .frame(maxWidth: 440)
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
        .padding(10)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .onChange(of: store.isConnected) { _, connected in
      if connected { codeFocused = true }
    }
  }

  private var setupWindow: some View {
    Win95Window(title: "Eng Setup", icon: "macbook.and.iphone") {
      VStack(spacing: 0) {
        HStack(alignment: .top, spacing: 0) {
          wizardSidebar
          VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to Eng")
              .font(Win95Font.heading)
              .foregroundStyle(Win95.text)
            Text(
              "This wizard connects your iPhone to the Codex bridge running on your Mac. "
                + "Eng mirrors active projects, lets you guide live threads, and keeps both "
                + "devices in view."
            )
            .font(Win95Font.body)
            .foregroundStyle(Win95.text)
            .fixedSize(horizontal: false, vertical: true)

            Win95GroupBox(title: "Bridge") {
              VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                  Win95LED(color: statusLEDColor, blinking: !store.isConnected)
                  Text(store.isConnected ? "Mac found" : "Searching nearby…")
                    .font(Win95Font.bold)
                    .foregroundStyle(Win95.text)
                }
                Text(connectionDetail)
                  .font(Win95Font.small)
                  .foregroundStyle(Win95.text)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }

            Win95GroupBox(title: "Replacement phone") {
              VStack(alignment: .leading, spacing: 6) {
                TextField("Optional six-digit code", text: $store.pairingCode)
                  .keyboardType(.numberPad)
                  .textContentType(.oneTimeCode)
                  .font(Win95Font.readout)
                  .multilineTextAlignment(.center)
                  .focused($codeFocused)
                  .onChange(of: store.pairingCode) { _, newValue in
                    store.pairingCode = String(newValue.filter(\.isNumber).prefix(6))
                  }
                  .win95Field()
                Text(
                  "Usually no code is needed. Use the fallback code printed by Eng Bridge "
                    + "only when pairing a different iPhone."
                )
                .font(Win95Font.small)
                .foregroundStyle(Win95.text)
              }
            }
          }
          .padding(.leading, 12)
          .padding(.trailing, 6)
          .padding(.vertical, 6)
        }
        .fixedSize(horizontal: false, vertical: true)

        Rectangle().fill(Win95.shadow).frame(height: 1)
        Rectangle().fill(Win95.light).frame(height: 1)

        HStack(spacing: 6) {
          Image(systemName: "lock.fill")
            .font(.system(size: 11))
            .foregroundStyle(Win95.text)
          Text("Encrypted nearby session. Codex stays on the Mac.")
            .font(Win95Font.small)
            .foregroundStyle(Win95.text)
            .lineLimit(2)
          Spacer(minLength: 8)
          Button("Use Code") {
            store.pair()
          }
          .buttonStyle(Win95ButtonStyle(isDefault: true))
          .disabled(!store.isConnected || store.pairingCode.count != 6)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)

        Win95StatusBar(items: [store.connectionLabel, "Nearby Auto"])
          .padding(.horizontal, 2)
          .padding(.bottom, 2)
      }
    }
  }

  private var wizardSidebar: some View {
    VStack(alignment: .leading) {
      Image(systemName: "chevron.right.2")
        .font(.system(size: 26, weight: .black))
        .foregroundStyle(.white)
      Text("Eng")
        .font(.system(size: 26, weight: .bold))
        .foregroundStyle(.white)
      Text("for iPhone")
        .font(Win95Font.small)
        .foregroundStyle(Win95.lightFace)
      Spacer(minLength: 40)
      Text("v0.1")
        .font(Win95Font.monoSmall)
        .foregroundStyle(Win95.lightFace)
    }
    .padding(10)
    .frame(width: 92)
    .frame(maxHeight: .infinity)
    .background(
      LinearGradient(
        colors: [Win95.titleStart, Win95.titleEnd],
        startPoint: .top,
        endPoint: .bottom
      )
    )
    .padding(.leading, 2)
    .padding(.top, 2)
  }

  private var statusLEDColor: Color {
    switch store.connection {
    case .connected: Win95.ledGreen
    case .connecting, .searching: Win95.ledYellow
    case .disconnected: Win95.ledYellow
    case .failed: Win95.ledRed
    }
  }

  private var connectionDetail: String {
    switch store.connection {
    case .searching: "Start Eng Bridge on your Mac. This iPhone will connect automatically."
    case .connecting(let name): "Opening an encrypted session with \(name)."
    case .connected(let name): "Secure session opened with \(name). Finishing setup automatically."
    case .disconnected: "The bridge dropped. Eng will reconnect automatically."
    case .failed(let reason): reason
    }
  }
}
