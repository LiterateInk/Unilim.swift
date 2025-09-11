import Foundation

func getTimetableTimings(_ elements: PDFElements, bounds header: RectBounds) -> [CGFloat: String] {
  let fills = elements.rects.filter { rect in
    return rect.color == Color.rulers.rawValue && getRectBounds(rect).topY == header.bottomY
  }

  var timings: [CGFloat: String] = [:]

  for fill in fills {
    let bounds = getRectBounds(fill)
    let texts = getTextsInRectBounds(texts: elements.texts, bounds: bounds)

    guard let text = texts.first?.text else { continue }

    let trimmedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    if !trimmedText.isEmpty {
      timings[fill.x] = trimmedText
    }
  }

  return timings
}
