import Foundation
import Testing

@testable import PawnilimIUTCS

struct PawnilimIUTCSTests {
  @Test func parsePDFTest() throws {
    let bundle = Bundle.module
    guard let pdfURL = bundle.url(forResource: "A1_S1", withExtension: "pdf") else {
      throw TestError.resourceNotFound
    }

    let elements = try parsePDF(from: pdfURL)
    let timetable = try getTimetable(using: elements)

    #expect(!timetable.lessons.isEmpty)
  }
}

enum TestError: Error {
  case resourceNotFound
}
