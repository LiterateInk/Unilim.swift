struct TimetableGroup {
  /// Main group value.
  /// For example, if you're in G1A, the main group value is `1`.
  let main: TimetableMainGroup

  /// Sub group value. Where `0` is **A** and `1` is **B**.
  /// For example, if you're in G1A, the subgroup value is `0`.
  let sub: TimetableSubGroup

  /// Index of the day in the week, starting from `0`
  /// for **Monday** to `5` for **Saturday**.
  let day: Day
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
