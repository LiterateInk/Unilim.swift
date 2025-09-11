import Foundation
import Testing

@testable import PawnilimIUTCS

struct PawnilimIUTCSTests {
  @Test func parsePDFTest() throws {
    let bundle = Bundle.module
    guard let pdfURL = bundle.url(forResource: "A1_S1", withExtension: "pdf") else {
      throw TestError.resourceNotFound
    }

    let timetable = try parseTimetable(from: pdfURL)
    #expect(!timetable.lessons.isEmpty)
  }
}

enum TestError: Error {
  case resourceNotFound
}
