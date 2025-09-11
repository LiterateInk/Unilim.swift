import Foundation

protocol TimetableLessonContent {
  var type: String { get }
  var teacher: String { get }
  var room: String { get }
  var lessonFromReference: String { get }
}

struct TimetableLessonTPContent: TimetableLessonContent {
  let type: String
  let teacher: String
  let lessonFromReference: String
  let room: String
}

struct TimetableLessonTDContent: TimetableLessonContent {
  let type: String
  let teacher: String
  let lessonFromReference: String
  let room: String
}

struct TimetableLessonDSContent: TimetableLessonContent {
  let type: String
  let teacher: String
  let lessonFromReference: String
  let room: String
}

struct TimetableLessonSAEContent: TimetableLessonContent {
  let type: String
  let teacher: String
  let lessonFromReference: String
  let rawLesson: String?
  let room: String
}

struct TimetableLessonOTHERContent {
  let description: String
  let teacher: String
  let room: String
}

struct LessonGroup {
  let main: Int
  let sub: TimetableSubGroup?
}

public struct TimetableLessonCM {
  public struct Content: TimetableLessonContent {
    public let type: String
    public let rawLesson: String
    public let lessonFromReference: String
    public let teacher: String
    public let room: String
  }

  public let type: LessonType = .cm
  public let content: Content
}

public struct TimetableLessonTP {
  let type: LessonType = .tp
  let group: LessonGroup
  let content: TimetableLessonTPContent
}

public struct TimetableLessonTD {
  let type: LessonType = .td
  let group: LessonGroup
  let content: TimetableLessonTDContent
}

public struct TimetableLessonDS {
  let type: LessonType = .ds
  let group: LessonGroup
  let content: TimetableLessonDSContent
}

public struct TimetableLessonSAE {
  let type: LessonType = .sae
  /// When `nil`, it means that it's for every groups.
  let group: LessonGroup?
  let content: TimetableLessonSAEContent
}

public struct TimetableLessonOTHER {
  let type: LessonType = .other
  let content: TimetableLessonOTHERContent
}

public enum TimetableLessonVariant {
  case cm(TimetableLessonCM)
  case tp(TimetableLessonTP)
  case td(TimetableLessonTD)
  case ds(TimetableLessonDS)
  case sae(TimetableLessonSAE)
  case other(TimetableLessonOTHER)
}

public struct TimetableLesson {
  public let startDate: Date
  public let endDate: Date
  public let variant: TimetableLessonVariant
}

func getTimetableLessons(
  _ elements: PDFElements, _ header: TimetableHeader, _ timings: [CGFloat: String],
  _ groups: [String: TimetableGroup]
) -> [TimetableLesson] {
  var lessons: [TimetableLesson] = []

  for rect in elements.rects {
    guard let color = rect.color else { continue }

    guard
      [
        Color.cm.rawValue, Color.td.rawValue, Color.tp.rawValue, Color.ds.rawValue,
        Color.sae.rawValue,
      ].contains(color)
    else { continue }

    let bounds = getRectBounds(rect)
    let containedTexts = getTextsInRectBounds(
      texts: elements.texts,
      bounds: bounds,
      topOffsetY: color == Color.cm.rawValue ? 6 : 4,
      bottomOffsetY: 6,
    )

    var texts = containedTexts.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    let roundedStartY = round(bounds.bottomY, toDecimalPlaces: 4)
    guard let group = groups[String(describing: roundedStartY)] else { continue }

    guard let startTime = timings[bounds.leftX] else { continue }
    guard
      let startDate = createDateFromTime(
        startTime, baseDate: header.data.startDate, weekday: group.day)
    else { continue }

    guard let endTime = timings[bounds.rightX] else { continue }
    guard
      let endDate = createDateFromTime(
        endTime, baseDate: header.data.startDate, weekday: group.day)
    else { continue }

    switch color {
    case Color.cm.rawValue:
      var type = texts.removeFirst()
      let parts = type.split(separator: " -", maxSplits: 1).map(String.init)
      guard parts.count >= 1 else { continue }

      type = removeDuplicateTypes(parts[0])
      let textFromAfterSeparator = parts.count > 1 ? [parts[1]] : []

      guard let room = texts.popLast() else { continue }
      var teacher = texts.popLast()

      if teacher == room {
        teacher = texts.popLast()
      }

      guard let teacher = teacher else { continue }

      let lessonName = (textFromAfterSeparator + texts)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: " ")

      let lesson = TimetableLesson(
        startDate: startDate,
        endDate: endDate,
        variant: .cm(
          .init(
            content: .init(
              type: type,
              rawLesson: lessonName,
              lessonFromReference: BUT_INFO_REF[type]!,
              teacher: teacher,
              room: room
            )
          ))
      )

      lessons.append(lesson)

    case Color.tp.rawValue:
      guard !texts.isEmpty else { continue }

      let parts = texts[0].split(separator: " - ").map(String.init)
      guard parts.count >= 3 else { continue }

      let lesson = TimetableLesson(
        startDate: startDate,
        endDate: endDate,
        variant: .tp(
          TimetableLessonTP(
            group: LessonGroup(main: group.main, sub: group.sub),
            content: TimetableLessonTPContent(
              type: parts[0],
              teacher: parts[1],
              lessonFromReference: BUT_INFO_REF[parts[0]]!,
              room: parts[2]
            )
          ))
      )

      lessons.append(lesson)

    case Color.td.rawValue:
      guard !texts.isEmpty else { continue }

      let parts = texts[0].split(separator: "-").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      guard parts.count >= 3 else { continue }

      let lesson = TimetableLesson(
        startDate: startDate,
        endDate: endDate,
        variant: .td(
          TimetableLessonTD(
            group: LessonGroup(main: group.main, sub: nil),
            content: TimetableLessonTDContent(
              type: parts[0],
              teacher: parts[1],
              lessonFromReference: BUT_INFO_REF[parts[0]]!,
              room: parts[2]
            )
          ))
      )

      lessons.append(lesson)

    case Color.ds.rawValue:
      guard !texts.isEmpty else { continue }

      let parts = texts[0].split(separator: "-").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      guard parts.count >= 3 else { continue }

      let lesson = TimetableLesson(
        startDate: startDate,
        endDate: endDate,
        variant: .ds(
          TimetableLessonDS(
            group: LessonGroup(main: group.main, sub: nil),
            content: TimetableLessonDSContent(
              type: parts[0],
              teacher: parts[1],
              lessonFromReference: BUT_INFO_REF[parts[0]]!,
              room: parts[2]
            )
          ))
      )

      lessons.append(lesson)

    case Color.sae.rawValue:
      let groupsInsideBounds = groups.values.filter { otherGroup in
        let otherRoundedY = round(bounds.bottomY + 2, toDecimalPlaces: 4)
        return otherRoundedY > bounds.bottomY + 2 && otherRoundedY < bounds.topY - 2
      }.count

      let lesson: TimetableLesson

      if texts.count == 1 {
        let parts = texts[0].split(separator: " - ").map(String.init)
        guard parts.count >= 3 else { continue }

        lesson = TimetableLesson(
          startDate: startDate,
          endDate: endDate,
          variant: .sae(
            TimetableLessonSAE(
              group: LessonGroup(
                main: group.main,
                sub: groupsInsideBounds == 0 ? group.sub : nil
              ),
              content: TimetableLessonSAEContent(
                type: parts[0],
                teacher: parts[1],
                lessonFromReference: BUT_INFO_REF[parts[0]]!,
                rawLesson: nil,
                room: parts[2]
              )
            ))
        )
      } else {
        var mutableTexts = texts
        guard let room = mutableTexts.popLast()?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { continue }

        var teacher = mutableTexts.popLast()?.trimmingCharacters(in: .whitespacesAndNewlines)

        if teacher == room {
          teacher = mutableTexts.popLast()?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let teacher = teacher else { continue }

        var description = mutableTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .joined(separator: " ")
        guard !description.isEmpty else { continue }

        let firstWord = description.split(separator: " ").first.map(String.init) ?? ""
        let lessonFromReference = BUT_INFO_REF[firstWord]

        if let lessonFromReference = lessonFromReference {
          // Remove the first word from description
          let descriptionParts = description.split(separator: " - ", maxSplits: 1)
          description = descriptionParts.count > 1 ? String(descriptionParts[1]) : ""

          lesson = TimetableLesson(
            startDate: startDate,
            endDate: endDate,
            variant: .sae(
              TimetableLessonSAE(
                group: nil,
                content: TimetableLessonSAEContent(
                  type: firstWord,
                  teacher: teacher,
                  lessonFromReference: lessonFromReference,
                  rawLesson: description,
                  room: room
                )
              ))
          )
        } else {
          // Unknown lesson type - treat as OTHER
          lesson = TimetableLesson(
            startDate: startDate,
            endDate: endDate,
            variant: .other(
              TimetableLessonOTHER(
                content: TimetableLessonOTHERContent(
                  description: description,
                  teacher: teacher,
                  room: room
                )
              ))
          )
        }
      }

      lessons.append(lesson)

    default:
      continue
    }
  }

  return lessons
}
