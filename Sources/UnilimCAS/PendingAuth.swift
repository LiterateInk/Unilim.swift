import Foundation
import Rikka
import SwiftSoup

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct PendingAuth {
  public var isEmailAvailable = false
  public var isTotpAvailable = false
  public var solved: Bool

  /// Extracted hidden fields from received <form> that we'll send back.
  ///
  /// Most of the properties in there are useless,
  /// but for bundle size reasons, we won't filter them out.
  private var fields: [String: String] = [:]
  private var document: Document

  internal init(_ document: Document) throws {
    self.document = document
    let form = try document.select("form")

    self.solved = try form.attr("action") == "/registerbrowser"
    try self.extractFields()

    if !self.solved {
      let buttons = try form.select("button[name=sf]")

      for button in buttons {
        switch try button.attr("value") {
        case "totp":
          self.isTotpAvailable = true
          break
        case "mail":
          self.isEmailAvailable = true
          break
        default:
          continue
        }
      }
    }
  }

  public enum Error: Swift.Error {
    case notSolved
    case noCookie
    case noSecret
  }

  /// Finish authentication sequence.
  ///
  /// This method will call the `registerbrowser` API to enable
  /// persistence and be able to re-authenticate in the future
  /// without having to manually solve the 2FA challenge.
  public mutating func finish() async throws -> CAS {
    if !self.solved { throw Error.notSolved }

    guard let key = self.fields["totpsecret"]?.uppercased() else {
      throw Error.noSecret
    }

    let totp = generate(key)
    self.fields["fg"] = "TOTP_" + totp

    let request = try HttpRequest.Builder(CAS.HOST + "/registerbrowser")
      .setRedirection(.manual)
      .setMethod(.post)
      .setFormUrlEncodedBody(self.fields)
      .build()

    let response = try await send(request)
    let cookies = response.headers.getSetCookie()

    func toKV(_ cookie: String) -> String {
      return String(cookie.split(separator: ";")[0].split(separator: "=")[1])
    }

    guard let lemonldap = cookies.first(where: { $0.hasPrefix(CAS.COOKIE + "=") }),
      let llngconnection = cookies.first(where: { $0.hasPrefix(CAS.PERSIST_COOKIE + "=") })
    else {
      throw Error.noCookie
    }

    return CAS(
      cookie: toKV(lemonldap),
      connection: toKV(llngconnection),
      key: key
    )
  }

  public mutating func sendEmailCode() async throws {
    try await use("mail")
  }

  public mutating func solveWithEmailCode(code: String) async throws {
    try await solve(method: "mail2fcheck", code)
  }

  public mutating func solveWithTotp(totp: String) async throws {
    try await use("totp")
    try await solve(method: "totp2fcheck", totp)
  }

  private mutating func extractFields() throws {
    self.fields = [:]

    for input in try self.document.select("form input[type=hidden]") {
      let key = try input.attr("name")
      let value = try input.attr("value")

      self.fields[key] = value
    }
  }

  private mutating func solve(method: String, _ code: String) async throws {
    self.fields["code"] = code
    self.fields["stayconnected"] = "1"  // in case it is missing.

    let request = try HttpRequest.Builder(CAS.HOST + "/" + method)
      .setMethod(.post)
      .setFormUrlEncodedBody(self.fields)
      .build()

    let response = try await send(request)
    self.document = try response.toHTML()
    try self.extractFields()
    self.solved = true
  }

  private mutating func use(_ choice: String) async throws {
    self.fields["sf"] = choice

    let request = try HttpRequest.Builder(CAS.HOST + "/2fchoice")
      .setMethod(.post)
      .setFormUrlEncodedBody(self.fields)
      .build()

    let response = try await send(request)
    self.document = try response.toHTML()
    try self.extractFields()
  }
}
