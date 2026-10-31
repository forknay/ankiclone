import XCTest

@testable import SchedulerCore

final class StudyLogicTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Toronto")!
    return calendar
  }

  private func card(
    _ id: String, note: String? = nil, _ phase: Phase = .review, dueIn: TimeInterval = -60,
    reviewedAgo: TimeInterval? = nil, held: Bool = false
  ) -> QueueCard {
    QueueCard(
      id: id, noteID: note ?? id, phase: phase, due: now.addingTimeInterval(dueIn),
      lastReview: reviewedAgo.map { now.addingTimeInterval(-$0) }, isHeld: held)
  }

  func testHeldCardsAreHidden() {
    XCTAssertEqual(StudyQueue.counts([card("a", .new, held: true)], now: now, calendar: calendar).total, 0)
  }

  func testSiblingIsBuriedForTheRestOfTheStudyDayOnly() {
    let sibling = card("en", note: "n", .new)
    let reviewedNow = card("zh", note: "n", .review, dueIn: 86_400, reviewedAgo: 60)
    XCTAssertNil(StudyQueue.next([reviewedNow, sibling], now: now, calendar: calendar))
    let reviewedDaysAgo = card("zh", note: "n", .review, dueIn: 86_400, reviewedAgo: 3 * 86_400)
    XCTAssertEqual(StudyQueue.next([reviewedDaysAgo, sibling], now: now, calendar: calendar)?.id, "en")
  }

  func testLearningCardIsNotBuriedBySibling() {
    let learning = card("zh", note: "n", .learning, reviewedAgo: 60)
    let other = card("en", note: "n", .learning, reviewedAgo: 30)
    XCTAssertEqual(StudyQueue.available([learning, other], now: now, calendar: calendar).count, 2)
  }

  func testOrderIsLearningThenMostOverdueThenNew() {
    let cards = [
      card("new", .new, dueIn: -9000),
      card("review-recent", .review, dueIn: -100),
      card("review-old", .review, dueIn: -5000),
      card("learning", .learning, dueIn: -1),
    ]
    XCTAssertEqual(StudyQueue.next(cards, now: now, calendar: calendar)?.id, "learning")
    XCTAssertEqual(StudyQueue.next(Array(cards.dropLast()), now: now, calendar: calendar)?.id, "review-old")
    XCTAssertEqual(StudyQueue.next([cards[0]], now: now, calendar: calendar)?.id, "new")
  }

  func testLearnAheadOnlyWhenNothingElseIsDue() {
    let soon = card("soon", .learning, dueIn: 300)
    let later = card("later", .learning, dueIn: 3600)
    XCTAssertEqual(StudyQueue.next([soon, later], now: now, calendar: calendar)?.id, "soon")
    XCTAssertEqual(StudyQueue.next([soon, card("due")], now: now, calendar: calendar)?.id, "due")
    XCTAssertNil(StudyQueue.next([later], now: now, calendar: calendar))
    XCTAssertEqual(StudyQueue.counts([soon], now: now, calendar: calendar).total, 0)
  }

  func testPromptBlanksTheAnswer() {
    XCTAssertEqual(
      CardPrompt.english("to practise (as in 学习 study)", hanzi: "习", pinyin: "xí"),
      "to practise (as in 学＿ study)")
    XCTAssertEqual(
      CardPrompt.english("convenient (biàn); pián in 便宜 cheap", hanzi: "便", pinyin: "biàn"),
      "convenient (＿); pián in ＿宜 cheap")
    XCTAssertEqual(CardPrompt.english("How are you?", hanzi: "你好吗？", pinyin: "nǐ hǎo ma"), "How are you?")
  }

  private func results(_ typed: String, _ answer: String) -> [SyllableResult] {
    PinyinCheck.check(typed: typed, answer: answer).map(\.result)
  }

  func testPinyinAcceptsMarksNumbersAndNoSpaces() {
    for typed in ["nǐ hǎo ma", "ni3 hao3 ma", "ni3hao3ma", "ni3 hao3 ma5", "NI3 HAO3 MA", "nǐhǎoma"] {
      XCTAssertEqual(results(typed, "nǐ hǎo ma"), [.correct, .correct, .correct], typed)
    }
  }

  func testPinyinReportsToneProblems() {
    XCTAssertEqual(results("ni2 hao3 ma", "nǐ hǎo ma"), [.wrongTone, .correct, .correct])
    XCTAssertEqual(results("ni hao ma", "nǐ hǎo ma"), [.missingTone, .missingTone, .correct])
    XCTAssertEqual(results("nihaoma", "nǐ hǎo ma"), [.missingTone, .missingTone, .correct])
    XCTAssertEqual(results("ma1", "ma"), [.wrongTone])
  }

  func testPinyinReportsWrongSyllables() {
    XCTAssertEqual(results("wo3 hao3", "nǐ hǎo"), [.wrong, .correct])
    XCTAssertEqual(results("ni3", "nǐ hǎo"), [.correct, .wrong])
    XCTAssertEqual(results("", "nǐ"), [.wrong])
    XCTAssertEqual(results("wohao", "nǐ hǎo"), [.wrong, .wrong])
  }

  func testPinyinHandlesUmlaut() {
    for typed in ["nǚ", "nv3", "nü3"] { XCTAssertEqual(results(typed, "nǚ"), [.correct], typed) }
  }

  func testPinyinWithPunctuationAroundIt() {
    XCTAssertEqual(results("wo3, xue2.", "wǒ xué"), [.correct, .correct])
  }
}
