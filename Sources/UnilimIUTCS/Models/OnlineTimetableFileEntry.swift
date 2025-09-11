import Foundation

/// Entry of a timetable file in the directory listing available
/// on the university's official website.
public struct OnlineTimetableFileEntry: Comparable {
  /// Full name of the file, including the `.pdf` extension.
  public let fileName: String

  /// Date displayed on the directory listing,
  /// should equals to the last time an update was made to the PDF file.
  public let lastUpdated: Date

  /// Week since the beginning of the school year, starts at `1` and
  /// in September, obviously.
  public let weekNumber: Int

  /// Year of study for this timetable.
  public let fromYear: TimetableYear

  /// Direct link to access the timetable.
  public let url: URL

  /// Initialize a new timetable entry.
  ///
  /// - Parameters:
  ///   - fileName: Matched `fileName` from the directory listing
  ///   - date: Matched `date` from the directory listing
  ///   - fromYear: Year of study requested for the listing
  internal init(fileName: String, date: String, fromYear: TimetableYear) {
    self.fileName = fileName
    self.fromYear = fromYear

    // force unwrap since the URL is always going to be correct.
    self.url = URL(string: "\(timetableDirectoryListing)/\(fromYear.rawValue)/\(fileName)")!

    // file name: A{Year}_S{weekNumber}.pdf
    let week = fileName.replacingOccurrences(
      of: "(A(.*)_S)|(.pdf)", with: "", options: .regularExpression)

    // force unwrap because the file name is always going to contain
    // the week number at this position.
    self.weekNumber = Int(week)!

    // date: yyyy-MM-dd HH:mm
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    self.lastUpdated = formatter.date(from: date) ?? Date.distantPast
  }

  public static func < (lhs: OnlineTimetableFileEntry, rhs: OnlineTimetableFileEntry) -> Bool {
    lhs.weekNumber < rhs.weekNumber
  }
}
