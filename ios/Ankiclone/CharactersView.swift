import SwiftData
import SwiftUI

/// Every character and word in the master deck, as a grid to browse or search.
struct CharactersView: View {
  @Query(filter: #Predicate<NoteRecord> { $0.deckID == "master" }) private var notes: [NoteRecord]
  @Query(filter: #Predicate<CardRecord> { $0.deckID == "master" && $0.directionRaw == "zh_en" }) private var cards: [CardRecord]
  @State private var search = ""

  private var shown: [NoteRecord] {
    let query = search.trimmingCharacters(in: .whitespaces)
    let matching = query.isEmpty
      ? notes
      : notes.filter {
        $0.hanzi.contains(query)
          || $0.pinyin.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
          || $0.english.localizedCaseInsensitiveContains(query)
      }
    return matching.sorted { $0.pinyin.compare($1.pinyin, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedAscending }
  }

  var body: some View {
    let unreviewed = Set(cards.filter { $0.reps == 0 }.map(\.noteID))
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
        ForEach(shown) { note in
          NavigationLink {
            CharacterDetailView(note: note)
          } label: {
            VStack(spacing: 2) {
              Text(note.hanzi).font(.hanzi(note.hanzi.count > 2 ? 18 : 30)).lineLimit(1).minimumScaleFactor(0.5)
              Text(note.pinyin).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(.fill.tertiary, in: .rect(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
              if unreviewed.contains(note.id) {
                Circle().fill(.blue).frame(width: 7, height: 7).padding(6).accessibilityLabel("new")
              }
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding()
      if shown.isEmpty {
        Text(notes.isEmpty ? "No characters yet." : "No matches.").foregroundStyle(.secondary).padding()
      }
    }
    .searchable(text: $search, prompt: "Character, pinyin or English")
    .navigationTitle("Characters (\(notes.count))")
  }
}

struct CharacterDetailView: View {
  let note: NoteRecord
  @Query private var allNotes: [NoteRecord]
  @Query private var lessons: [LessonRecord]
  @Query private var cards: [CardRecord]

  init(note: NoteRecord) {
    self.note = note
    let id = note.id
    _cards = Query(filter: #Predicate<CardRecord> { $0.noteID == id }, sort: \.directionRaw, order: .reverse)
  }

  /// Uses written for this character in the lesson that introduced it.
  private var lessonUses: [LessonEntry] {
    lessons.flatMap { lesson -> [LessonEntry] in
      guard let body = try? JSONDecoder().decode(LessonBody.self, from: Data(lesson.body.utf8)) else { return [] }
      return body.characters.filter { $0.hanzi == note.hanzi }.flatMap(\.uses)
    }
  }

  /// Other cards containing this character, words before sentences.
  private var related: [NoteRecord] {
    allNotes
      .filter { $0.id != note.id && $0.hanzi.contains(note.hanzi) }
      .sorted { ($0.kind == "sentence" ? 1 : 0, $0.hanzi.count) < ($1.kind == "sentence" ? 1 : 0, $1.hanzi.count) }
      .prefix(12)
      .map { $0 }
  }

  var body: some View {
    List {
      Section {
        VStack(spacing: 8) {
          Text(note.hanzi).font(.hanzi(72)).textSelection(.enabled)
          Text(note.pinyin).font(.title3)
          Text(note.english).font(.title3).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      }

      let uses = lessonUses
      if !uses.isEmpty {
        Section("Common uses") {
          ForEach(uses, id: \.self) { EntryRow(entry: $0) }
        }
      }

      let others = related
      if !others.isEmpty {
        Section("In your cards") {
          ForEach(others) { EntryRow(entry: LessonEntry(hanzi: $0.hanzi, pinyin: $0.pinyin, english: $0.english)) }
        }
      }

      Section("Reviews") {
        ForEach(cards) { card in
          LabeledContent(card.direction == .zhToEn ? "Reading" : "Picturing it") {
            Text(summary(card))
          }
        }
      }
    }
    .navigationTitle(note.hanzi)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func summary(_ card: CardRecord) -> String {
    if card.heldBy != nil || card.reps == 0 { return "Not studied yet" }
    let next = card.due <= Date() ? "due now" : "next \(card.due.formatted(.relative(presentation: .named)))"
    let agains = card.agains > 0 ? " · Again \(card.agains)×" : ""
    return "\(next)\(agains)"
  }
}
