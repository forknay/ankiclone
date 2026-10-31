import SchedulerCore
import SwiftData
import SwiftUI

struct ReviewView: View {
  let deckID: String?

  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Environment(SyncEngine.self) private var sync
  @State private var current: CardRecord?
  @State private var note: NoteRecord?
  @State private var mode: ReverseMode = .recall
  @State private var revealed = false
  @State private var typed = ""
  @State private var checks: [SyllableCheck] = []
  @State private var remaining = QueueCounts()
  @State private var previews: [Grade: SchedulingState] = [:]
  @State private var loaded = false
  @State private var sinceLastSync = 0
  @FocusState private var typing: Bool

  private let scheduler = FSRSScheduler()

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button("Done", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
        Spacer()
        CountBadges(counts: remaining)
      }
      .padding()

      if let current, let note {
        ScrollView {
          VStack(spacing: 20) {
            prompt(current, note)
            if revealed { answer(current, note) }
          }
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 20)
          .padding(.top, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        controls(current, note)
      } else if loaded {
        Spacer()
        Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
        Text("All caught up").font(.title2.weight(.semibold)).padding(.top, 8)
        Button("Back to decks") { dismiss() }.padding(.top, 16)
        Spacer()
      } else {
        Spacer()
      }
    }
    .task { advance() }
  }

  @ViewBuilder
  private func prompt(_ card: CardRecord, _ note: NoteRecord) -> some View {
    switch card.direction {
    case .zhToEn:
      Text(note.hanzi)
        .font(.hanzi(note.kind == "sentence" ? 34 : 72))
        .multilineTextAlignment(.center)
        .textSelection(.enabled)
    case .enToZh:
      Text(CardPrompt.english(note.english, hanzi: note.hanzi, pinyin: note.pinyin))
        .font(.title2)
        .multilineTextAlignment(.center)
      if mode == .type && !revealed {
        TextField("Type the pinyin, e.g. ni3 hao3", text: $typed)
          .textFieldStyle(.roundedBorder)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($typing)
          .submitLabel(.done)
          .onSubmit { reveal(note) }
      }
    }
  }

  @ViewBuilder
  private func answer(_ card: CardRecord, _ note: NoteRecord) -> some View {
    Divider()
    if card.direction == .enToZh {
      Text(note.hanzi).font(.hanzi(note.kind == "sentence" ? 34 : 72)).multilineTextAlignment(.center)
    }
    if checks.isEmpty {
      Text(note.pinyin).font(.title3).multilineTextAlignment(.center)
    } else {
      PinyinResultView(checks: checks, typed: typed)
    }
    if card.direction == .zhToEn {
      Text(note.english).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
  }

  @ViewBuilder
  private func controls(_ card: CardRecord, _ note: NoteRecord) -> some View {
    Group {
      if revealed {
        HStack(spacing: 8) {
          ForEach(Grade.allCases, id: \.self) { grade in
            Button {
              answer(grade, card)
            } label: {
              VStack(spacing: 2) {
                Text(previews[grade].map { IntervalLabel.text(from: Date(), to: $0.due) } ?? "").font(.caption2)
                Text(grade.rawValue.capitalized).font(.subheadline.weight(.semibold))
              }
              .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .tint(grade.color)
          }
        }
      } else {
        Button {
          reveal(note)
        } label: {
          Text(card.direction == .enToZh && mode == .type ? "Check" : "Show answer")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding()
  }

  private func reveal(_ note: NoteRecord) {
    guard let current else { return }
    if current.direction == .enToZh && mode == .type {
      checks = PinyinCheck.check(typed: typed, answer: note.pinyin)
    }
    typing = false
    previews = scheduler.previews(current.schedulingState, at: Date(), cardID: current.id)
    revealed = true
  }

  private func answer(_ grade: Grade, _ card: CardRecord) {
    let now = Date()
    let state = scheduler.next(card.schedulingState, grade: grade, at: now, cardID: card.id)
    card.schedulingState = state
    let cardID = card.id
    let held = (try? context.fetch(FetchDescriptor<CardRecord>(predicate: #Predicate { $0.heldBy == cardID }))) ?? []
    held.forEach { $0.heldBy = nil }
    if let data = try? JSONEncoder().encode(state) {
      context.insert(
        PendingReview(
          id: UUID().uuidString, cardID: card.id, grade: grade.rawValue, reviewedAt: now,
          typedAnswer: typed.isEmpty ? nil : typed, stateData: data))
    }
    try? context.save()

    sinceLastSync += 1
    if sinceLastSync >= 20 {
      sinceLastSync = 0
      Task { await sync.sync(context) }
    }
    advance()
  }

  private func advance() {
    let descriptor: FetchDescriptor<CardRecord>
    if let deckID {
      descriptor = FetchDescriptor(predicate: #Predicate { $0.deckID == deckID })
    } else {
      descriptor = FetchDescriptor()
    }
    let cards = (try? context.fetch(descriptor)) ?? []
    // Burying looks at siblings in any deck, but a note's cards always share a deck.
    let now = Date()
    let queue = cards.map(\.queueCard)
    remaining = StudyQueue.counts(queue, now: now)
    revealed = false
    typed = ""
    checks = []
    previews = [:]
    loaded = true

    guard let next = StudyQueue.next(queue, now: now), let card = cards.first(where: { $0.id == next.id }) else {
      current = nil
      note = nil
      return
    }
    let noteID = card.noteID
    let deckID = card.deckID
    note = try? context.fetch(FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == noteID })).first
    mode = (try? context.fetch(FetchDescriptor<DeckRecord>(predicate: #Predicate { $0.id == deckID })).first)?.reverseMode ?? .recall
    current = card
    typing = card.direction == .enToZh && mode == .type
  }
}

private struct PinyinResultView: View {
  let checks: [SyllableCheck]
  let typed: String

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 6) {
        ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
          Text(check.expected).font(.title3.weight(.semibold)).foregroundStyle(check.result.color)
        }
      }
      if !summary.isEmpty {
        Text(summary).font(.footnote).foregroundStyle(.secondary)
      }
      Text("You typed: \(typed.isEmpty ? "nothing" : typed)").font(.footnote).foregroundStyle(.secondary)
    }
  }

  private var summary: String {
    let results = checks.map(\.result)
    if results.allSatisfy({ $0 == .correct }) { return "All correct" }
    var parts: [String] = []
    if results.contains(.wrong) { parts.append("red: wrong syllable") }
    if results.contains(.wrongTone) { parts.append("orange: wrong tone") }
    if results.contains(.missingTone) { parts.append("yellow: no tone given") }
    return parts.joined(separator: " · ")
  }
}

extension SyllableResult {
  fileprivate var color: Color {
    switch self {
    case .correct: .green
    case .wrongTone: .orange
    case .missingTone: .yellow
    case .wrong: .red
    }
  }
}

extension Grade {
  fileprivate var color: Color {
    switch self {
    case .again: .red
    case .hard: .orange
    case .good: .green
    case .easy: .blue
    }
  }
}
