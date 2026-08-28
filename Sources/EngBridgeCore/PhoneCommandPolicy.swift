import EngCore

enum PhoneCommandPolicy {
  static func permits(_ message: BridgeMessage) -> Bool {
    switch message {
    case .refresh, .subscribe, .sendMessage, .interrupt, .approvalResponse,
      .userInputResponse, .analytics, .ping:
      true
    case .clientHello, .pair, .pairResult, .transportBootstrap, .workspaceSnapshot,
      .workspacePage, .threadDetail, .timelineEvent, .pong, .error:
      false
    }
  }
}
