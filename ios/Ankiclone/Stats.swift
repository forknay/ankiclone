import Foundation

/// Lifetime study totals, kept on this iPhone. They survive app updates but not deleting the app.
enum Stats {
  static let revealsKey = "stats.reveals"
  static let secondsKey = "stats.seconds"

  static func recordReveal() {
    UserDefaults.standard.set(UserDefaults.standard.integer(forKey: revealsKey) + 1, forKey: revealsKey)
  }

  static func addTime(_ seconds: TimeInterval) {
    guard seconds > 0 else { return }
    UserDefaults.standard.set(UserDefaults.standard.double(forKey: secondsKey) + seconds, forKey: secondsKey)
  }

  /// Starts the counter from reviews done before it existed. Imported cards arrive with one rep
  /// already counted, so those are left out.
  static func backfillReveals(from cards: [CardRecord]) {
    guard UserDefaults.standard.object(forKey: revealsKey) == nil, !cards.isEmpty else { return }
    let imported = cards.filter { $0.id.hasPrefix("card-") && $0.id.hasSuffix("-zh") }.count
    let reps = cards.reduce(0) { $0 + $1.reps }
    UserDefaults.standard.set(max(0, reps - imported), forKey: revealsKey)
  }

  static func formatTime(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
  }
}
