import Foundation
import Testing

@testable import UnilimIUTCS

struct UnilimIUTCSTests {
  @Test func parsePDFTest() throws {
    let bundle = Bundle.module
    guard let pdfURL = bundle.url(forResource: "A1_S1", withExtension: "pdf") else {
      throw TestError.resourceNotFound
    }

    let timetable = try parseTimetable(from: pdfURL)
    #expect(!timetable.lessons.isEmpty)
  }

  @Test func getTimetablesAsyncTest() async throws {
    let entries = try await getTimetables(from: .a1)
    guard let entry = getTimetableFor(week: 1, entries: entries) else {
      throw TestError.directoryListingEmpty
    }

    print(entry)
    print(try parseTimetable(from: entry.url))

    // #expect(!timetables.isEmpty)
    // #expect(timetables.allSatisfy { $0.fromYear == .a1 })
  }
}

enum TestError: Error {
  case resourceNotFound
  case directoryListingEmpty
}
