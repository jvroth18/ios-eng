import Foundation

enum ThreadMessageBlock: Equatable, Sendable {
  case paragraph(String)
  case heading(level: Int, text: String)
  case bullet(String)
  case numbered(marker: String, text: String)
  case quote(String)
  case code(language: String?, body: String)
}

enum ThreadMessageFormatter {
  static func blocks(from source: String) -> [ThreadMessageBlock] {
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var result: [ThreadMessageBlock] = []
    var paragraph: [String] = []
    var code: [String] = []
    var codeLanguage: String?
    var insideCode = false

    func flushParagraph() {
      guard !paragraph.isEmpty else { return }
      result.append(.paragraph(paragraph.joined(separator: "\n")))
      paragraph.removeAll(keepingCapacity: true)
    }

    for line in lines {
      if line.hasPrefix("```") {
        if insideCode {
          result.append(.code(language: codeLanguage, body: code.joined(separator: "\n")))
          code.removeAll(keepingCapacity: true)
          codeLanguage = nil
          insideCode = false
        } else {
          flushParagraph()
          let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
          codeLanguage = language.isEmpty ? nil : language
          insideCode = true
        }
        continue
      }

      if insideCode {
        code.append(line)
        continue
      }

      if line.trimmingCharacters(in: .whitespaces).isEmpty {
        flushParagraph()
      } else if let heading = heading(from: line) {
        flushParagraph()
        result.append(heading)
      } else if let bullet = bullet(from: line) {
        flushParagraph()
        result.append(.bullet(bullet))
      } else if let numbered = numbered(from: line) {
        flushParagraph()
        result.append(numbered)
      } else if line.hasPrefix("> ") {
        flushParagraph()
        result.append(.quote(String(line.dropFirst(2))))
      } else {
        paragraph.append(line)
      }
    }

    flushParagraph()
    if insideCode {
      result.append(.code(language: codeLanguage, body: code.joined(separator: "\n")))
    }
    return result.isEmpty ? [.paragraph("")] : result
  }

  private static func heading(from line: String) -> ThreadMessageBlock? {
    let hashes = line.prefix { $0 == "#" }.count
    guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
    return .heading(level: hashes, text: String(line.dropFirst(hashes + 1)))
  }

  private static func bullet(from line: String) -> String? {
    for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
      return String(line.dropFirst(marker.count))
    }
    return nil
  }

  private static func numbered(from line: String) -> ThreadMessageBlock? {
    guard let dot = line.firstIndex(of: ".") else { return nil }
    let number = line[..<dot]
    let afterDot = line.index(after: dot)
    guard !number.isEmpty, number.allSatisfy(\.isNumber), afterDot < line.endIndex,
      line[afterDot] == " "
    else { return nil }
    let bodyStart = line.index(after: afterDot)
    return .numbered(marker: "\(number).", text: String(line[bodyStart...]))
  }
}
