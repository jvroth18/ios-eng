import EngCore
import Foundation

public struct PairingGate: Sendable {
  public let code: String
  public let expiresAt: Date
  private var pairedDeviceIDs: Set<UUID>

  public init(
    code: String = PairingGate.generateCode(),
    createdAt: Date = Date(),
    lifetime: TimeInterval = 10 * 60,
    pairedDeviceIDs: Set<UUID> = []
  ) {
    self.code = code
    expiresAt = createdAt.addingTimeInterval(lifetime)
    self.pairedDeviceIDs = pairedDeviceIDs
  }

  public mutating func validate(
    code candidate: String,
    deviceID: UUID,
    bridgeName: String,
    now: Date = Date()
  ) -> PairResult {
    if pairedDeviceIDs.contains(deviceID) {
      return PairResult(accepted: true, bridgeName: bridgeName)
    }
    guard now <= expiresAt else {
      return PairResult(accepted: false, bridgeName: bridgeName, reason: "Pairing code expired")
    }
    guard Self.constantTimeEquals(candidate, code) else {
      return PairResult(
        accepted: false, bridgeName: bridgeName, reason: "Pairing code is incorrect")
    }
    pairedDeviceIDs.insert(deviceID)
    return PairResult(accepted: true, bridgeName: bridgeName)
  }

  public func isPaired(deviceID: UUID) -> Bool {
    pairedDeviceIDs.contains(deviceID)
  }

  public static func generateCode() -> String {
    String(format: "%06d", Int.random(in: 0...999_999))
  }

  private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    var difference = UInt8(left.count ^ right.count)
    for index in 0..<max(left.count, right.count) {
      let l = index < left.count ? left[index] : 0
      let r = index < right.count ? right[index] : 0
      difference |= l ^ r
    }
    return difference == 0
  }
}
