import XCTest
@testable import OnTime

@MainActor
final class URLHandlerTests: XCTestCase {
  private var model: OnTimeModel!

  override func setUp() {
    super.setUp()
    model = OnTimeModel()
  }

  override func tearDown() {
    model.stop()
    model = nil
    super.tearDown()
  }

  func testParseStartDuration() {
    let url = URL(string: "ontime://start?duration=25m")!
    let action = OnTimeURLHandler.parse(url)
    XCTAssertEqual(action?.command, .start)
    XCTAssertEqual(action?.duration ?? 0, 25 * 60, accuracy: 0.1)
  }

  func testParseAliases() {
    XCTAssertEqual(
      OnTimeURLHandler.parse(URL(string: "ontime://start?d=10")!)?.duration ?? 0, 600, accuracy: 0.1)
    XCTAssertEqual(OnTimeURLHandler.parse(URL(string: "ontime://add?t=5m")!)?.command, .add)
    XCTAssertEqual(OnTimeURLHandler.parse(URL(string: "ontime://clear")!)?.command, .clear)
  }

  func testPerformStartAndAdd() {
    let start = OnTimeURLHandler.parse(URL(string: "ontime://start?duration=2m")!)!
    XCTAssertTrue(OnTimeURLHandler.perform(start, on: model))
    XCTAssertTrue(model.isRunning)
    XCTAssertEqual(model.remaining, 120, accuracy: 1.5)

    let add = OnTimeURLHandler.parse(URL(string: "ontime://add?duration=1m")!)!
    XCTAssertTrue(OnTimeURLHandler.perform(add, on: model))
    XCTAssertEqual(model.remaining, 180, accuracy: 1.5)
  }

  func testPerformPomodoroSkipStop() {
    XCTAssertTrue(
      OnTimeURLHandler.perform(
        OnTimeURLHandler.parse(URL(string: "ontime://pomodoro")!)!, on: model))
    XCTAssertNotNil(model.pomodoroSession)
    XCTAssertTrue(
      OnTimeURLHandler.perform(OnTimeURLHandler.parse(URL(string: "ontime://skip")!)!, on: model))
    XCTAssertTrue(
      OnTimeURLHandler.perform(OnTimeURLHandler.parse(URL(string: "ontime://stop")!)!, on: model))
    XCTAssertFalse(model.isRunning)
  }

  func testRejectUnknownScheme() {
    XCTAssertNil(OnTimeURLHandler.parse(URL(string: "notontime://startstop")!))
  }
}

final class LoggerFocusTests: XCTestCase {
  func testTodaysFocusSummaryReadsFocusSeconds() throws {
    let temp = FileManager.default.temporaryDirectory
      .appendingPathComponent("OnTime-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let file = temp.appendingPathComponent("sessions.jsonl")
    let logger = OnTimeLogger(fileURL: file)
    logger.log(
      event: "phase_transition",
      fields: [
        "from": "work",
        "to": "shortBreak",
        "focus_seconds": "1500",
        "duration": "1500",
      ]
    )

    let exp = expectation(description: "log flush")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { exp.fulfill() }
    wait(for: [exp], timeout: 1.0)

    let seconds = logger.todaysFocusSeconds()
    XCTAssertEqual(seconds, 1500, accuracy: 1)
    XCTAssertTrue(logger.todaysFocusSummary().contains("Focus"))
  }
}
