import EngCore
import SwiftUI

enum EngDesign {
  static let canvas = Color(red: 0.035, green: 0.047, blue: 0.082)
  static let raised = Color.white.opacity(0.065)
  static let border = Color.white.opacity(0.105)
  static let muted = Color.white.opacity(0.58)
  static let cyan = Color(red: 0.30, green: 0.84, blue: 0.98)
  static let violet = Color(red: 0.58, green: 0.43, blue: 0.98)
  static let mint = Color(red: 0.37, green: 0.91, blue: 0.70)
  static let amber = Color(red: 1.0, green: 0.72, blue: 0.29)
  static let coral = Color(red: 1.0, green: 0.40, blue: 0.45)
  static let accent = LinearGradient(
    colors: [cyan, violet],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
}

struct EngCanvas: View {
  var body: some View {
    ZStack {
      EngDesign.canvas
      Circle()
        .fill(EngDesign.violet.opacity(0.14))
        .frame(width: 360, height: 360)
        .blur(radius: 90)
        .offset(x: 170, y: -310)
      Circle()
        .fill(EngDesign.cyan.opacity(0.10))
        .frame(width: 320, height: 320)
        .blur(radius: 100)
        .offset(x: -190, y: 330)
    }
    .ignoresSafeArea()
  }
}

struct GlassCardModifier: ViewModifier {
  var padding: CGFloat = 18

  func body(content: Content) -> some View {
    content
      .padding(padding)
      .background(EngDesign.raised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .stroke(EngDesign.border, lineWidth: 1)
      }
  }
}

extension View {
  func glassCard(padding: CGFloat = 18) -> some View {
    modifier(GlassCardModifier(padding: padding))
  }
}

struct StatusDot: View {
  let color: Color
  var pulsing = false

  @State private var isExpanded = false

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 8, height: 8)
      .overlay {
        if pulsing {
          Circle()
            .stroke(color.opacity(0.45), lineWidth: 2)
            .scaleEffect(isExpanded ? 2.2 : 1)
            .opacity(isExpanded ? 0 : 1)
        }
      }
      .onAppear {
        guard pulsing else { return }
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
          isExpanded = true
        }
      }
  }
}

struct EngSectionHeader: View {
  let eyebrow: String
  let title: String
  var trailing: String?

  var body: some View {
    HStack(alignment: .lastTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        Text(eyebrow.uppercased())
          .font(.caption2.weight(.bold))
          .tracking(1.8)
          .foregroundStyle(EngDesign.cyan)
        Text(title)
          .font(.title2.weight(.semibold))
      }
      Spacer()
      if let trailing {
        Text(trailing)
          .font(.caption.monospacedDigit())
          .foregroundStyle(EngDesign.muted)
      }
    }
  }
}

extension ThreadRuntimeStatus {
  var presentationLabel: String {
    switch self {
    case .active: "Working"
    case .waiting: "Needs you"
    case .idle: "Ready"
    case .notLoaded: "Saved"
    case .systemError: "Error"
    }
  }

  var presentationColor: Color {
    switch self {
    case .active: EngDesign.cyan
    case .waiting: EngDesign.amber
    case .idle: EngDesign.mint
    case .notLoaded: EngDesign.muted
    case .systemError: EngDesign.coral
    }
  }
}

extension ThreadControlLevel {
  var presentationLabel: String { rawValue.capitalized }

  var presentationSymbol: String {
    switch self {
    case .observe: "eye"
    case .message: "arrow.up.message"
    case .live: "bolt.horizontal.circle.fill"
    }
  }
}
