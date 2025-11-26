public struct OAuth2 {
  public let identifier: String
  public let callback: String
  public let scopes: [String]

  public init(identifier: String, callback: String, scopes: [String]) {
    self.identifier = identifier
    self.callback = callback
    self.scopes = scopes
  }
}
