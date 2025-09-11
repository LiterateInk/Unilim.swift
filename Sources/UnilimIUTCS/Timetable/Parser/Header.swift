import Foundation

public struct TimetableHeaderContent {
  let weekNumber: Int
  let weekNumberInYear: Int
  let startDate: Date
  let endDate: Date
}

struct TimetableHeader {
  let data: TimetableHeaderContent
  let bounds: RectBounds
}

func getTimetableHeader(_ elements: PDFElements) throws -> TimetableHeader {
  guard
    let headerRect = elements.rects.first(where: { rect in
      rect.color == Color.header.rawValue
    })
  else {
    throw ParseTimetableError.headerRectNotFound
  }

  let bounds = getRectBounds(headerRect)

  let texts = getTextsInRectBounds(texts: elements.texts, bounds: bounds)
  guard let text = texts.first?.text else {
    throw ParseTimetableError.headerTextsNotFound
  }

  let pattern = #"Semaine (\d+) \((\d+)\) : du (\d{2}/\d{2}/\d{4}) au (\d{2}/\d{2}/\d{4})"#
  guard let regex = try? NSRegularExpression(pattern: pattern),
    let match = regex.firstMatch(
      in: text, range: NSRange(text.startIndex..., in: text)),
    match.numberOfRanges == 5
  else {
    throw ParseTimetableError.headerTextUnparseable
  }

  func group(_ idx: Int) -> String {
    let range = match.range(at: idx)
    guard let range = Range(range, in: text) else { return "" }
    return String(text[range])
  }

  let weekNumber = Int(group(1)).unsafelyUnwrapped
  let weekNumberInYear = Int(group(2)).unsafelyUnwrapped
  let startDateString = group(3)
  let endDateString = group(4)

  let formatter = DateFormatter()
  formatter.dateFormat = "dd/MM/yyyy"
  formatter.locale = Locale(identifier: "fr_FR")
  formatter.timeZone = TimeZone(identifier: "Europe/Paris")

  guard let startDate = formatter.date(from: startDateString),
    let endDate = formatter.date(from: endDateString)
  else {
    throw ParseTimetableError.headerTextUnparseable
  }

  return TimetableHeader(
    data: .init(
      weekNumber: weekNumber,
      weekNumberInYear: weekNumberInYear,
      startDate: startDate,
      endDate: endDate
    ),
    bounds: bounds
  )
}
