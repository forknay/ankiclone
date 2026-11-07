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
  @State private var revealed = false
  @State private var remaining = QueueCounts()
  @State private var previews: [Grade: SchedulingState] = [:]
  @State private var loaded = false
  @State private var sinceLastSync = 0

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
        controls(current)
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

  private func hanziSize(_ note: NoteRecord) -> CGFloat {
    switch note.kind {
    case "sentence": 34
    case "lookalike": 60
    default: 72
    }
  }

  @ViewBuilder
  private func prompt(_ card: CardRecord, _ note: NoteRecord) -> some View {
    switch card.direction {
    case .zhToEn:
      Text(note.kind == "lookalike" ? note.hanzi.map(String.init).joined(separator: "  ") : note.hanzi)
        .font(.hanzi(hanziSize(note)))
        .multilineTextAlignment(.center)
        .textSelection(.enabled)
    case .enToZh:
      // The sound is given; the work is picturing the character. The meaning tells homophones apart.
      Text(note.pinyin).font(.largeTitle.weight(.semibold)).multilineTextAlignment(.center)
      Text(CardPrompt.english(note.english, hanzi: note.hanzi, pinyin: note.pinyin))
        .font(.title3)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  @ViewBuilder
  private func answer(_ card: CardRecord, _ note: NoteRecord) -> some View {
    Divider()
    if note.kind == "lookalike" {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(LookalikeMember.members(of: note), id: \.self) { member in
          HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(member.hanzi).font(.hanzi(40))
            VStack(alignment: .leading, spacing: 2) {
              Text(member.pinyin).font(.title3)
              Text(member.english).foregroundStyle(.secondary)
            }
          }
        }
      }
    } else if card.direction == .enToZh {
      Text(note.hanzi).font(.hanzi(hanziSize(note))).multilineTextAlignment(.center)
    } else {
      Text(note.pinyin).font(.title3).multilineTextAlignment(.center)
      Text(note.english).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
  }

  @ViewBuilder
  private func controls(_ card: CardRecord) -> some View {
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
          reveal()
        } label: {
          Text("Show answer").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding()
  }

  private func reveal() {
    guard let current else { return }
    previews = scheduler.previews(current.schedulingState, at: Date(), cardID: current.id)
    revealed = true
    Stats.recordReveal()
  }

  private func answer(_ grade: Grade, _ card: CardRecord) {
    let now = Date()
    let state = scheduler.next(card.schedulingState, grade: grade, at: now, cardID: card.id)
    card.schedulingState = state
    if grade == .again { card.agains += 1 }
    let cardID = card.id
    let held = (try? context.fetch(FetchDescriptor<CardRecord>(predicate: #Predicate { $0.heldBy == cardID }))) ?? []
    held.forEach { $0.heldBy = nil }
    if let data = try? JSONEncoder().encode(state) {
      context.insert(
        PendingReview(
          id: UUID().uuidString, cardID: card.id, grade: grade.rawValue, reviewedAt: now,
          typedAnswer: nil, stateData: data))
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
    previews = [:]
    loaded = true

    guard let next = StudyQueue.next(queue, now: now), let card = cards.first(where: { $0.id == next.id }) else {
      current = nil
      note = nil
      return
    }
    let noteID = card.noteID
    note = try? context.fetch(FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == noteID })).first
    current = card
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
