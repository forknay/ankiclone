import Foundation

/// Short text for a grade button, such as "10m", "3d" or "2.1mo".
public enum IntervalLabel {
  public static func text(from now: Date, to due: Date) -> String {
    let seconds = due.timeIntervalSince(now)
    if seconds < 3600 { return "\(max(1, Int((seconds / 60).rounded())))m" }
    if seconds < 86_400 { return "\(Int((seconds / 3600).rounded()))h" }
    let days = seconds / 86_400
    if days < 30 { return "\(Int(days.rounded()))d" }
    if days < 365 { return String(format: "%.1fmo", days / 30.4375) }
    return String(format: "%.1fy", days / 365.25)
  }
}
