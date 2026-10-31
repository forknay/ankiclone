import Foundation

/// A study day runs 4 AM to 4 AM, as in Anki, so late-night reviews count towards the same day.
public enum StudyDay {
  public static let rolloverHour = 4

  public static func start(of date: Date, calendar: Calendar = .current, addingDays days: Int = 0) -> Date {
    let shifted = calendar.date(byAdding: .hour, value: -rolloverHour, to: date)!
    let day = calendar.startOfDay(for: shifted)
    let target = calendar.date(byAdding: .day, value: days, to: day)!
    return calendar.date(bySettingHour: rolloverHour, minute: 0, second: 0, of: target)!
  }
}

/// Spreads long intervals by up to 5% so cards reviewed together don't all return on one day.
/// Deterministic per card and review, so button previews match what actually happens,
/// and the same factor for every grade, so Hard/Good/Easy keep their order.
enum Fuzz {
  static func apply(to days: Double, cardID: String, reps: Int) -> Double {
    guard days >= 3 else { return days.rounded() }
    let spread = (fnv1a("\(cardID)#\(reps)") % 1001)
    let factor = 0.95 + 0.1 * Double(spread) / 1000
    return max(1, (days * factor).rounded())
  }

  private static func fnv1a(_ text: String) -> UInt64 {
    text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
  }
}
