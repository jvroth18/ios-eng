import EngBridgeCore
import Foundation
import Testing

struct PairingGateTests {
  @Test func rejectsWrongAndExpiredCodesAndTrustsValidatedDevice() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let device = UUID(uuidString: "74388781-59AC-43ED-A247-64CB3BC80C3C")!
    var gate = PairingGate(code: "123456", createdAt: now, lifetime: 60)

    #expect(
      gate.validate(code: "654321", deviceID: device, bridgeName: "Mac", now: now).accepted
        == false
    )
    #expect(
      gate.validate(
        code: "123456", deviceID: UUID(), bridgeName: "Mac", now: now.addingTimeInterval(61)
      )
      .accepted == false
    )
    #expect(gate.validate(code: "123456", deviceID: device, bridgeName: "Mac", now: now).accepted)
    #expect(gate.validate(code: "", deviceID: device, bridgeName: "Mac", now: now).accepted)
  }

  @Test func generatedCodeIsAlwaysSixDigits() {
    for _ in 0..<100 {
      let code = PairingGate.generateCode()
      #expect(code.count == 6)
      #expect(code.allSatisfy { $0.isNumber })
    }
  }

  @Test func automaticallyTrustsOnlyTheFirstDeviceInsideThePairingWindow() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let first = UUID()
    let second = UUID()
    var gate = PairingGate(
      code: "123456",
      createdAt: now,
      lifetime: 60,
      automaticallyTrustFirstDevice: true
    )

    #expect(gate.validate(code: "", deviceID: first, bridgeName: "Mac", now: now).accepted)
    #expect(gate.validate(code: "", deviceID: first, bridgeName: "Mac", now: now).accepted)
    #expect(!gate.validate(code: "", deviceID: second, bridgeName: "Mac", now: now).accepted)
    #expect(
      gate.validate(code: "123456", deviceID: second, bridgeName: "Mac", now: now).accepted)
  }
}
