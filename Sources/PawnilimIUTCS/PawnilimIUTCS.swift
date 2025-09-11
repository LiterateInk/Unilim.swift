import CoreGraphics
import Foundation

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
