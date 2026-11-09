import SchedulerCore
import SwiftData
import SwiftUI

/// Endless reading practice: every Chinese-first card already seen, shuffled, with no grading and
/// no effect on scheduling. For when the day's reviews are done and you want more.
struct PracticeView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @State private var queue: [(card: CardRecord, note: NoteRecord)] = []
  @State private var position = 0
  @State private var revealed = false
  @State private var seen = 0

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button("Done", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
        Spacer()
        Text("\(seen) this session").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
      }
      .padding()

      if queue.indices.contains(position) {
        let item = queue[position]
        ScrollView {
          CardFace(direction: .zhToEn, note: item.note, revealed: revealed)
        }
        Button {
          revealed ? next() : reveal()
        } label: {
          Text(revealed ? "Next" : "Show answer").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .padding()
      } else {
        Spacer()
        Text("Nothing to practise yet. Study some cards first.").foregroundStyle(.secondary).padding()
        Spacer()
      }
    }
    .task { shuffle() }
  }

  private func reveal() {
    revealed = true
    seen += 1
    Stats.recordReveal()
  }

  private func next() {
    revealed = false
    position += 1
    if position >= queue.count { shuffle() }
  }

  /// A fresh round through every card, in random order but with often-missed cards tending to come
  /// earlier (weighted random sampling: weight 1 + Agains, capped).
  private func shuffle() {
    let cards = (try? context.fetch(FetchDescriptor<CardRecord>(predicate: #Predicate { $0.directionRaw == "zh_en" }))) ?? []
    let notes = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<NoteRecord>())) ?? []).map { ($0.id, $0) })
    // Only cards already met, so practice never spoils sentences the reading deck hasn't unlocked.
    let pool = cards.filter { $0.reps > 0 || $0.phaseRaw != Phase.new.rawValue }
    let previous = queue.last?.note.id
    var round = pool
      .compactMap { card in notes[card.noteID].map { (card: card, note: $0) } }
      .map { item in (item, -log(Double.random(in: Double.ulpOfOne..<1)) / Double(1 + min(item.card.agains, 9))) }
      .sorted { $0.1 < $1.1 }
      .map(\.0)
    // Don't show the last card of one round as the first of the next.
    if round.count > 1, round.first?.note.id == previous { round.swapAt(0, 1) }
    queue = round
    position = 0
  }
}
