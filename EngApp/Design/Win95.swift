import EngCore
import SwiftUI

// MARK: - Palette and type

/// Classic Windows 95/98 system colors plus a few hardware-style accents (LEDs and
/// green-phosphor monitor readouts). Every screen is built from these tokens; there
/// are no rounded corners, blurs, or shadows anywhere in the app.
enum Win95 {
  static let desktop = Color(red: 0.0, green: 0.502, blue: 0.502)
  static let face = Color(red: 0.753, green: 0.753, blue: 0.753)
  static let lightFace = Color(red: 0.875, green: 0.875, blue: 0.875)
  static let light = Color.white
  static let shadow = Color(red: 0.502, green: 0.502, blue: 0.502)
  static let darkShadow = Color.black
  static let paper = Color.white
  static let text = Color.black
  static let disabledText = shadow
  static let titleStart = Color(red: 0.0, green: 0.0, blue: 0.502)
  static let titleEnd = Color(red: 0.063, green: 0.518, blue: 0.816)
  static let inactiveTitleStart = Color(red: 0.502, green: 0.502, blue: 0.502)
  static let inactiveTitleEnd = Color(red: 0.71, green: 0.71, blue: 0.71)
  static let highlight = titleStart
  static let highlightText = Color.white
  static let warning = Color(red: 1.0, green: 0.85, blue: 0.0)
  static let folder = Color(red: 1.0, green: 0.8, blue: 0.2)
  static let ledGreen = Color(red: 0.0, green: 1.0, blue: 0.0)
  static let ledYellow = Color(red: 1.0, green: 1.0, blue: 0.0)
  static let ledRed = Color(red: 1.0, green: 0.0, blue: 0.0)
  static let ledBlue = Color(red: 0.2, green: 0.6, blue: 1.0)
  static let ledOff = Color(red: 0.3, green: 0.3, blue: 0.3)
  static let monitorBackground = Color.black
  static let monitorGrid = Color(red: 0.0, green: 0.5, blue: 0.0)
  static let monitorTrace = Color(red: 0.0, green: 1.0, blue: 0.0)
}

enum Win95Font {
  static let body = Font.system(size: 13)
  static let bold = Font.system(size: 13, weight: .bold)
  static let small = Font.system(size: 11)
  static let smallBold = Font.system(size: 11, weight: .bold)
  static let title = Font.system(size: 13, weight: .bold)
  static let heading = Font.system(size: 18, weight: .bold)
  static let mono = Font.system(size: 12, design: .monospaced)
  static let monoBold = Font.system(size: 12, weight: .bold, design: .monospaced)
  static let monoSmall = Font.system(size: 11, design: .monospaced)
  static let readout = Font.system(size: 22, weight: .bold, design: .monospaced)
}

// MARK: - Bevels

enum BevelStyle {
  case raised
  case pressed
  case sunken
  case window
  case status
  case etched

  fileprivate var edges: (outerTL: Color, outerBR: Color, innerTL: Color?, innerBR: Color?) {
    switch self {
    case .raised: (Win95.light, Win95.darkShadow, Win95.lightFace, Win95.shadow)
    case .pressed: (Win95.darkShadow, Win95.light, Win95.shadow, Win95.lightFace)
    case .sunken: (Win95.shadow, Win95.light, Win95.darkShadow, Win95.lightFace)
    case .window: (Win95.lightFace, Win95.darkShadow, Win95.light, Win95.shadow)
    case .status: (Win95.shadow, Win95.light, nil, nil)
    case .etched: (Win95.shadow, Win95.light, Win95.light, Win95.shadow)
    }
  }
}

/// Draws the two-pixel 3D edge Windows used on every control. Overlay it on a view
/// that already has an opaque background.
struct BevelBorder: View {
  let style: BevelStyle

  var body: some View {
    Canvas { context, size in
      let edges = style.edges
      let w = size.width
      let h = size.height
      func fill(_ rect: CGRect, _ color: Color) {
        context.fill(Path(rect), with: .color(color))
      }
      fill(CGRect(x: 0, y: 0, width: w, height: 1), edges.outerTL)
      fill(CGRect(x: 0, y: 0, width: 1, height: h), edges.outerTL)
      fill(CGRect(x: 0, y: h - 1, width: w, height: 1), edges.outerBR)
      fill(CGRect(x: w - 1, y: 0, width: 1, height: h), edges.outerBR)
      if let innerTL = edges.innerTL, let innerBR = edges.innerBR {
        fill(CGRect(x: 1, y: 1, width: w - 2, height: 1), innerTL)
        fill(CGRect(x: 1, y: 1, width: 1, height: h - 2), innerTL)
        fill(CGRect(x: 1, y: h - 2, width: w - 2, height: 1), innerBR)
        fill(CGRect(x: w - 2, y: 1, width: 1, height: h - 2), innerBR)
      }
    }
    .allowsHitTesting(false)
  }
}

extension View {
  func bevel(_ style: BevelStyle, fill: Color = Win95.face) -> some View {
    background(fill).overlay(BevelBorder(style: style))
  }

  /// White sunken area used for lists, logs, and text.
  func sunkenPaper() -> some View {
    bevel(.sunken, fill: Win95.paper)
  }

  /// Gray raised panel used for tab pages and toolbars.
  func raisedPanel() -> some View {
    bevel(.raised)
  }

  func win95Field() -> some View {
    modifier(Win95FieldModifier())
  }
}

struct Win95FieldModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .font(Win95Font.body)
      .foregroundStyle(Win95.text)
      .tint(Win95.highlight)
      .textFieldStyle(.plain)
      .padding(.horizontal, 5)
      .padding(.vertical, 5)
      .sunkenPaper()
  }
}

// MARK: - Windows and chrome

struct Win95Window<Content: View>: View {
  let title: String
  var icon: String? = nil
  var active = true
  var onClose: (() -> Void)? = nil
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      Win95TitleBar(title: title, icon: icon, active: active, onClose: onClose)
      content()
        .frame(maxWidth: .infinity)
        .padding(.top, 3)
    }
    .padding(3)
    .bevel(.window)
  }
}

struct Win95TitleBar: View {
  let title: String
  var icon: String? = nil
  var active = true
  var onClose: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 4) {
      if let icon {
        Image(systemName: icon)
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 16)
      }
      Text(title)
        .font(Win95Font.title)
        .foregroundStyle(active ? Color.white : Win95.lightFace)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 8)
      HStack(spacing: 2) {
        TitleButton(symbol: "minus", action: nil)
        TitleButton(symbol: "square", action: nil)
        TitleButton(symbol: "xmark", action: onClose)
      }
    }
    .padding(.leading, 4)
    .padding(.trailing, 2)
    .frame(height: 22)
    .background(
      LinearGradient(
        colors: active
          ? [Win95.titleStart, Win95.titleEnd]
          : [Win95.inactiveTitleStart, Win95.inactiveTitleEnd],
        startPoint: .leading,
        endPoint: .trailing
      )
    )
  }
}

private struct TitleButton: View {
  let symbol: String
  let action: (() -> Void)?

  var body: some View {
    Button {
      action?()
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 8, weight: .black))
        .foregroundStyle(.black)
        .frame(width: 18, height: 16)
        .bevel(.raised)
    }
    .buttonStyle(Win95PressStyle())
    .disabled(action == nil)
    .accessibilityLabel(symbol == "xmark" ? "Close" : symbol)
  }
}

struct Win95StatusBar: View {
  let items: [String]

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Array(items.enumerated()), id: \.offset) { index, item in
        Text(item)
          .font(Win95Font.small)
          .foregroundStyle(Win95.text)
          .lineLimit(1)
          .padding(.horizontal, 5)
          .padding(.vertical, 3)
          .frame(maxWidth: index == 0 ? .infinity : nil, alignment: .leading)
          .bevel(.status)
      }
    }
  }
}

struct Win95GroupBox<Content: View>: View {
  let title: String
  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 10)
      .padding(.top, 14)
      .padding(.bottom, 10)
      .overlay(BevelBorder(style: .etched).padding(.top, 7))
      .overlay(alignment: .topLeading) {
        Text(title)
          .font(Win95Font.body)
          .foregroundStyle(Win95.text)
          .padding(.horizontal, 3)
          .background(Win95.face)
          .padding(.leading, 8)
      }
  }
}

struct Win95Tab<ID: Hashable>: Identifiable {
  let id: ID
  let label: String
}

struct Win95Tabs<ID: Hashable>: View {
  let tabs: [Win95Tab<ID>]
  @Binding var selection: ID

  var body: some View {
    HStack(alignment: .bottom, spacing: 0) {
      ForEach(tabs) { tab in
        let selected = tab.id == selection
        Button {
          selection = tab.id
        } label: {
          Text(tab.label)
            .font(Win95Font.body)
            .foregroundStyle(Win95.text)
            .padding(.horizontal, selected ? 14 : 10)
            .padding(.top, selected ? 5 : 3)
            .padding(.bottom, selected ? 6 : 3)
            .background(Win95.face)
            .overlay(TabEdge())
        }
        .buttonStyle(.plain)
        .zIndex(selected ? 1 : 0)
        .offset(y: selected ? 2 : 0)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 2)
  }
}

private struct TabEdge: View {
  var body: some View {
    Canvas { context, size in
      let w = size.width
      let h = size.height
      func fill(_ rect: CGRect, _ color: Color) {
        context.fill(Path(rect), with: .color(color))
      }
      fill(CGRect(x: 2, y: 0, width: w - 4, height: 1), Win95.light)
      fill(CGRect(x: 1, y: 1, width: 1, height: 1), Win95.light)
      fill(CGRect(x: 0, y: 2, width: 1, height: h - 2), Win95.light)
      fill(CGRect(x: 1, y: 2, width: 1, height: h - 2), Win95.lightFace)
      fill(CGRect(x: w - 2, y: 1, width: 1, height: 1), Win95.darkShadow)
      fill(CGRect(x: w - 1, y: 2, width: 1, height: h - 2), Win95.darkShadow)
      fill(CGRect(x: w - 2, y: 2, width: 1, height: h - 2), Win95.shadow)
    }
    .allowsHitTesting(false)
  }
}

// MARK: - Controls

struct Win95ButtonStyle: ButtonStyle {
  var isDefault = false
  var compact = false
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let pressed = configuration.isPressed
    return configuration.label
      .font(Win95Font.body)
      .lineLimit(1)
      .foregroundStyle(isEnabled ? Win95.text : Win95.disabledText)
      .padding(.horizontal, compact ? 8 : 14)
      .padding(.vertical, compact ? 3 : 5)
      .frame(minWidth: compact ? 0 : 75)
      .offset(x: pressed ? 1 : 0, y: pressed ? 1 : 0)
      .bevel(pressed ? .pressed : .raised)
      .padding(isDefault ? 1 : 0)
      .background(isDefault ? Color.black : Color.clear)
  }
}

/// Bare press feedback for controls that draw their own chrome.
struct Win95PressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
  }
}

/// List-row selection: navy highlight with white text while pressed.
struct Win95RowStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(configuration.isPressed ? Win95.highlightText : Win95.text)
      .background(configuration.isPressed ? Win95.highlight : Color.clear)
  }
}

struct Win95Checkbox: View {
  let label: String
  @Binding var isOn: Bool

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      HStack(spacing: 6) {
        ZStack {
          Rectangle()
            .fill(Win95.paper)
            .frame(width: 13, height: 13)
            .overlay(BevelBorder(style: .sunken))
          if isOn {
            Image(systemName: "checkmark")
              .font(.system(size: 9, weight: .black))
              .foregroundStyle(.black)
          }
        }
        Text(label)
          .font(Win95Font.body)
          .foregroundStyle(Win95.text)
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isOn ? [.isSelected] : [])
  }
}

struct Win95ProgressBar: View {
  let fraction: Double?

  var body: some View {
    GeometryReader { geometry in
      let inner = max(geometry.size.width - 4, 0)
      let block: CGFloat = 8
      let gap: CGFloat = 2
      let count = max(Int((inner + gap) / (block + gap)), 1)
      let clamped = min(max(fraction ?? 0, 0), 1)
      let filled = Int((Double(count) * clamped).rounded())
      HStack(spacing: gap) {
        ForEach(0..<count, id: \.self) { index in
          Rectangle().fill(index < filled ? Win95.highlight : Color.clear)
        }
      }
      .padding(2)
    }
    .frame(height: 16)
    .bevel(.sunken)
  }
}

struct Win95LED: View {
  let color: Color
  var blinking = false
  @State private var lit = true

  var body: some View {
    Rectangle()
      .fill(blinking && !lit ? Win95.ledOff : color)
      .frame(width: 10, height: 10)
      .overlay(BevelBorder(style: .sunken))
      .task(id: blinking) {
        guard blinking else {
          lit = true
          return
        }
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(550))
          lit.toggle()
        }
      }
  }
}

/// Green-phosphor numeric readout on a black sunken panel.
struct Win95Readout: View {
  let value: String
  let label: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value)
        .font(Win95Font.readout)
        .foregroundStyle(Win95.monitorTrace)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .bevel(.sunken, fill: Win95.monitorBackground)
      Text(label)
        .font(Win95Font.small)
        .foregroundStyle(Win95.text)
    }
  }
}

struct Win95MetricRow: View {
  let label: String
  let value: String
  var fraction: Double? = nil
  var detail: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .firstTextBaseline) {
        Text(label).font(Win95Font.body).foregroundStyle(Win95.text)
        Spacer(minLength: 8)
        Text(value).font(Win95Font.monoBold).foregroundStyle(Win95.text).lineLimit(1)
      }
      if let fraction {
        Win95ProgressBar(fraction: fraction)
      }
      if let detail {
        Text(detail)
          .font(Win95Font.small)
          .foregroundStyle(Win95.shadow)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }
}

struct TreeExpander: View {
  let expanded: Bool

  var body: some View {
    ZStack {
      Rectangle()
        .fill(Win95.paper)
        .frame(width: 9, height: 9)
        .overlay(Rectangle().stroke(Win95.shadow, lineWidth: 1))
      Image(systemName: expanded ? "minus" : "plus")
        .font(.system(size: 7, weight: .black))
        .foregroundStyle(.black)
    }
  }
}

struct Win95MessageBox: View {
  let title: String
  let message: String
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.18).ignoresSafeArea()
      Win95Window(title: title, onClose: onDismiss) {
        VStack(spacing: 14) {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
              .symbolRenderingMode(.palette)
              .foregroundStyle(.black, Win95.warning)
              .font(.system(size: 30))
            Text(message)
              .font(Win95Font.body)
              .foregroundStyle(Win95.text)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.top, 8)
          Button("OK", action: onDismiss)
            .buttonStyle(Win95ButtonStyle(isDefault: true))
        }
        .padding(10)
      }
      .frame(width: 300)
    }
  }
}

// MARK: - Presentation of shared model values

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

  var ledColor: Color {
    switch self {
    case .active: Win95.ledGreen
    case .waiting: Win95.ledYellow
    case .idle: Win95.ledGreen
    case .notLoaded: Win95.ledOff
    case .systemError: Win95.ledRed
    }
  }

  var ledBlinks: Bool {
    self == .active || self == .waiting
  }
}

extension ThreadControlLevel {
  var presentationLabel: String {
    switch self {
    case .observe: "Read only"
    case .message: "Available"
    case .live: "Live"
    }
  }

  var presentationSymbol: String {
    switch self {
    case .observe: "eye"
    case .message: "envelope"
    case .live: "bolt.fill"
    }
  }
}
