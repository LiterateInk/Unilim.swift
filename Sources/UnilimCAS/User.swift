public struct User: Codable {
  public let email: String
  public let familyName: String
  public let givenName: String
  /// Family name and given name combined.
  public let name: String
  /// Username used to authenticate.
  public let sub: String

  enum CodingKeys: String, CodingKey {
    case email
    case familyName = "family_name"
    case givenName = "given_name"
    case name
    case sub
  }
}
