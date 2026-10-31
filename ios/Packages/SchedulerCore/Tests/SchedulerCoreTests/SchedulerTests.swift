import XCTest

@testable import SchedulerCore

final class SchedulerTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Toronto")!
    return calendar
  }
  private var scheduler: FSRSScheduler { FSRSScheduler(calendar: calendar) }
  private var start: Date { date(2026, 11, 2, hour: 9) }

  private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
  }

  private func days(_ state: SchedulingState, from now: Date) -> Double {
    state.due.timeIntervalSince(now) / 86_400
  }

  func testNewCardGradesUseLearningSteps() {
    let previews = scheduler.previews(SchedulingState(due: start), at: start, cardID: "a")
    XCTAssertEqual(previews[.again]!.due.timeIntervalSince(start), 60)
    XCTAssertEqual(previews[.hard]!.due.timeIntervalSince(start), 300)
    XCTAssertEqual(previews[.good]!.due.timeIntervalSince(start), 600)
    XCTAssertEqual(previews[.easy]!.phase, .review)
    XCTAssertGreaterThanOrEqual(days(previews[.easy]!, from: start), 7)
  }

  func testSecondEasyPushesFurtherThanFirst() {
    let first = scheduler.next(SchedulingState(due: start), grade: .easy, at: start, cardID: "a")
    let second = scheduler.next(first, grade: .easy, at: first.due, cardID: "a")
    let third = scheduler.next(second, grade: .easy, at: second.due, cardID: "a")
    XCTAssertGreaterThan(second.scheduledDays, first.scheduledDays * 1.5)
    XCTAssertGreaterThan(third.scheduledDays, second.scheduledDays)
  }

  func testIntervalsNeverExceedTheCap() {
    var state = SchedulingState(due: start)
    for _ in 0..<10 {
      state = scheduler.next(state, grade: .easy, at: state.due, cardID: "a")
      XCTAssertLessThanOrEqual(state.scheduledDays, FSRSScheduler.maximumIntervalDays)
    }
    // Fuzz can land a capped card a few days short, but it stays close to the cap.
    XCTAssertGreaterThanOrEqual(state.scheduledDays, FSRSScheduler.maximumIntervalDays * 0.95)
  }

  func testReviewGradesAreOrdered() {
    let first = scheduler.next(SchedulingState(due: start), grade: .easy, at: start, cardID: "a")
    let previews = scheduler.previews(first, at: first.due, cardID: "a")
    XCTAssertLessThan(previews[.again]!.due, previews[.hard]!.due)
    XCTAssertLessThan(previews[.hard]!.due, previews[.good]!.due)
    XCTAssertLessThan(previews[.good]!.due, previews[.easy]!.due)
  }

  func testLapseGoesToRelearningThenRecoversShorter() {
    var state = scheduler.next(SchedulingState(due: start), grade: .easy, at: start, cardID: "a")
    state = scheduler.next(state, grade: .good, at: state.due, cardID: "a")
    let before = state
    let lapsed = scheduler.next(state, grade: .again, at: state.due, cardID: "a")
    XCTAssertEqual(lapsed.phase, .relearning)
    XCTAssertEqual(lapsed.lapses, 1)
    XCTAssertEqual(lapsed.due.timeIntervalSince(state.due), 300)
    let recovered = scheduler.next(lapsed, grade: .good, at: lapsed.due, cardID: "a")
    XCTAssertEqual(recovered.phase, .review)
    XCTAssertLessThan(recovered.scheduledDays, before.scheduledDays)
  }

  func testGraduatingFromLearningTakesAtLeastADay() {
    let learning = scheduler.next(SchedulingState(due: start), grade: .good, at: start, cardID: "a")
    let graduated = scheduler.next(learning, grade: .good, at: learning.due, cardID: "a")
    XCTAssertEqual(graduated.phase, .review)
    XCTAssertGreaterThanOrEqual(graduated.scheduledDays, 1)
  }

  func testStudyDayRollsOverAtFourAM() {
    let lateNight = date(2026, 11, 3, hour: 2)
    XCTAssertEqual(StudyDay.start(of: lateNight, calendar: calendar), date(2026, 11, 2, hour: 4))
    XCTAssertEqual(StudyDay.start(of: date(2026, 11, 3, hour: 5), calendar: calendar), date(2026, 11, 3, hour: 4))
  }

  func testLongIntervalsLandOnStudyDayBoundary() {
    let lateNight = date(2026, 11, 3, hour: 2)
    let state = scheduler.next(SchedulingState(due: lateNight), grade: .easy, at: lateNight, cardID: "a")
    XCTAssertEqual(calendar.component(.hour, from: state.due), 4)
  }

  func testStudyDayBoundarySurvivesDaylightSaving() {
    let beforeChange = date(2026, 10, 31, hour: 12)
    XCTAssertEqual(
      StudyDay.start(of: beforeChange, calendar: calendar, addingDays: 2),
      date(2026, 11, 2, hour: 4)
    )
  }

  func testFuzzIsDeterministicAndBounded() {
    let results = (0..<200).map { Fuzz.apply(to: 100, cardID: "card-\($0)", reps: 3) }
    XCTAssertTrue(results.allSatisfy { (95...105).contains($0) })
    XCTAssertGreaterThan(Set(results).count, 3)
    XCTAssertEqual(Fuzz.apply(to: 100, cardID: "x", reps: 1), Fuzz.apply(to: 100, cardID: "x", reps: 1))
    XCTAssertEqual(Fuzz.apply(to: 2, cardID: "x", reps: 1), 2)
  }

  func testPreviewsMatchActualResult() {
    let previews = scheduler.previews(SchedulingState(due: start), at: start, cardID: "a")
    XCTAssertEqual(previews[.easy], scheduler.next(SchedulingState(due: start), grade: .easy, at: start, cardID: "a"))
  }

  func testIntervalLabels() {
    XCTAssertEqual(IntervalLabel.text(from: start, to: start.addingTimeInterval(600)), "10m")
    XCTAssertEqual(IntervalLabel.text(from: start, to: start.addingTimeInterval(86_400 * 3)), "3d")
    XCTAssertEqual(IntervalLabel.text(from: start, to: start.addingTimeInterval(86_400 * 64)), "2.1mo")
  }

  /// Not an assertion: prints what repeated Good and Easy actually look like.
  func testPrintSampleIntervals() {
    for grade in [Grade.good, .easy] {
      var state = SchedulingState(due: start)
      var line: [String] = []
      for _ in 0..<6 {
        let now = state.due
        state = scheduler.next(state, grade: grade, at: now, cardID: "sample")
        line.append(IntervalLabel.text(from: now, to: state.due))
      }
      print("\(grade.rawValue):", line.joined(separator: " -> "))
    }
  }
}
