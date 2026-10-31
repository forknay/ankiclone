import Foundation
import SchedulerCore
import SwiftData

enum ReverseMode: String, CaseIterable, Identifiable {
  case type, recall
  var id: String { rawValue }
  var label: String { self == .type ? "Type pinyin" : "Recall in your head" }
}

@Model
final class DeckRecord {
  @Attribute(.unique) var id: String
  var name: String
  var kind: String
  var reverseModeRaw: String
  var createdAt: Double
  /// Changed on this device and not yet uploaded.
  var reverseModeDirty = false

  init(id: String, name: String, kind: String, reverseModeRaw: String, createdAt: Double) {
    self.id = id
    self.name = name
    self.kind = kind
    self.reverseModeRaw = reverseModeRaw
    self.createdAt = createdAt
  }

  var reverseMode: ReverseMode { ReverseMode(rawValue: reverseModeRaw) ?? .recall }
}

@Model
final class NoteRecord {
  @Attribute(.unique) var id: String
  var deckID: String
  var kind: String
  var hanzi: String
  var pinyin: String
  var english: String

  init(id: String, deckID: String, kind: String, hanzi: String, pinyin: String, english: String) {
    self.id = id
    self.deckID = deckID
    self.kind = kind
    self.hanzi = hanzi
    self.pinyin = pinyin
    self.english = english
  }
}

@Model
final class CardRecord {
  @Attribute(.unique) var id: String
  var noteID: String
  var deckID: String
  var directionRaw: String
  var phaseRaw: String
  var due: Date
  var stability: Double
  var difficulty: Double
  var elapsedDays: Double
  var scheduledDays: Double
  var reps: Int
  var lapses: Int
  var lastReview: Date?
  var heldBy: String?

  init(
    id: String, noteID: String, deckID: String, directionRaw: String, phaseRaw: String, due: Date,
    stability: Double, difficulty: Double, elapsedDays: Double, scheduledDays: Double, reps: Int,
    lapses: Int, lastReview: Date?, heldBy: String?
  ) {
    self.id = id
    self.noteID = noteID
    self.deckID = deckID
    self.directionRaw = directionRaw
    self.phaseRaw = phaseRaw
    self.due = due
    self.stability = stability
    self.difficulty = difficulty
    self.elapsedDays = elapsedDays
    self.scheduledDays = scheduledDays
    self.reps = reps
    self.lapses = lapses
    self.lastReview = lastReview
    self.heldBy = heldBy
  }

  var direction: Direction { Direction(rawValue: directionRaw) ?? .zhToEn }

  var schedulingState: SchedulingState {
    get {
      SchedulingState(
        phase: Phase(rawValue: phaseRaw) ?? .new, due: due, stability: stability, difficulty: difficulty,
        elapsedDays: elapsedDays, scheduledDays: scheduledDays, reps: reps, lapses: lapses, lastReview: lastReview)
    }
    set {
      phaseRaw = newValue.phase.rawValue
      due = newValue.due
      stability = newValue.stability
      difficulty = newValue.difficulty
      elapsedDays = newValue.elapsedDays
      scheduledDays = newValue.scheduledDays
      reps = newValue.reps
      lapses = newValue.lapses
      lastReview = newValue.lastReview
    }
  }

  var queueCard: QueueCard {
    QueueCard(
      id: id, noteID: noteID, phase: Phase(rawValue: phaseRaw) ?? .new, due: due,
      lastReview: lastReview, isHeld: heldBy != nil)
  }
}

@Model
final class LessonRecord {
  @Attribute(.unique) var date: String
  var title: String
  var body: String

  init(date: String, title: String, body: String) {
    self.date = date
    self.title = title
    self.body = body
  }
}

/// A review waiting to be uploaded. Removed only once the server has confirmed it.
@Model
final class PendingReview {
  @Attribute(.unique) var id: String
  var cardID: String
  var grade: String
  var reviewedAt: Date
  var typedAnswer: String?
  var stateData: Data

  init(id: String, cardID: String, grade: String, reviewedAt: Date, typedAnswer: String?, stateData: Data) {
    self.id = id
    self.cardID = cardID
    self.grade = grade
    self.reviewedAt = reviewedAt
    self.typedAnswer = typedAnswer
    self.stateData = stateData
  }
}

struct LessonEntry: Codable, Hashable {
  var hanzi: String
  var pinyin: String
  var english: String
}

struct LessonCharacter: Codable, Hashable {
  var hanzi: String
  var pinyin: String
  var english: String
  var uses: [LessonEntry]
}

struct LessonBody: Codable {
  var intro: String
  var characters: [LessonCharacter]
  var words: [LessonEntry]
  var sentenceCount: Int
}
