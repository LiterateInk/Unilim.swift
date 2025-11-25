import Foundation
import SwiftOTP

internal func generate(_ key: String) -> String {
  let totp = SwiftOTP.TOTP(secret: base32DecodeToData(key)!)!
  return totp.generate(time: Date.now)!
}
