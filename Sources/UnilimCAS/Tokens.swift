public struct Tokens: Codable {
  public let accessToken: String
  public let expiresIn: Int
  public let idToken: String
  public let refreshToken: String
  public let tokenType: String

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case expiresIn = "expires_in"
    case idToken = "id_token"
    case refreshToken = "refresh_token"
    case tokenType = "token_type"
  }
}
