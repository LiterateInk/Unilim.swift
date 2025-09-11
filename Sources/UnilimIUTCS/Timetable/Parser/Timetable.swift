import Foundation

public struct Timetable {
  public let header: TimetableHeaderContent
  public let lessons: [TimetableLesson]
}

public func parseTimetable(from url: URL) throws -> Timetable {
  let elements = try parsePDF(from: url)

  let header = try getTimetableHeader(elements)
  let timings = getTimetableTimings(elements, bounds: header.bounds)
  let groups = getTimetableGroups(elements, bounds: header.bounds)
  let lessons = getTimetableLessons(elements, header, timings, groups)

  return .init(header: header.data, lessons: lessons)
}
