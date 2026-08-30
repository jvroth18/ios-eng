import CryptoKit
import Foundation
import Testing

@testable import EngCore

struct BridgeProtocolTests {
  @Test func remoteRelayConfigurationRequiresHTTPSOutsideLoopback() throws {
    let credential = try RelayChannelCredential.generate()
    #expect(throws: RemoteRelayError.insecureURL) {
      try RemoteRelayConfiguration(
        baseURL: URL(string: "http://relay.example.com")!, credential: credential)
    }
    #expect(
      try RemoteRelayConfiguration(
        baseURL: URL(string: "https://relay.example.com")!, credential: credential
      ).baseURL.scheme == "https")
    #expect(
      try RemoteRelayConfiguration(
        baseURL: URL(string: "http://127.0.0.1:8787")!, credential: credential
      ).baseURL.host == "127.0.0.1")
  }

  @Test func relayProvisioningDocumentRoundTripsAndValidates() throws {
    let configuration = try RemoteRelayConfiguration(
      baseURL: URL(string: "https://relay.example.com")!,
      credential: RelayChannelCredential.generate())
    let encoded = try JSONEncoder().encode(RelayProvisioningDocument(configuration: configuration))
    let decoded = try JSONDecoder().decode(RelayProvisioningDocument.self, from: encoded)
    #expect(try decoded.configuration() == configuration)
  }
  @Test func newlineFramesHandleFragmentedAndCoalescedPackets() throws {
    var frames = NewlineFrameBuffer()
    #expect(try frames.append(Data("one".utf8)) == [])
    #expect(try frames.append(Data("\ntwo\nthree".utf8)) == [Data("one".utf8), Data("two".utf8)])
    #expect(try frames.append(Data("\n".utf8)) == [Data("three".utf8)])
  }

  @Test func secureTransportRoundTripsAndRejectsTampering() throws {
    let now = Date(timeIntervalSince1970: 1_787_000_000)
    let credential = try TransportBootstrap.generate(
      deviceID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
      validFor: 600,
      now: now
    )
    let envelope = BridgeEnvelope(
      id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
      sentAt: now,
      message: .refresh(RefreshRequest(threadID: "thread-secure"))
    )
    let packet = try SecureTransportCodec.seal(envelope, using: credential, now: now)
    #expect(try SecureTransportCodec.open(packet, using: credential, now: now) == envelope)

    var tampered = packet
    tampered[tampered.index(before: tampered.endIndex)] ^= 1
    #expect(throws: (any Error).self) {
      try SecureTransportCodec.open(tampered, using: credential, now: now)
    }
  }

  @Test func directPairingDerivesTheSameAuthenticatedCredentialOnBothDevices() throws {
    let deviceID = UUID()
    let phoneKey = Curve25519.KeyAgreement.PrivateKey()
    let macKey = Curve25519.KeyAgreement.PrivateKey()
    let issuedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let expiresAt = issuedAt.addingTimeInterval(600)

    let phone = try DirectPairingKeyAgreement.bootstrap(
      deviceID: deviceID,
      privateKey: phoneKey,
      remotePublicKey: macKey.publicKey.rawRepresentation,
      issuedAt: issuedAt,
      expiresAt: expiresAt
    )
    let mac = try DirectPairingKeyAgreement.bootstrap(
      deviceID: deviceID,
      privateKey: macKey,
      remotePublicKey: phoneKey.publicKey.rawRepresentation,
      issuedAt: issuedAt,
      expiresAt: expiresAt
    )

    #expect(phone == mac)
  }

  @Test func secureTransportRejectsExpiredAndWrongDeviceCredentials() throws {
    let now = Date(timeIntervalSince1970: 1_787_000_000)
    let first = try TransportBootstrap.generate(deviceID: UUID(), validFor: 10, now: now)
    let second = try TransportBootstrap.generate(deviceID: UUID(), validFor: 10, now: now)
    let envelope = BridgeEnvelope(sentAt: now, message: .refresh(RefreshRequest()))
    let packet = try SecureTransportCodec.seal(envelope, using: first, now: now)

    #expect(throws: SecureTransportError.expiredCredential) {
      try SecureTransportCodec.open(packet, using: first, now: now.addingTimeInterval(11))
    }
    #expect(throws: SecureTransportError.invalidPacket) {
      try SecureTransportCodec.open(packet, using: second, now: now)
    }
  }

  @Test func workspaceSnapshotRoundTripsWithStableEnvelopeShape() throws {
    let now = Date(timeIntervalSince1970: 1_787_000_000)
    let thread = ThreadSummary(
      id: "thread-1",
      title: "Build the phone mirror",
      preview: "Build the phone mirror",
      cwd: "/Users/jordan/Testing/ios-eng",
      repositoryRoot: "/Users/jordan/Testing/ios-eng",
      source: "cli",
      status: .active,
      controlLevel: .live,
      activeTurnID: "turn-1",
      updatedAt: now
    )
    let project = ProjectSummary(
      id: "project-1",
      name: "ios-eng",
      repositoryRoot: thread.repositoryRoot,
      threads: [thread],
      updatedAt: now
    )
    let expected = BridgeEnvelope(
      id: UUID(uuidString: "A9EA0BBA-568D-4C8E-A1F1-2278434F36F3")!,
      sentAt: now,
      message: .workspaceSnapshot(
        WorkspaceSnapshot(bridgeName: "Jordan's MacBook", projects: [project], generatedAt: now)
      )
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(expected)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let message = try #require(object["message"] as? [String: Any])
    #expect(message["kind"] as? String == "workspaceSnapshot")
    #expect(message["payload"] != nil)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(BridgeEnvelope.self, from: data) == expected)
  }

  @Test func everyCommandPayloadRoundTrips() throws {
    let deviceID = UUID(uuidString: "417CB15A-7F55-43C5-B911-39C3BBC9D8A7")!
    let messages: [BridgeMessage] = [
      .clientHello(ClientHello(deviceID: deviceID, deviceName: "iPhone", appVersion: "1.0")),
      .pair(PairRequest(code: "123456", deviceID: deviceID, deviceName: "iPhone")),
      .refresh(RefreshRequest(threadID: "thread-1")),
      .subscribe(ThreadSubscription(threadID: "thread-1")),
      .sendMessage(SendMessageRequest(threadID: "thread-1", text: "Continue")),
      .setThreadModel(SetThreadModelRequest(threadID: "thread-1", model: "gpt-5.6-terra")),
      .interrupt(InterruptRequest(threadID: "thread-1", turnID: "turn-1")),
      .approvalResponse(ApprovalResponse(requestID: "rpc-1", decision: .acceptForSession)),
      .userInputResponse(UserInputResponse(requestID: "rpc-2", answers: ["choice": "yes"])),
      .ping(Ping(sequence: 7, clientSentAt: .distantPast, payloadBytes: 65_536)),
      .error(BridgeError(code: "test", message: "Expected", recoverable: true)),
    ]

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for message in messages {
      let encoded = try encoder.encode(BridgeEnvelope(message: message))
      let decoded = try decoder.decode(BridgeEnvelope.self, from: encoded)
      #expect(decoded.message == message)
    }
  }

  @Test func workspacePagesStaySmallAndReassembleLosslessly() throws {
    let now = Date(timeIntervalSince1970: 1_787_000_000)
    var threads: [ThreadSummary] = []
    for index in 0..<245 {
      let status: ThreadRuntimeStatus = index == 244 ? .active : .notLoaded
      let control: ThreadControlLevel = index == 244 ? .live : .message
      threads.append(
        ThreadSummary(
          id: "thread-\(index)",
          title: "Thread \(index)",
          preview: String(repeating: "diagnostic ", count: 70),
          cwd: "/Users/jordan/Testing/ios-eng",
          repositoryRoot: "/Users/jordan/Testing/ios-eng",
          source: "cli",
          status: status,
          controlLevel: control,
          updatedAt: now.addingTimeInterval(Double(-index))
        )
      )
    }
    let project = ProjectSummary(
      id: "project-1",
      name: "ios-eng",
      repositoryRoot: "/Users/jordan/Testing/ios-eng",
      threads: threads,
      updatedAt: now
    )
    let snapshot = WorkspaceSnapshot(
      bridgeName: "Jordan's MacBook",
      projects: [project],
      generatedAt: now
    )

    let pages = WorkspacePager.pages(for: snapshot, maxThreadsPerPage: 100)
    #expect(pages.count == 3)
    #expect(WorkspacePager.assemble(pages) == snapshot)

    let encoder = JSONEncoder()
    for page in pages {
      let data = try encoder.encode(BridgeEnvelope(message: .workspacePage(page)))
      #expect(data.count < 2 * 1_024 * 1_024)
      let decoded = try JSONDecoder().decode(BridgeEnvelope.self, from: data)
      #expect(decoded.message == BridgeMessage.workspacePage(page))
    }
  }

  @Test func outgoingTextIsNormalizedWithoutMutatingOriginal() {
    let request = SendMessageRequest(threadID: "thread-1", text: "  Continue from the phone. \n")
    #expect(request.text == "  Continue from the phone. \n")
    #expect(request.normalizedText == "Continue from the phone.")
  }

  @Test func linkProbeCarriesRealPayloadBytes() throws {
    let ping = Ping(sequence: 1, payloadBytes: 65_536)
    #expect(ping.payloadBytes == 65_536)
    let data = try JSONEncoder().encode(BridgeEnvelope(message: .ping(ping)))
    #expect(data.count > ping.payloadBytes)
  }
}
