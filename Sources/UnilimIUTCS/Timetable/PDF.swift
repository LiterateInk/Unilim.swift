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
