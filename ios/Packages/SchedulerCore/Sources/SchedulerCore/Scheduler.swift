import Foundation
import SwiftFSRS

public enum Grade: String, CaseIterable, Codable, Sendable {
  case again, hard, good, easy
}

public enum Phase: String, Codable, Sendable {
  case new, learning, review, relearning
}

/// Everything the scheduler needs to know about one card. Synced to the backend as-is.
public struct SchedulingState: Codable, Equatable, Sendable {
  public var phase: Phase
  public var due: Date
  public var stability: Double
  public var difficulty: Double
  public var elapsedDays: Double
  public var scheduledDays: Double
  public var reps: Int
  public var lapses: Int
  public var lastReview: Date?

  public init(
    phase: Phase = .new,
    due: Date,
    stability: Double = 0,
    difficulty: Double = 0,
    elapsedDays: Double = 0,
    scheduledDays: Double = 0,
    reps: Int = 0,
    lapses: Int = 0,
    lastReview: Date? = nil
  ) {
    self.phase = phase
    self.due = due
    self.stability = stability
    self.difficulty = difficulty
    self.elapsedDays = elapsedDays
    self.scheduledDays = scheduledDays
    self.reps = reps
    self.lapses = lapses
    self.lastReview = lastReview
  }
}

/// The app only talks to this protocol, so the algorithm can be swapped without touching stored reviews.
public protocol CardScheduler: Sendable {
  func next(_ state: SchedulingState, grade: Grade, at now: Date, cardID: String) -> SchedulingState
}

extension CardScheduler {
  /// What each grade button would do, for showing intervals on the buttons.
  public func previews(_ state: SchedulingState, at now: Date, cardID: String) -> [Grade: SchedulingState] {
    Dictionary(uniqueKeysWithValues: Grade.allCases.map { ($0, next(state, grade: $0, at: now, cardID: cardID)) })
  }
}

public struct FSRSScheduler: CardScheduler {
  /// Every card comes back at least twice a year, however easy it felt.
  public static let maximumIntervalDays = 183.0

  private let algorithm: FSRSAlgorithm
  private let calendar: Calendar

  public init(desiredRetention: Double = 0.9, calendar: Calendar = .current) {
    var algorithm = FSRSAlgorithm.v5
    algorithm.requestRetention = desiredRetention
    algorithm.maximumInterval = Self.maximumIntervalDays
    self.algorithm = algorithm
    self.calendar = calendar
  }

  public func next(_ state: SchedulingState, grade: Grade, at now: Date, cardID: String) -> SchedulingState {
    let review = SchedulerType.shortTerm.implementation.schedule(
      card: state.fsrsCard,
      algorithm: algorithm,
      reviewRating: grade.rating,
      reviewTime: now
    )
    var result = SchedulingState(review.postReviewCard)
    guard result.scheduledDays > 0 else { return result }

    // Day-long intervals land on a study-day boundary, so "due today" doesn't drift through the day.
    let days = min(
      Fuzz.apply(to: result.scheduledDays, cardID: cardID, reps: state.reps),
      Self.maximumIntervalDays
    )
    result.scheduledDays = days
    result.due = StudyDay.start(of: now, calendar: calendar, addingDays: Int(days))
    return result
  }
}

extension Grade {
  fileprivate var rating: Rating {
    switch self {
    case .again: .again
    case .hard: .hard
    case .good: .good
    case .easy: .easy
    }
  }
}

extension SchedulingState {
  fileprivate var fsrsCard: Card {
    Card(
      due: due,
      stability: stability,
      difficulty: difficulty,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: lapses,
      status: phase.status,
      lastReview: lastReview
    )
  }

  fileprivate init(_ card: Card) {
    self.init(
      phase: Phase(card.status),
      due: card.due,
      stability: card.stability,
      difficulty: card.difficulty,
      elapsedDays: card.elapsedDays,
      scheduledDays: card.scheduledDays,
      reps: card.reps,
      lapses: card.lapses,
      lastReview: card.lastReview
    )
  }
}

extension Phase {
  fileprivate var status: Status {
    switch self {
    case .new: .new
    case .learning: .learning
    case .review: .review
    case .relearning: .relearning
    }
  }

  fileprivate init(_ status: Status) {
    switch status {
    case .new: self = .new
    case .learning: self = .learning
    case .review: self = .review
    case .relearning: self = .relearning
    }
  }
}
