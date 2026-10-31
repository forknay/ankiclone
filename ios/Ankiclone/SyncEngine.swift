import Foundation
import Observation
import SchedulerCore
import SwiftData

private struct SyncResponse: Decodable {
  struct Deck: Decodable {
    let id, name, kind, reverseMode: String
    let createdAt: Double
  }
  struct Note: Decodable {
    let id, deckId, kind, hanzi, pinyin, english: String
  }
  struct Card: Decodable {
    let id, noteId, deckId, direction, phase: String
    let due: Double
    let stability, difficulty, elapsedDays, scheduledDays: Double
    let reps, lapses: Int
    let lastReview: Double?
    let heldBy: String?
  }
  struct Lesson: Decodable {
    let date, title, body: String
  }
  let cursor: Int
  let decks: [Deck]
  let notes: [Note]
  let cards: [Card]
  let lessons: [Lesson]
}

private struct ReviewUpload: Encodable {
  struct State: Encodable {
    let phase: String
    let due: Double
    let stability, difficulty, elapsedDays, scheduledDays: Double
    let reps, lapses: Int
    let lastReview: Double?
  }
  let id, cardId, grade: String
  let reviewedAt: Double
  let typedAnswer: String?
  let state: State
}

private struct SyncRequest: Encodable {
  struct DeckSetting: Encodable {
    let deckId, reverseMode: String
  }
  let cursor: Int
  let reviews: [ReviewUpload]
  let deckSettings: [DeckSetting]
}

private func milliseconds(_ date: Date) -> Double { (date.timeIntervalSince1970 * 1000).rounded() }
private func date(_ milliseconds: Double) -> Date { Date(timeIntervalSince1970: milliseconds / 1000) }

@MainActor
@Observable
final class SyncEngine {
  enum Status: Equatable {
    case idle, syncing, offline(String), notConfigured
  }

  private(set) var status: Status = .idle
  private let cursorKey = "syncCursor"

  func sync(_ context: ModelContext) async {
    guard status != .syncing else { return }
    guard AppSettings.isConfigured, let url = URL(string: AppSettings.serverURL)?.appending(path: "sync") else {
      status = .notConfigured
      return
    }
    status = .syncing
    do {
      let pending = try context.fetch(FetchDescriptor<PendingReview>(sortBy: [SortDescriptor(\.reviewedAt)]))
      let dirtyDecks = try context.fetch(FetchDescriptor<DeckRecord>(predicate: #Predicate { $0.reverseModeDirty }))
      let sentModes = dirtyDecks.map { ($0, $0.reverseModeRaw) }
      let body = SyncRequest(
        cursor: UserDefaults.standard.integer(forKey: cursorKey),
        reviews: try pending.map(upload),
        deckSettings: sentModes.map { .init(deckId: $0.0.id, reverseMode: $0.1) })

      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("Bearer \(AppSettings.token)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server returned \(code)"])
      }
      let result = try JSONDecoder().decode(SyncResponse.self, from: data)

      // Only what was actually sent is cleared: reviews made while waiting stay queued.
      pending.forEach(context.delete)
      for (deck, mode) in sentModes where deck.reverseModeRaw == mode { deck.reverseModeDirty = false }
      try merge(result, into: context)
      try context.save()
      UserDefaults.standard.set(result.cursor, forKey: cursorKey)
      status = .idle
    } catch {
      // Everything stays queued locally and goes up on the next attempt.
      status = .offline(error.localizedDescription)
    }
  }

  func registerDevice(token: String) async {
    guard AppSettings.isConfigured, let url = URL(string: AppSettings.serverURL)?.appending(path: "devices") else { return }
    #if DEBUG
      let environment = "sandbox"
    #else
      let environment = "production"
    #endif
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(AppSettings.token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(["token": token, "environment": environment])
    _ = try? await URLSession.shared.data(for: request)
  }

  private func upload(_ review: PendingReview) throws -> ReviewUpload {
    let state = try JSONDecoder().decode(SchedulingState.self, from: review.stateData)
    return ReviewUpload(
      id: review.id, cardId: review.cardID, grade: review.grade, reviewedAt: milliseconds(review.reviewedAt),
      typedAnswer: review.typedAnswer,
      state: .init(
        phase: state.phase.rawValue, due: milliseconds(state.due), stability: state.stability,
        difficulty: state.difficulty, elapsedDays: state.elapsedDays, scheduledDays: state.scheduledDays,
        reps: state.reps, lapses: state.lapses, lastReview: state.lastReview.map(milliseconds)))
  }

  private func merge(_ result: SyncResponse, into context: ModelContext) throws {
    let decks = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<DeckRecord>()).map { ($0.id, $0) })
    for item in result.decks {
      if let deck = decks[item.id] {
        deck.name = item.name
        if !deck.reverseModeDirty { deck.reverseModeRaw = item.reverseMode }
      } else {
        context.insert(DeckRecord(id: item.id, name: item.name, kind: item.kind, reverseModeRaw: item.reverseMode, createdAt: item.createdAt))
      }
    }

    let notes = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<NoteRecord>()).map { ($0.id, $0) })
    for item in result.notes {
      if let note = notes[item.id] {
        note.hanzi = item.hanzi
        note.pinyin = item.pinyin
        note.english = item.english
      } else {
        context.insert(NoteRecord(id: item.id, deckID: item.deckId, kind: item.kind, hanzi: item.hanzi, pinyin: item.pinyin, english: item.english))
      }
    }

    // A card with a review still queued here is newer than whatever the server just sent.
    let queued = Set(try context.fetch(FetchDescriptor<PendingReview>()).filter { !$0.isDeleted }.map(\.cardID))
    let cards = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CardRecord>()).map { ($0.id, $0) })
    for item in result.cards where !queued.contains(item.id) {
      let lastReview = item.lastReview.map(date)
      if let card = cards[item.id] {
        card.schedulingState = SchedulingState(
          phase: Phase(rawValue: item.phase) ?? .new, due: date(item.due), stability: item.stability,
          difficulty: item.difficulty, elapsedDays: item.elapsedDays, scheduledDays: item.scheduledDays,
          reps: item.reps, lapses: item.lapses, lastReview: lastReview)
        card.heldBy = item.heldBy
      } else {
        context.insert(
          CardRecord(
            id: item.id, noteID: item.noteId, deckID: item.deckId, directionRaw: item.direction, phaseRaw: item.phase,
            due: date(item.due), stability: item.stability, difficulty: item.difficulty, elapsedDays: item.elapsedDays,
            scheduledDays: item.scheduledDays, reps: item.reps, lapses: item.lapses, lastReview: lastReview, heldBy: item.heldBy))
      }
    }

    let lessons = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<LessonRecord>()).map { ($0.date, $0) })
    for item in result.lessons where lessons[item.date] == nil {
      context.insert(LessonRecord(date: item.date, title: item.title, body: item.body))
    }
  }
}
