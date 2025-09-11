import Foundation

func round(_ value: CGFloat, toDecimalPlaces places: Int) -> CGFloat {
  let multiplier = pow(10.0, CGFloat(places))
  return Darwin.round(value * multiplier) / multiplier
}

/// Create a date from a timing, start week and a day of the week.
///
/// - Parameters:
///   - timeString: 13:30 (from `getTimetableTimings()`)
///   - baseDate: Start date of the week (from `TimetableHeader`)
///   - weekday: Day of the week to use
/// - Returns: A usable Date.
func createDateFromTime(_ timeString: String, baseDate: Date, weekday: Day) -> Date? {
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

func removeDuplicateTypes(_ typeString: String) -> String {
  let types = typeString.split(separator: " ").map(String.init)
  let uniqueTypes = Array(Set(types))
  return uniqueTypes.joined(separator: " ")
}
