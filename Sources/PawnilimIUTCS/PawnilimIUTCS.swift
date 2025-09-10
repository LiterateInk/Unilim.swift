import CoreGraphics
import Foundation

func rgbToHex(r: CGFloat, g: CGFloat, b: CGFloat) -> String {
  let red = Int(r * 255)
  let green = Int(g * 255)
  let blue = Int(b * 255)

  return String(format: "#%02X%02X%02X", red, green, blue)
}

// per-scan mutable graphic state stored via an `UnsafeMutablePointer` passed into callbacks.
struct GraphicsState {
  var textMatrix: (a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, x: CGFloat, y: CGFloat)?
  var fillColor: String?
}

struct TextRecord {
  let x: CGFloat
  let y: CGFloat
  let text: String
}

struct RectRecord {
  let x: CGFloat
  let y: CGFloat
  let w: CGFloat
  let h: CGFloat
  let color: String?
}

struct PDFElements {
  let texts: [TextRecord]
  let rects: [RectRecord]
}

final class PDFParseContext {
  var state = GraphicsState()
  var texts: [TextRecord] = []
  var rects: [RectRecord] = []

  struct WorkItem {
    let content: CGPDFContentStreamRef
    let savedState: GraphicsState
  }

  var worklist: [WorkItem] = []
  var visited: [UInt] = []
  var currentContent: CGPDFContentStreamRef? = nil

  // simple path tracking, only for rectangle detection.
  struct PathSubpath {
    var points: [(CGFloat, CGFloat)] = []
    var closed: Bool = false
  }

  var currentSubpath = PathSubpath()
  var subpaths: [PathSubpath] = []

  init() {
    state = GraphicsState()
    worklist.removeAll(keepingCapacity: true)
    visited.removeAll(keepingCapacity: true)
    currentContent = nil
    pathReset()
  }

  func pathMoveTo(_ x: CGFloat, _ y: CGFloat) {
    if !currentSubpath.points.isEmpty { subpaths.append(currentSubpath) }
    currentSubpath = PathSubpath(points: [(x, y)], closed: false)
  }

  func pathLineTo(_ x: CGFloat, _ y: CGFloat) {
    currentSubpath.points.append((x, y))
  }

  func pathClose() { currentSubpath.closed = true }

  func pathFinishSubpaths() {
    if !currentSubpath.points.isEmpty { subpaths.append(currentSubpath) }
    currentSubpath = PathSubpath()
  }

  func pathReset() {
    currentSubpath = PathSubpath()
    subpaths.removeAll(keepingCapacity: true)
  }

  func captureFilledRectangles(fillColor: String?) {
    pathFinishSubpaths()
    for sp in subpaths {
      guard sp.points.count >= 4 else { continue }
      // Axis-aligned rectangle heuristic: exactly 2 distinct X and 2 distinct Y values
      let xs = Set(sp.points.map { $0.0 })
      let ys = Set(sp.points.map { $0.1 })
      if xs.count == 2 && ys.count == 2 {
        let minX = xs.min()!
        let maxX = xs.max()!
        let minY = ys.min()!
        let maxY = ys.max()!
        let w = maxX - minX
        let h = maxY - minY
        if w >= 0 && h >= 0 {
          rects.append(
            RectRecord(x: minX, y: minY, w: w, h: h, color: fillColor))
        }
      }
    }
    pathReset()
  }
}

enum PDFError: Error {
  case documentCreationFailed
  case missingFirstPage
  case scanFailed
}

func decode(from data: Data) -> String? {
  let encodings: [String.Encoding] = [.utf8, .isoLatin1, .windowsCP1252, .ascii]
  for encoding in encodings {
    if let str = String(data: data, encoding: encoding) {
      return str
    }
  }

  return nil
}

/// Parses a PDF at the given URL.
///
/// - Parameter url: The location of the PDF file to parse.
/// - Throws:
///   - `PDFError.documentCreationFailed` if the PDF cannot be opened.
///   - `PDFError.missingFirstPage` if the first page is not available.
///   - `PDFError.scanFailed` if the scan of the page content failed.
/// - Returns: A `PDFElements` populated with rectangles and texts
///            from the PDF's first page.
func parsePDF(from url: URL) throws -> PDFElements {
  guard let doc = CGPDFDocument(url as CFURL) else {
    throw PDFError.documentCreationFailed
  }

  let ctx = PDFParseContext()

  guard let page = doc.page(at: 1) else {
    throw PDFError.missingFirstPage
  }

  let content = CGPDFContentStreamCreateWithPage(page)
  let table = CGPDFOperatorTableCreate()!

  // rectangles ("re")
  CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()

    var x: CGPDFReal = 0
    var y: CGPDFReal = 0
    var w: CGPDFReal = 0
    var h: CGPDFReal = 0

    CGPDFScannerPopNumber(scanner, &h)
    CGPDFScannerPopNumber(scanner, &w)
    CGPDFScannerPopNumber(scanner, &y)
    CGPDFScannerPopNumber(scanner, &x)
    let rectColor = ctx.state.fillColor
    ctx.rects.append(
      RectRecord(
        x: CGFloat(x), y: CGFloat(y), w: CGFloat(w), h: CGFloat(h),
        color: rectColor))

    // also push into path model for consistency
    ctx.pathMoveTo(CGFloat(x), CGFloat(y))
    ctx.pathLineTo(CGFloat(x + w), CGFloat(y))
    ctx.pathLineTo(CGFloat(x + w), CGFloat(y + h))
    ctx.pathLineTo(CGFloat(x), CGFloat(y + h))
    ctx.pathClose()
  }

  // path move ("m")
  CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    var y: CGPDFReal = 0
    var x: CGPDFReal = 0
    CGPDFScannerPopNumber(scanner, &y)
    CGPDFScannerPopNumber(scanner, &x)
    ctx.pathMoveTo(CGFloat(x), CGFloat(y))
  }

  // path line ("l")
  CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    var y: CGPDFReal = 0
    var x: CGPDFReal = 0
    CGPDFScannerPopNumber(scanner, &y)
    CGPDFScannerPopNumber(scanner, &x)
    ctx.pathLineTo(CGFloat(x), CGFloat(y))
  }

  // close path ("h")
  CGPDFOperatorTableSetCallback(table, "h") { _, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    ctx.pathClose()
  }

  // painting operators that fill (capture rectangles)
  let fillOps = ["f", "F", "f*", "B", "B*", "b", "b*"]
  for op in fillOps {
    CGPDFOperatorTableSetCallback(table, op) { _, info in
      guard let info else { return }
      let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
      ctx.captureFilledRectangles(fillColor: ctx.state.fillColor)
    }
  }

  // end path without fill/stroke ("n") – just reset
  CGPDFOperatorTableSetCallback(table, "n") { _, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    ctx.pathReset()
  }

  // text matrix ("Tm")
  CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    var a: CGPDFReal = 0
    var b: CGPDFReal = 0
    var c: CGPDFReal = 0
    var d: CGPDFReal = 0
    var x: CGPDFReal = 0
    var y: CGPDFReal = 0
    CGPDFScannerPopNumber(scanner, &y)
    CGPDFScannerPopNumber(scanner, &x)
    CGPDFScannerPopNumber(scanner, &d)
    CGPDFScannerPopNumber(scanner, &c)
    CGPDFScannerPopNumber(scanner, &b)
    CGPDFScannerPopNumber(scanner, &a)
    ctx.state.textMatrix = (
      CGFloat(a), CGFloat(b), CGFloat(c), CGFloat(d), CGFloat(x), CGFloat(y)
    )
  }

  // fill color ("rg")
  CGPDFOperatorTableSetCallback(table, "rg") { scanner, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    var r: CGPDFReal = 0
    var g: CGPDFReal = 0
    var b: CGPDFReal = 0
    CGPDFScannerPopNumber(scanner, &b)
    CGPDFScannerPopNumber(scanner, &g)
    CGPDFScannerPopNumber(scanner, &r)
    ctx.state.fillColor = rgbToHex(r: CGFloat(r), g: CGFloat(g), b: CGFloat(b))
  }

  // show text ("Tj")
  CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    var object: CGPDFObjectRef?
    guard CGPDFScannerPopObject(scanner, &object), let obj = object else { return }
    if CGPDFObjectGetType(obj) == .string {
      var strRef: CGPDFStringRef?
      if CGPDFObjectGetValue(obj, .string, &strRef), let str = strRef,
        let bytes = CGPDFStringGetBytePtr(str)
      {
        let length = CGPDFStringGetLength(str)
        let data = Data(bytes: bytes, count: length)

        let text = decode(from: data)

        if let text = text, !text.isEmpty {
          // Apply full text matrix transformation
          var x: CGFloat = 0
          var y: CGFloat = 0

          if let tm = ctx.state.textMatrix {
            // Apply the transformation matrix: [x' y'] = [a c tx] [0]
            //                                            [b d ty] [1]
            x = tm.a * 0 + tm.c * 0 + tm.x
            y = tm.b * 0 + tm.d * 0 + tm.y
          }

          ctx.texts.append(
            TextRecord(x: x, y: y, text: text))
        }
      }
    }
  }

  // show text array ("TJ")
  CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    var object: CGPDFObjectRef?
    guard CGPDFScannerPopObject(scanner, &object), let obj = object else { return }
    if CGPDFObjectGetType(obj) == .array {
      var arrRef: CGPDFArrayRef?
      if CGPDFObjectGetValue(obj, .array, &arrRef), let arr = arrRef {
        let count = CGPDFArrayGetCount(arr)
        var collected = ""
        for i in 0..<count {
          var elem: CGPDFObjectRef?
          if CGPDFArrayGetObject(arr, i, &elem), let e = elem, CGPDFObjectGetType(e) == .string {
            var strRef: CGPDFStringRef?
            if CGPDFObjectGetValue(e, .string, &strRef), let s = strRef,
              let bytes = CGPDFStringGetBytePtr(s)
            {
              let len = CGPDFStringGetLength(s)
              let data = Data(bytes: bytes, count: len)

              let part = decode(from: data)

              if let part = part {
                collected += part
              }
            }
          }
        }

        if !collected.isEmpty {
          // Apply full text matrix transformation
          var x: CGFloat = 0
          var y: CGFloat = 0

          if let tm = ctx.state.textMatrix {
            x = tm.a * 0 + tm.c * 0 + tm.x
            y = tm.b * 0 + tm.d * 0 + tm.y
          }

          ctx.texts.append(
            TextRecord(x: x, y: y, text: collected))
        }
      }
    }
  }

  // move text position ("Td")
  CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    var ty: CGPDFReal = 0
    var tx: CGPDFReal = 0
    CGPDFScannerPopNumber(scanner, &ty)
    CGPDFScannerPopNumber(scanner, &tx)
    if var tm = ctx.state.textMatrix {
      tm.x += CGFloat(tx)
      tm.y += CGFloat(ty)
      ctx.state.textMatrix = tm
    } else {
      ctx.state.textMatrix = (1, 0, 0, 1, CGFloat(tx), CGFloat(ty))
    }
  }

  // move text position and set leading ("TD")
  CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    var ty: CGPDFReal = 0
    var tx: CGPDFReal = 0
    CGPDFScannerPopNumber(scanner, &ty)
    CGPDFScannerPopNumber(scanner, &tx)
    if var tm = ctx.state.textMatrix {
      tm.x += CGFloat(tx)
      tm.y += CGFloat(ty)
      ctx.state.textMatrix = tm
    } else {
      ctx.state.textMatrix = (1, 0, 0, 1, CGFloat(tx), CGFloat(ty))
    }
  }

  // set text leading ("TL")
  CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
    // Text leading - just consume the parameter but don't need to track it for our purposes
    var leading: CGPDFReal = 0
    CGPDFScannerPopNumber(scanner, &leading)
  }

  // move to next line ("T*")
  CGPDFOperatorTableSetCallback(table, "T*") { _, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    // Move to next line using text leading (we'll use a default of -14 points)
    if var tm = ctx.state.textMatrix {
      tm.y -= 14  // Default leading
      ctx.state.textMatrix = tm
    }
  }

  // show text and move to next line ("'")
  CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()

    // First move to next line
    if var tm = ctx.state.textMatrix {
      tm.y -= 14  // Default leading
      ctx.state.textMatrix = tm
    }

    // Then show the text (same as "Tj")
    var object: CGPDFObjectRef?
    guard CGPDFScannerPopObject(scanner, &object), let obj = object else { return }
    if CGPDFObjectGetType(obj) == .string {
      var strRef: CGPDFStringRef?
      if CGPDFObjectGetValue(obj, .string, &strRef), let str = strRef,
        let bytes = CGPDFStringGetBytePtr(str)
      {
        let length = CGPDFStringGetLength(str)
        let data = Data(bytes: bytes, count: length)

        let text = decode(from: data)

        if let text = text, !text.isEmpty {
          var x: CGFloat = 0
          var y: CGFloat = 0

          if let tm = ctx.state.textMatrix {
            x = tm.a * 0 + tm.c * 0 + tm.x
            y = tm.b * 0 + tm.d * 0 + tm.y
          }

          ctx.texts.append(
            TextRecord(x: x, y: y, text: text))
        }
      }
    }
  }

  // begin text object ("BT") resets text matrix
  CGPDFOperatorTableSetCallback(table, "BT") { _, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    ctx.state.textMatrix = (1, 0, 0, 1, 0, 0)
  }

  // add `Do` operator to enqueue Form XObjects (added after other callbacks so it has table)
  CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
    guard let info else { return }
    let ctx = Unmanaged<PDFParseContext>.fromOpaque(info).takeUnretainedValue()
    var namePtr: UnsafePointer<CChar>? = nil
    guard CGPDFScannerPopName(scanner, &namePtr), let cName = namePtr else { return }
    guard let parent = ctx.currentContent else { return }
    let name = String(cString: cName)
    guard let xobjObj = CGPDFContentStreamGetResource(parent, "XObject", name) else { return }
    if CGPDFObjectGetType(xobjObj) == .stream {
      var sref: CGPDFStreamRef?
      if CGPDFObjectGetValue(xobjObj, .stream, &sref), let stream = sref,
        let dict = CGPDFStreamGetDictionary(stream)
      {
        var subtypeName: UnsafePointer<CChar>? = nil
        if CGPDFDictionaryGetName(dict, "Subtype", &subtypeName), let sn = subtypeName,
          String(cString: sn) == "Form"
        {
          let nested = CGPDFContentStreamCreateWithStream(stream, dict, parent)
          let key = UInt(bitPattern: nested)
          if !ctx.visited.contains(where: { $0 == key }) {
            ctx.worklist.append(.init(content: nested, savedState: ctx.state))
          }
        }
      }
    }
  }

  // seed worklist with page content
  ctx.worklist.append(.init(content: content, savedState: ctx.state))

  // iteratively process worklist (depth-first)
  while let item = ctx.worklist.popLast() {
    let key = UInt(bitPattern: item.content)
    if ctx.visited.contains(where: { $0 == key }) { continue }
    ctx.visited.append(key)
    ctx.state = item.savedState
    ctx.currentContent = item.content
    let scanner = CGPDFScannerCreate(
      item.content, table, UnsafeMutableRawPointer(Unmanaged.passUnretained(ctx).toOpaque()))

    if !CGPDFScannerScan(scanner) {
      throw PDFError.scanFailed
    }
  }

  return PDFElements(texts: ctx.texts, rects: ctx.rects)
}

struct RectBounds {
  let leftX: CGFloat
  let bottomY: CGFloat
  let rightX: CGFloat
  let topY: CGFloat
}

func getRectBounds(_ rect: RectRecord) -> RectBounds {
  return RectBounds(
    leftX: rect.x,
    bottomY: rect.y,
    rightX: rect.x + rect.w,
    topY: rect.y + rect.h
  )
}

func getTextsInRectBounds(
  texts: [TextRecord], bounds: RectBounds, topOffsetY: CGFloat = 0, bottomOffsetY: CGFloat = 0
) -> [TextRecord] {
  return texts.filter { text in
    let xInBounds = text.x >= bounds.leftX && text.x <= bounds.rightX

    let yInBounds =
      text.y >= (bounds.bottomY - bottomOffsetY)
      && text.y <= (bounds.topY - topOffsetY)

    return xInBounds && yInBounds
  }
}

enum Color: String {
  case cm = "#FFFF0C"
  case td = "#FFBAB3"
  case tp = "#B3FFFF"
  case ds = "#F23EA7"
  case sae = "#9FFF9F"
  case rulers = "#FFFFA7"
  case header = "#64CCFF"
}

enum Day: Int, CaseIterable {
  case monday = 2
  case tuesday
  case wednesday
  case thursday
  case friday
  case saturday

  init?(from string: String) {
    switch string.lowercased() {
    case "lundi": self = .monday
    case "mardi": self = .tuesday
    case "mercredi": self = .wednesday
    case "jeudi": self = .thursday
    case "vendredi": self = .friday
    case "samedi": self = .saturday
    default: return nil
    }
  }
}

enum Subgroup: Int {
  case a = 0
  case b
}

enum LessonType: String {
  case cm = "CM"
  case td = "TD"
  case tp = "TP"
  case ds = "DS"
  case sae = "SAE"
  case other = "OTHER"
}

struct TimetableHeaderContent {
  let weekNumber: Int
  let weekNumberInYear: Int
  let startDate: Date
  let endDate: Date
}

struct TimetableHeader {
  let data: TimetableHeaderContent
  let bounds: RectBounds
}

enum ParseTimetableError: Error {
  case headerRectNotFound
  case headerTextsNotFound
  case headerTextUnparseable
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

struct TimetableGroup {
  /// Main group value.
  /// For example, if you're in G1A, the main group value is `1`.
  let main: Int

  /// Subgroup value. Where `0` is **A** and `1` is **B**.
  /// For example, if you're in G1A, the subgroup value is `0`.
  let sub: Subgroup

  /// Index of the day in the week, starting from `0`
  /// for **Monday** to `5` for **Saturday**.
  let day: Day
}

func round(_ value: CGFloat, toDecimalPlaces places: Int) -> CGFloat {
  let multiplier = pow(10.0, CGFloat(places))
  return Darwin.round(value * multiplier) / multiplier
}

func getTimetableGroups(_ elements: PDFElements, bounds header: RectBounds) -> [String:
  TimetableGroup]
{
  // --------------------------------------------------------------------------
  // |                                 HEADER                                 |
  // |-------------------------------------------------------------------------
  // ^ headers.leftX (x=0.0)
  //  |       | G1 |                                                          |
  //  | LUNDI | G2 |                                                          |
  //  |       | G3 |                                                          |
  //  |-------|----|----------------------------------------------------------|
  //  |       | G1 |                                                          |
  //  | MARDI | G2 |                                                          |
  //  |       | G3 |                                                          |
  //  |-----------------------------------------------------------------------|
  //  ^ rect.x (x=1.0)
  let days = elements.rects.filter { rect in
    return rect.color == Color.rulers.rawValue && rect.x == header.leftX + 1.0
  }

  var groupsFromY: [String: TimetableGroup] = [:]

  for rect in days {
    let dayBounds = getRectBounds(rect)
    let texts = getTextsInRectBounds(texts: elements.texts, bounds: dayBounds)

    guard let day = texts.first?.text else { continue }
    guard let day = Day(from: day) else { continue }

    //  --------- < dayBounds.topY
    //          ^ groupBounds.topY <= dayBounds.topY
    //  |       | G1 |                                                          |
    //          ^ groupBounds.bottomY >= dayBounds.bottomY
    //  | LUNDI | G2 |                                                          |
    //  |       | G3 |                                                          |
    //  --------- < dayBounds.bottomY
    //          ^ dayBounds.rightX = groupBounds.leftX
    let groups = elements.rects.filter { rect in
      let groupBounds = getRectBounds(rect)

      let withinDay =
        groupBounds.topY <= dayBounds.topY
        && groupBounds.bottomY >= dayBounds.bottomY

      let isGroup = rect.color == Color.rulers.rawValue
      let locatedAfterDay = groupBounds.leftX == dayBounds.rightX

      return withinDay && isGroup && locatedAfterDay
    }

    for rect in groups {
      let bounds = getRectBounds(rect)
      let texts = getTextsInRectBounds(texts: elements.texts, bounds: bounds)

      guard let text = texts.first?.text else { continue }
      guard let main = Int(String(text[text.index(text.startIndex, offsetBy: 1)])) else {
        continue
      }

      let subA = round(bounds.bottomY, toDecimalPlaces: 4)
      let subB = round(bounds.topY + (rect.h / 2), toDecimalPlaces: 4)

      groupsFromY[String(describing: subA)] = TimetableGroup(
        main: main,
        sub: .a,
        day: day
      )

      groupsFromY[String(describing: subB)] = TimetableGroup(
        main: main,
        sub: .b,
        day: day
      )
    }
  }

  return groupsFromY
}

private let BUT_INFO_REF: [String: String] = [
  "EE1A": "Questionnaire",
  "EE2A": "Questionnaire",

  // Semestre 1, commun.
  "S1.01": "Implémentation d'un besoin client",
  "S1.02": "Comparaison d'approches algorithmiques",
  "S1.03": "Installation d'un poste pour le développement",
  "S1.04": "Création d'une base de données",
  "S1.05": "Recueil de besoins",
  "S1.06": "Environnement économique",

  "R1.01": "Initiation au développement",
  "R1.02": "Développement d'interfaces web",
  "R1.03": "Architecture des ordinateurs",
  "R1.04": "Systèmes d'exploitation",
  "R1.05": "Bases de données et SQL",
  "R1.06": "Mathématiques discrètes",
  "R1.07": "Outils mathématiques fondamentaux",
  "R1.08": "Organisations",
  "R1.08B": "Introduction à la gestion des Organisations",
  "R1.09": "Économie durable et numérique",
  "R1.10": "Anglais",
  "R1.11": "Communication",
  "R1.12": "Projet professionnel et personnel",

  "P1.01": "Portfolio",

  // Semestre 2, commun.
  "S2.01": "Développement d'une application",
  "S2.02": "Exploration algorithmique d'un problème",
  "S2.03": "Installation de services réseau",
  "S2.04": "Exploitation d'une base de données",
  "S2.05": "Gestion d'un projet",
  "S2.06": "Organisation d'un travail d'équipe",

  "R2.01": "Développement orienté objets",
  "R2.02": "Développement d'applications avec IHM",
  "R2.02B": "Développement JavaScript",
  "R2.03": "Qualité de développement",
  "R2.04": "Communication et fonctionnement bas niveau",
  "R2.04B": "Réseaux",
  "R2.05": "Introduction aux services réseaux",
  "R2.06": "Exploitation d'une base de données",
  "R2.07": "Graphes",
  "R2.08": "Outils numériques pour les statistiques descriptives",
  "R2.09": "Méthodes numériques",
  "R2.10": "Introduction à la gestion des systèmes d'information",
  "R2.10A": "Gestion projet",
  "R2.10B": "Comptabilité",
  "R2.11": "Introduction au droit",
  "R2.12": "Anglais",
  "R2.13": "Communication technique",
  "R2.14": "Projet professionnel et personnel",

  "P2.01": "Portfolio",

  // Semestre 3, parcours A - we only have parcours A in this IUT.
  "S3.St": "Stage",
  "S3.01A": "Développement logiciel",
  "S3.01B": "Réseaux",

  "R3.01": "Développement web",
  "R3.01A": "Développement web / JavaScript",
  "R3.01B": "Développement web / PHP",
  "R3.02": "Développement efficace",
  "R3.03": "Analyse",
  "R3.04": "Qualité de développement",
  "R3.05": "Programmation système",
  "R3.06": "Architecture des réseaux",
  "R3.07": "SQL et programmation",
  "R3.08": "Probabilités",
  "R3.09": "Cryptographie et sécurité",
  "R3.10": "Systèmes d'information",
  "R3.10B": "Systèmes d'information",
  "R3.11": "Droit du numérique",
  "R3.12": "Anglais",
  "R3.13": "Communication professionnelle",
  "R3.14": "Projet personnel et professionnel",

  "P3.01": "Portfolio",

  // Semestre 4, parcours A.
  "S4.St": "Stage",
  "S4.01A": "Développement d'une application complexe",
  "S4.01B": "Réseaux",

  "R4.01": "Architecture logicielle",
  "R4.02": "Qualité de développement",
  "R4.03": "Qualité et au-delà du relationnel",
  "R4.04": "Méthodes d'optimisation",
  "R4.05": "Anglais",
  "R4.06": "Communication interne",
  "R4.07": "Projet personnel et professionnel",
  // .Real.
  "R4A.08": "Virtualisation",
  "R4A.09": "Systèmes d'information",
  "R4A.10": "Complément web",
  "R4A.11": "Développement pour applications mobiles",
  "R4A.12": "Automates et Langages",

  "P4.01": "Portfolio",

  // Semestre 5, parcours A.
  "S5A.01": "Développement avancé",
  // Same as S5A.01, somehow the IUT has two different codes for the same SAE.
  "S5A.02": "Développement avancé",

  "R5.01": "Management d'une équipe de projet informatique",
  "R5.02": "Projet personnel et professionnel",
  "R5.02A": "Projet personnel et professionnel",
  "R5A.02": "Projet personnel et professionnel",
  "R5.03": "Communication",
  // .Real.
  "R5A.04": "Qualité algorithmique",
  "R5A.05": "Programmation avancée",
  "R5A.06": "Programmation multimédia",
  "R5A.07": "Automatisation de la chaîne de production",
  "R5A.08": "Qualité de développement",
  "R5A.09": "Virtualisation avancée",
  "R5A.10": "NoSQL",
  "R5A.11": "Méthodes d'optimisation",
  "R5A.12": "Modélisations mathématiques",
  "R5A.13": "Économie durable et numérique",
  "R5A.14": "Anglais",

  "P5A.01": "Portfolio",
  "P5.01A": "Portfolio",
  "P5.01": "Portfolio",

  // Semestre 6, parcours A.
  "S6A.01": "Évolution d'une application existante",

  "R6.01": "Initiation à l'entrepreneuriat",
  "R6.02": "Droit du numérique et de la propriété intellectuelle",
  "R6.03": "Communication",
  "R6.04": "Projet personnel et professionnel",
  // .Real.
  "R6A.05": "Développement avancé",
  "R6A.06": "Maintenance applicative",

  "P6.01": "Portfolio",
]

protocol TimetableLessonContent {
  var type: String { get }
  var teacher: String { get }
  var room: String { get }
  var lessonFromReference: String { get }
}

struct TimetableLessonCMContent: TimetableLessonContent {
  let type: String
  let rawLesson: String
  let lessonFromReference: String
  let teacher: String
  let room: String
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
  let sub: Subgroup?
}

struct TimetableLessonCM {
  let type: LessonType = .cm
  let content: TimetableLessonCMContent
}

struct TimetableLessonTP {
  let type: LessonType = .tp
  let group: LessonGroup
  let content: TimetableLessonTPContent
}

struct TimetableLessonTD {
  let type: LessonType = .td
  let group: LessonGroup
  let content: TimetableLessonTDContent
}

struct TimetableLessonDS {
  let type: LessonType = .ds
  let group: LessonGroup
  let content: TimetableLessonDSContent
}

struct TimetableLessonSAE {
  let type: LessonType = .sae
  /// When `nil`, it means that it's for every groups.
  let group: LessonGroup?
  let content: TimetableLessonSAEContent
}

struct TimetableLessonOTHER {
  let type: LessonType = .other
  let content: TimetableLessonOTHERContent
}

enum TimetableLessonVariant {
  case cm(TimetableLessonCM)
  case tp(TimetableLessonTP)
  case td(TimetableLessonTD)
  case ds(TimetableLessonDS)
  case sae(TimetableLessonSAE)
  case other(TimetableLessonOTHER)
}

struct TimetableLesson {
  let startDate: Date
  let endDate: Date
  let variant: TimetableLessonVariant
}

/// Create a date from a timing, start week and a day of the week.
///
/// - Parameters:
///   - timeString: 13:30 (from `getTimetableTimings()`)
///   - baseDate: Start date of the week (from `TimetableHeader`)
///   - weekday: Day of the week to use
/// - Returns: A usable Date.
private func createDateFromTime(_ timeString: String, baseDate: Date, weekday: Day) -> Date? {
  let components = timeString.split(separator: ":").compactMap { Int($0) }
  guard components.count == 2 else { return nil }

  let calendar = Calendar.current

  var dateComponents = calendar.dateComponents([.year, .month, .weekOfYear], from: baseDate)
  dateComponents.weekday = weekday.rawValue
  dateComponents.hour = components[0]
  dateComponents.minute = components[1]
  dateComponents.second = 0

  return calendar.date(from: dateComponents)
}

private func removeDuplicateTypes(_ typeString: String) -> String {
  let types = typeString.split(separator: " ").map(String.init)
  let uniqueTypes = Array(Set(types))
  return uniqueTypes.joined(separator: " ")
}

private func getTimetableLessons(
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
          TimetableLessonCM(
            content: TimetableLessonCMContent(
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

struct Timetable {
  let header: TimetableHeaderContent
  let lessons: [TimetableLesson]
}

func getTimetable(using elements: PDFElements) throws -> Timetable {
  let header = try getTimetableHeader(elements)
  let timings = getTimetableTimings(elements, bounds: header.bounds)
  let groups = getTimetableGroups(elements, bounds: header.bounds)
  let lessons = getTimetableLessons(elements, header, timings, groups)

  return .init(header: header.data, lessons: lessons)
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
