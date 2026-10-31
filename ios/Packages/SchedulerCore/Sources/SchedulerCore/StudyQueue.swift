import Foundation

public enum Direction: String, Codable, Sendable {
  case zhToEn = "zh_en"
  case enToZh = "en_zh"
}

/// The parts of a card that decide whether and when it can be shown.
public struct QueueCard: Sendable {
  public let id: String
  public let noteID: String
  public let phase: Phase
  public let due: Date
  public let lastReview: Date?
  public let isHeld: Bool

  public init(id: String, noteID: String, phase: Phase, due: Date, lastReview: Date?, isHeld: Bool) {
    self.id = id
    self.noteID = noteID
    self.phase = phase
    self.due = due
    self.lastReview = lastReview
    self.isHeld = isHeld
  }
}

public struct QueueCounts: Equatable, Sendable {
  public var overdue = 0
  public var learning = 0
  public var fresh = 0
  public var total: Int { overdue + learning + fresh }
  public init() {}
}

public enum StudyQueue {
  /// A learning card due this soon is shown rather than leaving the session idle, as in Anki.
  public static let learnAhead: TimeInterval = 20 * 60

  /// Cards available right now: not held, and not buried because the other direction was seen today.
  public static func available(_ cards: [QueueCard], now: Date, calendar: Calendar = .current) -> [QueueCard] {
    let dayStart = StudyDay.start(of: now, calendar: calendar)
    let reviewedToday = Dictionary(grouping: cards.filter { ($0.lastReview ?? .distantPast) >= dayStart }, by: \.noteID)
    return cards.filter { card in
      if card.isHeld { return false }
      if card.phase == .learning || card.phase == .relearning { return true }
      return !(reviewedToday[card.noteID] ?? []).contains { $0.id != card.id }
    }
  }

  public static func counts(_ cards: [QueueCard], now: Date, calendar: Calendar = .current) -> QueueCounts {
    var counts = QueueCounts()
    for card in available(cards, now: now, calendar: calendar) where card.due <= now {
      switch card.phase {
      case .review: counts.overdue += 1
      case .learning, .relearning: counts.learning += 1
      case .new: counts.fresh += 1
      }
    }
    return counts
  }

  /// Learning cards first, so short steps stay on time; then the most overdue reviews; then new cards.
  public static func next(_ cards: [QueueCard], now: Date, calendar: Calendar = .current) -> QueueCard? {
    let open = available(cards, now: now, calendar: calendar)
    let learning = open.filter { $0.phase == .learning || $0.phase == .relearning }
    if let card = learning.filter({ $0.due <= now }).min(by: { $0.due < $1.due }) { return card }
    if let card = open.filter({ $0.phase == .review && $0.due <= now }).min(by: { $0.due < $1.due }) { return card }
    if let card = open.filter({ $0.phase == .new && $0.due <= now }).min(by: { $0.due < $1.due }) { return card }
    return learning.filter { $0.due.timeIntervalSince(now) <= learnAhead }.min { $0.due < $1.due }
  }
}

public enum CardPrompt {
  /// English shown on an English-first card, with the answer's characters and pinyin blanked
  /// out of notes such as "to practise (as in 学习 study)".
  public static func english(_ english: String, hanzi: String, pinyin: String) -> String {
    var text = english
    if !pinyin.isEmpty { text = text.replacingOccurrences(of: pinyin, with: "＿") }
    for character in hanzi where character.isChineseCharacter {
      text = text.replacingOccurrences(of: String(character), with: "＿")
    }
    return text
  }
}

extension Character {
  var isChineseCharacter: Bool {
    unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
  }
}
