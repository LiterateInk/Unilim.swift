import Foundation

/// Get timetable entries for a given study year.
/// We do this by reading entries in the directory listing from the endpoint.
public func getTimetables(from year: TimetableYear) async throws -> [OnlineTimetableFileEntry] {
  let url = "\(timetableDirectoryListing)/\(year.rawValue)"
  guard let url = URL(string: url) else {
    throw URLError(.badURL)
  }

  // Request the directory listing and read as raw HTML.
  let (data, _) = try await URLSession.shared.data(from: url)
  guard let html = String(data: data, encoding: .utf8) else {
    throw URLError(.cannotDecodeContentData)
  }

  // Match the file name and the date from the listing.
  let pattern =
    #"<td><a href=\"(A[123]_S\d+\.pdf)\">.*?<\/a><\/td><td align=\"right\">(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\s<\/td>"#
  let regex = try NSRegularExpression(pattern: pattern, options: [])
  let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
  let matches = regex.matches(in: html, options: [], range: nsrange)

  // Retrieve entries from the listing!
  var entries: [OnlineTimetableFileEntry] = []
  for match in matches {
    guard match.numberOfRanges == 3,
      let fileNameRange = Range(match.range(at: 1), in: html),
      let dateRange = Range(match.range(at: 2), in: html)
    else {
      continue
    }
    let fileName = String(html[fileNameRange])
    let rawDate = String(html[dateRange])
    entries.append(OnlineTimetableFileEntry(fileName: fileName, date: rawDate, fromYear: year))
  }

  // Sort them by date, since `OnlineTimetableFileEntry` is implementing the `Comparable` protocol.
  return entries.sorted()
}

// let elements = try parsePDF(from: URL(fileURLWithPath: path))
// let timetable = try getTimetable(using: elements)

// print("Parsed timetable with \(timetable.lessons.count) lessons")
// print("Week \(timetable.header.weekNumber) (\(timetable.header.weekNumberInYear))")

// // Print first few lessons as examples
// for (index, lesson) in timetable.lessons.enumerated() {
//   print("\nLesson \(index + 1):")
//   let formatter = DateFormatter()
//   formatter.dateFormat = "HH:mm dd/MM/yyyy"
//   print(
//     "  Time: \(formatter.string(from: lesson.startDate)) - \(formatter.string(from: lesson.endDate))"
//   )

//   switch lesson.variant {
//   case .cm(let cm):
//     print("  Type: CM")
//     print("  Subject: \(cm.content.type)")
//     print("  Teacher: \(cm.content.teacher)")
//     print("  Room: \(cm.content.room)")
//     print("  Lesson: \(cm.content.lessonFromReference)")
//   case .tp(let tp):
//     print("  Type: TP")
//     print("  Subject: \(tp.content.type)")
//     print("  Teacher: \(tp.content.teacher)")
//     print("  Room: \(tp.content.room)")
//     print("  Group: G\(tp.group.main)\(tp.group.sub == .a ? "A" : "B")")
//     print("  Lesson: \(tp.content.lessonFromReference)")
//   case .td(let td):
//     print("  Type: TD")
//     print("  Subject: \(td.content.type)")
//     print("  Teacher: \(td.content.teacher)")
//     print("  Room: \(td.content.room)")
//     print("  Group: G\(td.group.main)")
//     print("  Lesson: \(td.content.lessonFromReference)")
//   case .ds(let ds):
//     print("  Type: DS")
//     print("  Subject: \(ds.content.type)")
//     print("  Teacher: \(ds.content.teacher)")
//     print("  Room: \(ds.content.room)")
//     print("  Group: G\(ds.group.main)")
//     print("  Lesson: \(ds.content.lessonFromReference)")
//   case .sae(let sae):
//     print("  Type: SAE")
//     print("  Subject: \(sae.content.type)")
//     print("  Teacher: \(sae.content.teacher)")
//     print("  Room: \(sae.content.room)")
//     print("  Lesson: \(sae.content.lessonFromReference)")
//     if let group = sae.group {
//       if let sub = group.sub {
//         print("  Group: G\(group.main)\(sub == .a ? "A" : "B")")
//       } else {
//         print("  Group: G\(group.main)")
//       }
//     } else {
//       print("  Group: All groups")
//     }
//   case .other(let other):
//     print("  Type: OTHER")
//     print("  Description: \(other.content.description)")
//     print("  Teacher: \(other.content.teacher)")
//     print("  Room: \(other.content.room)")
//   }
// }
