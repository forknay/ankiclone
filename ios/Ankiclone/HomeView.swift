import SchedulerCore
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct HomeView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.scenePhase) private var scenePhase
  @Environment(SyncEngine.self) private var sync
  @Environment(AppRouter.self) private var router
  @Query(sort: \DeckRecord.createdAt, order: .reverse) private var decks: [DeckRecord]
  @Query private var cards: [CardRecord]
  @Query(sort: \LessonRecord.date, order: .reverse) private var lessons: [LessonRecord]
  @State private var now = Date()
  @State private var showingSettings = false
  @State private var studyingAll = false
  @State private var activeSince: Date?
  @AppStorage(Stats.revealsKey) private var reveals = 0
  @AppStorage(Stats.secondsKey) private var secondsInApp = 0.0
  @Query(filter: #Predicate<NoteRecord> { $0.deckID == "master" }) private var masterNotes: [NoteRecord]

  private var countsByDeck: [String: QueueCounts] {
    let queue = cards.map { ($0.deckID, $0.queueCard) }
    let everything = StudyQueue.available(queue.map(\.1), now: now)
    let open = Set(everything.map(\.id))
    return Dictionary(grouping: queue, by: \.0).mapValues { pairs in
      StudyQueue.counts(pairs.map(\.1).filter { open.contains($0.id) }, now: now)
    }
  }

  var body: some View {
    let counts = countsByDeck
    let total = counts.values.reduce(0) { $0 + $1.total }
    NavigationStack {
      List {
        if let lesson = lessons.first {
          Section("Latest lesson") {
            NavigationLink(value: lesson.date) {
              VStack(alignment: .leading, spacing: 4) {
                Text(lesson.title).font(.hanzi(18))
                Text(lesson.date).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }

        Section {
          Button {
            studyingAll = true
          } label: {
            Label(total == 0 ? "Nothing due" : "Study all \(total) cards", systemImage: "play.fill")
              .font(.headline)
          }
          .disabled(total == 0)
        }

        Section("Progress") {
          NavigationLink {
            CharactersView()
          } label: {
            LabeledContent("Characters", value: "\(masterNotes.count)")
          }
          LabeledContent("Cards reviewed", value: reveals.formatted())
          TimelineView(.everyMinute) { context in
            // The timeline's date is rounded down to the minute, so it can fall before activeSince.
            let current = activeSince.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            LabeledContent("Time in app", value: Stats.formatTime(secondsInApp + current))
          }
        }

        Section("Decks") {
          if decks.isEmpty {
            Text(emptyMessage).foregroundStyle(.secondary)
          }
          ForEach(decks) { deck in
            NavigationLink {
              DeckView(deck: deck)
            } label: {
              HStack {
                Text(deck.name)
                Spacer()
                CountBadges(counts: counts[deck.id] ?? QueueCounts())
              }
            }
          }
        }

        if lessons.count > 1 {
          Section("Earlier lessons") {
            ForEach(lessons.dropFirst()) { lesson in
              NavigationLink(value: lesson.date) {
                Text(lesson.title).font(.hanzi(16))
              }
            }
          }
        }

        if case .offline(let reason) = sync.status {
          Section {
            Label("Offline. Reviews are saved and will sync later. (\(reason))", systemImage: "wifi.slash")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Flashcards")
      .navigationDestination(for: String.self) { date in
        if let lesson = lessons.first(where: { $0.date == date }) { LessonView(lesson: lesson) }
      }
      .navigationDestination(item: Bindable(router).lessonDate) { date in
        if let lesson = lessons.first(where: { $0.date == date }) { LessonView(lesson: lesson) }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Settings", systemImage: "gearshape") { showingSettings = true }
        }
      }
      .refreshable { await refresh() }
      .sheet(isPresented: $showingSettings, onDismiss: { Task { await refresh() } }) { SettingsView() }
      .fullScreenCover(isPresented: $studyingAll, onDismiss: { Task { await refresh() } }) {
        ReviewView(deckID: nil)
      }
    }
    .task {
      if !AppSettings.isConfigured { showingSettings = true }
      await refresh()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await refresh() } }
    }
    // Counts only time with the app on screen.
    .onChange(of: scenePhase, initial: true) { _, phase in
      if phase == .active {
        activeSince = activeSince ?? Date()
      } else if let start = activeSince {
        Stats.addTime(Date().timeIntervalSince(start))
        activeSince = nil
      }
    }
  }

  private var emptyMessage: String {
    switch sync.status {
    case .syncing: "Downloading your cards…"
    case .notConfigured: "Add your server in Settings to get started."
    default: "No decks yet. Pull down to refresh."
    }
  }

  private func refresh() async {
    await sync.sync(context)
    now = Date()
    Stats.backfillReveals(from: cards)
    guard AppSettings.isConfigured else { return }
    let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    if granted { UIApplication.shared.registerForRemoteNotifications() }
  }
}

struct CountBadges: View {
  let counts: QueueCounts

  var body: some View {
    HStack(spacing: 10) {
      badge(counts.overdue, .red, "overdue")
      badge(counts.learning, .orange, "learning")
      badge(counts.fresh, .blue, "new")
    }
    .font(.subheadline.monospacedDigit().weight(.semibold))
  }

  private func badge(_ value: Int, _ color: Color, _ label: String) -> some View {
    Text("\(value)")
      .foregroundStyle(value == 0 ? Color.secondary.opacity(0.5) : color)
      .accessibilityLabel("\(value) \(label)")
  }
}

struct DeckView: View {
  @Environment(\.modelContext) private var context
  @Environment(SyncEngine.self) private var sync
  @Bindable var deck: DeckRecord
  @Query private var cards: [CardRecord]
  @State private var studying = false

  init(deck: DeckRecord) {
    self.deck = deck
    let id = deck.id
    _cards = Query(filter: #Predicate<CardRecord> { $0.deckID == id })
  }

  var body: some View {
    let counts = StudyQueue.counts(cards.map(\.queueCard), now: Date())
    List {
      Section {
        LabeledContent("Overdue") { Text("\(counts.overdue)").foregroundStyle(.red) }
        LabeledContent("Learning") { Text("\(counts.learning)").foregroundStyle(.orange) }
        LabeledContent("New") { Text("\(counts.fresh)").foregroundStyle(.blue) }
        LabeledContent("Total cards", value: "\(cards.count)")
      }
      Section {
        Button("Study \(counts.total) cards") { studying = true }.disabled(counts.total == 0)
      }
    }
    .navigationTitle(deck.name)
    .fullScreenCover(isPresented: $studying, onDismiss: { Task { await sync.sync(context) } }) {
      ReviewView(deckID: deck.id)
    }
  }
}

struct LessonView: View {
  let lesson: LessonRecord

  private var body_: LessonBody? {
    try? JSONDecoder().decode(LessonBody.self, from: Data(lesson.body.utf8))
  }

  var body: some View {
    List {
      if let content = body_ {
        Section { Text(content.intro) }
        ForEach(content.characters, id: \.hanzi) { character in
          Section {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text(character.hanzi).font(.hanzi(44))
              VStack(alignment: .leading) {
                Text(character.pinyin).font(.title3)
                Text(character.english).foregroundStyle(.secondary)
              }
            }
            ForEach(character.uses, id: \.self) { EntryRow(entry: $0) }
          }
        }
        if !content.words.isEmpty {
          Section("New words") {
            ForEach(content.words, id: \.self) { EntryRow(entry: $0) }
          }
        }
        if content.sentenceCount > 0 {
          Section { Text("This week's reading deck has \(content.sentenceCount) sentences, unlocking a few each day.") }
        }
        if let groups = content.lookalikes, !groups.isEmpty {
          Section("New look-alike sets") {
            Text(groups.joined(separator: "   ")).font(.hanzi(24))
          }
        }
      } else {
        Text("This lesson couldn't be displayed.")
      }
    }
    .navigationTitle(lesson.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct EntryRow: View {
  let entry: LessonEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(entry.hanzi).font(.hanzi(20))
      Text(entry.pinyin).font(.subheadline)
      Text(entry.english).font(.subheadline).foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }
}

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var url = AppSettings.serverURL
  @State private var token = AppSettings.token

  var body: some View {
    NavigationStack {
      Form {
        Section("Server address") {
          TextField("https://…", text: $url)
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        Section {
          SecureField("API token", text: $token)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
        } header: {
          Text("API token")
        } footer: {
          Text("Stored in this iPhone's Keychain.")
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            AppSettings.serverURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            AppSettings.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            dismiss()
          }
        }
      }
    }
  }
}
