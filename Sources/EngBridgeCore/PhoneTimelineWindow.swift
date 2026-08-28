import EngCore
import Foundation

enum PhoneTimelineWindow {
  static let maximumEncodedBytes = 48_000

  static func project(
    _ items: [TimelineItem],
    maximumItems: Int = 60,
    maximumBytes: Int = maximumEncodedBytes
  ) -> [TimelineItem] {
    guard maximumItems > 0, maximumBytes > 0 else { return [] }

    var projected: [TimelineItem] = []
    var remainingBytes = maximumBytes
    for item in items.reversed().prefix(maximumItems) {
      let title = prefix(item.title, fittingUTF8Bytes: min(512, remainingBytes))
      let fixedCost =
        420 + item.id.utf8.count + item.threadID.utf8.count
        + (item.turnID?.utf8.count ?? 0) + title.utf8.count
      guard remainingBytes > fixedCost else { break }
      let bodyBudget = min(6_000, remainingBytes - fixedCost)
      let body = prefix(item.body, fittingUTF8Bytes: bodyBudget)
      projected.append(
        TimelineItem(
          id: item.id,
          threadID: item.threadID,
          turnID: item.turnID,
          kind: item.kind,
          state: item.state,
          title: title,
          body: body,
          timestamp: item.timestamp
        ))
      remainingBytes -= fixedCost + body.utf8.count
    }
    return projected.reversed()
  }

  private static func prefix(_ value: String, fittingUTF8Bytes maximumBytes: Int) -> String {
    guard value.utf8.count > maximumBytes else { return value }
    guard maximumBytes > 3 else { return "" }
    var result = ""
    var usedBytes = 0
    for character in value {
      let text = String(character)
      let count = text.utf8.count
      guard usedBytes + count <= maximumBytes - 3 else { break }
      result.append(character)
      usedBytes += count
    }
    return result + "…"
  }
}
