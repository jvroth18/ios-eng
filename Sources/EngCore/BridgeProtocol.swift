import Foundation

public struct BridgeEnvelope: Codable, Equatable, Sendable, Identifiable {
  public static let currentProtocolVersion = 4

  public let id: UUID
  public let sentAt: Date
  public let message: BridgeMessage

  public init(id: UUID = UUID(), sentAt: Date = Date(), message: BridgeMessage) {
    self.id = id
    self.sentAt = sentAt
    self.message = message
  }
}

public enum BridgeMessage: Equatable, Sendable {
  case clientHello(ClientHello)
  case pair(PairRequest)
  case pairResult(PairResult)
  case transportBootstrap(TransportBootstrap)
  case refresh(RefreshRequest)
  case subscribe(ThreadSubscription)
  case workspaceSnapshot(WorkspaceSnapshot)
  case workspacePage(WorkspacePage)
  case threadDetail(ThreadDetail)
  case timelineEvent(TimelineItem)
  case sendMessage(SendMessageRequest)
  case interrupt(InterruptRequest)
  case approvalResponse(ApprovalResponse)
  case userInputResponse(UserInputResponse)
  case analytics(AnalyticsSnapshot)
  case ping(Ping)
  case pong(Pong)
  case error(BridgeError)
}

extension BridgeMessage: Codable {
  private enum CodingKeys: String, CodingKey {
    case kind
    case payload
  }

  private enum Kind: String, Codable {
    case clientHello
    case pair
    case pairResult
    case transportBootstrap
    case refresh
    case subscribe
    case workspaceSnapshot
    case workspacePage
    case threadDetail
    case timelineEvent
    case sendMessage
    case interrupt
    case approvalResponse
    case userInputResponse
    case analytics
    case ping
    case pong
    case error
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .clientHello:
      self = .clientHello(try container.decode(ClientHello.self, forKey: .payload))
    case .pair:
      self = .pair(try container.decode(PairRequest.self, forKey: .payload))
    case .pairResult:
      self = .pairResult(try container.decode(PairResult.self, forKey: .payload))
    case .transportBootstrap:
      self = .transportBootstrap(try container.decode(TransportBootstrap.self, forKey: .payload))
    case .refresh:
      self = .refresh(try container.decode(RefreshRequest.self, forKey: .payload))
    case .subscribe:
      self = .subscribe(try container.decode(ThreadSubscription.self, forKey: .payload))
    case .workspaceSnapshot:
      self = .workspaceSnapshot(try container.decode(WorkspaceSnapshot.self, forKey: .payload))
    case .workspacePage:
      self = .workspacePage(try container.decode(WorkspacePage.self, forKey: .payload))
    case .threadDetail:
      self = .threadDetail(try container.decode(ThreadDetail.self, forKey: .payload))
    case .timelineEvent:
      self = .timelineEvent(try container.decode(TimelineItem.self, forKey: .payload))
    case .sendMessage:
      self = .sendMessage(try container.decode(SendMessageRequest.self, forKey: .payload))
    case .interrupt:
      self = .interrupt(try container.decode(InterruptRequest.self, forKey: .payload))
    case .approvalResponse:
      self = .approvalResponse(try container.decode(ApprovalResponse.self, forKey: .payload))
    case .userInputResponse:
      self = .userInputResponse(try container.decode(UserInputResponse.self, forKey: .payload))
    case .analytics:
      self = .analytics(try container.decode(AnalyticsSnapshot.self, forKey: .payload))
    case .ping:
      self = .ping(try container.decode(Ping.self, forKey: .payload))
    case .pong:
      self = .pong(try container.decode(Pong.self, forKey: .payload))
    case .error:
      self = .error(try container.decode(BridgeError.self, forKey: .payload))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .clientHello(let payload):
      try container.encode(Kind.clientHello, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .pair(let payload):
      try container.encode(Kind.pair, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .pairResult(let payload):
      try container.encode(Kind.pairResult, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .transportBootstrap(let payload):
      try container.encode(Kind.transportBootstrap, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .refresh(let payload):
      try container.encode(Kind.refresh, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .subscribe(let payload):
      try container.encode(Kind.subscribe, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .workspaceSnapshot(let payload):
      try container.encode(Kind.workspaceSnapshot, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .workspacePage(let payload):
      try container.encode(Kind.workspacePage, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .threadDetail(let payload):
      try container.encode(Kind.threadDetail, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .timelineEvent(let payload):
      try container.encode(Kind.timelineEvent, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .sendMessage(let payload):
      try container.encode(Kind.sendMessage, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .interrupt(let payload):
      try container.encode(Kind.interrupt, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .approvalResponse(let payload):
      try container.encode(Kind.approvalResponse, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .userInputResponse(let payload):
      try container.encode(Kind.userInputResponse, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .analytics(let payload):
      try container.encode(Kind.analytics, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .ping(let payload):
      try container.encode(Kind.ping, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .pong(let payload):
      try container.encode(Kind.pong, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    case .error(let payload):
      try container.encode(Kind.error, forKey: .kind)
      try container.encode(payload, forKey: .payload)
    }
  }
}

public struct ClientHello: Codable, Equatable, Sendable {
  public let protocolVersion: Int
  public let deviceID: UUID
  public let deviceName: String
  public let appVersion: String

  public init(
    protocolVersion: Int = BridgeEnvelope.currentProtocolVersion,
    deviceID: UUID,
    deviceName: String,
    appVersion: String
  ) {
    self.protocolVersion = protocolVersion
    self.deviceID = deviceID
    self.deviceName = deviceName
    self.appVersion = appVersion
  }
}

public struct PairRequest: Codable, Equatable, Sendable {
  public let code: String
  public let deviceID: UUID
  public let deviceName: String
  public let identityPublicKey: Data?

  public init(
    code: String,
    deviceID: UUID,
    deviceName: String,
    identityPublicKey: Data? = nil
  ) {
    self.code = code
    self.deviceID = deviceID
    self.deviceName = deviceName
    self.identityPublicKey = identityPublicKey
  }
}

public struct PairResult: Codable, Equatable, Sendable {
  public let accepted: Bool
  public let bridgeName: String
  public let reason: String?

  public init(accepted: Bool, bridgeName: String, reason: String? = nil) {
    self.accepted = accepted
    self.bridgeName = bridgeName
    self.reason = reason
  }
}

public struct RefreshRequest: Codable, Equatable, Sendable {
  public let threadID: String?

  public init(threadID: String? = nil) {
    self.threadID = threadID
  }
}

public struct ThreadSubscription: Codable, Equatable, Sendable {
  public let threadID: String

  public init(threadID: String) {
    self.threadID = threadID
  }
}

public struct SendMessageRequest: Codable, Equatable, Sendable {
  public let clientMessageID: UUID
  public let threadID: String
  public let text: String

  public init(clientMessageID: UUID = UUID(), threadID: String, text: String) {
    self.clientMessageID = clientMessageID
    self.threadID = threadID
    self.text = text
  }

  public var normalizedText: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public struct InterruptRequest: Codable, Equatable, Sendable {
  public let threadID: String
  public let turnID: String

  public init(threadID: String, turnID: String) {
    self.threadID = threadID
    self.turnID = turnID
  }
}

public enum ApprovalDecision: String, Codable, Equatable, Sendable {
  case accept
  case acceptForSession
  case decline
  case cancel
}

public struct ApprovalResponse: Codable, Equatable, Sendable {
  public let requestID: String
  public let decision: ApprovalDecision

  public init(requestID: String, decision: ApprovalDecision) {
    self.requestID = requestID
    self.decision = decision
  }
}

public struct UserInputResponse: Codable, Equatable, Sendable {
  public let requestID: String
  public let answers: [String: String]

  public init(requestID: String, answers: [String: String]) {
    self.requestID = requestID
    self.answers = answers
  }
}

public struct Ping: Codable, Equatable, Sendable {
  public let sequence: UInt64
  public let clientSentAt: Date
  public let probe: Data

  public var payloadBytes: Int { probe.count }

  public init(sequence: UInt64, clientSentAt: Date = Date(), payloadBytes: Int = 0) {
    self.sequence = sequence
    self.clientSentAt = clientSentAt
    probe = Data(repeating: 0xA7, count: min(max(payloadBytes, 0), 65_536))
  }
}

public struct Pong: Codable, Equatable, Sendable {
  public let sequence: UInt64
  public let clientSentAt: Date
  public let bridgeReceivedAt: Date
  public let bridgeSentAt: Date
  public let probe: Data

  public var payloadBytes: Int { probe.count }

  public init(
    sequence: UInt64,
    clientSentAt: Date,
    bridgeReceivedAt: Date,
    bridgeSentAt: Date = Date(),
    payloadBytes: Int
  ) {
    self.sequence = sequence
    self.clientSentAt = clientSentAt
    self.bridgeReceivedAt = bridgeReceivedAt
    self.bridgeSentAt = bridgeSentAt
    probe = Data(repeating: 0xA7, count: min(max(payloadBytes, 0), 65_536))
  }
}

public struct BridgeError: Codable, Equatable, Sendable, Error {
  public let code: String
  public let message: String
  public let recoverable: Bool
  public let relatedMessageID: UUID?

  public init(code: String, message: String, recoverable: Bool, relatedMessageID: UUID? = nil) {
    self.code = code
    self.message = message
    self.recoverable = recoverable
    self.relatedMessageID = relatedMessageID
  }
}
