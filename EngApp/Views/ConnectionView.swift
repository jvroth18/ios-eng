import SwiftUI

struct ConnectionView: View {
  @EnvironmentObject private var store: BridgeStore
  @FocusState private var codeFocused: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        HStack {
          EngMark(size: 46)
          Spacer()
          ConnectionPill()
        }

        Spacer(minLength: 36)

        VStack(alignment: .leading, spacing: 12) {
          Text("YOUR CODEX WORK,\nIN YOUR POCKET")
            .font(.caption.weight(.heavy))
            .tracking(2.5)
            .foregroundStyle(EngDesign.cyan)
          Text("Stay close to the work.")
            .font(.system(size: 42, weight: .bold, design: .rounded))
            .tracking(-1.4)
          Text(
            "Eng mirrors active Mac projects, lets you guide live threads, and keeps both devices in view."
          )
          .font(.body)
          .foregroundStyle(EngDesign.muted)
          .lineSpacing(4)
        }

        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 12) {
            Image(
              systemName: store.isConnected ? "macbook.and.iphone" : "dot.radiowaves.left.and.right"
            )
            .font(.title2)
            .foregroundStyle(EngDesign.accent)
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
              Text(store.isConnected ? "Mac found" : "Searching nearby")
                .font(.headline)
              Text(connectionDetail)
                .font(.caption)
                .foregroundStyle(EngDesign.muted)
            }
          }

          if store.isConnected {
            VStack(alignment: .leading, spacing: 10) {
              Text("PAIRING CODE")
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(EngDesign.muted)
              TextField("000000", text: $store.pairingCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .tracking(7)
                .multilineTextAlignment(.center)
                .padding(.vertical, 15)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
                .focused($codeFocused)
                .onChange(of: store.pairingCode) { _, newValue in
                  store.pairingCode = String(newValue.filter(\.isNumber).prefix(6))
                }

              Button {
                store.pair()
              } label: {
                Text("Connect privately")
                  .font(.headline)
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 15)
                  .background(EngDesign.accent, in: RoundedRectangle(cornerRadius: 16))
              }
              .buttonStyle(.plain)
              .disabled(store.pairingCode.count != 6)
              .opacity(store.pairingCode.count == 6 ? 1 : 0.5)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
        .glassCard()

        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "lock.shield.fill")
            .foregroundStyle(EngDesign.mint)
          Text(
            "Nearby Auto uses encrypted Bluetooth or Wi-Fi without exposing Codex credentials. The App Server stays on Mac loopback."
          )
          .font(.caption)
          .foregroundStyle(EngDesign.muted)
          .lineSpacing(3)
        }
      }
      .padding(.horizontal, 22)
      .padding(.vertical, 18)
      .frame(maxWidth: 620)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .animation(.snappy, value: store.isConnected)
    .onChange(of: store.isConnected) { _, connected in
      if connected { codeFocused = true }
    }
  }

  private var connectionDetail: String {
    switch store.connection {
    case .searching: "Start Eng Bridge on your Mac to connect."
    case .connecting(let name): "Opening an encrypted session with \(name)."
    case .connected(let name): "Enter the six digits shown by \(name)."
    case .disconnected: "The bridge dropped. Eng will reconnect automatically."
    case .failed(let reason): reason
    }
  }
}

struct EngMark: View {
  let size: CGFloat

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        .fill(EngDesign.accent)
      Image(systemName: "chevron.right.2")
        .font(.system(size: size * 0.34, weight: .black, design: .rounded))
        .foregroundStyle(.white)
    }
    .frame(width: size, height: size)
    .shadow(color: EngDesign.violet.opacity(0.35), radius: 18, y: 8)
  }
}
