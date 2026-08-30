import Foundation

public struct RelayProvisioningDocument: Codable, Equatable, Sendable {
  public let relayURL: URL
  public let channelID: UUID
  public let token: Data

  public init(relayURL: URL, channelID: UUID, token: Data) {
    self.relayURL = relayURL
    self.channelID = channelID
    self.token = token
  }

  public init(configuration: RemoteRelayConfiguration) {
    relayURL = configuration.baseURL
    channelID = configuration.credential.channelID
    token = configuration.credential.token
  }

  public func configuration() throws -> RemoteRelayConfiguration {
    let credential = try RelayChannelCredential(channelID: channelID, token: token)
    return try RemoteRelayConfiguration(baseURL: relayURL, credential: credential)
  }
}
