import XCTest
@testable import OnTime

final class DisplayPrecisionTests: XCTestCase {
  private let precisionKey = OnTimeSettingsKeys.displayPrecision
  private let legacyKey = OnTimeSettingsKeys.stopwatchPrecision

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: precisionKey)
    UserDefaults.standard.removeObject(forKey: legacyKey)
    super.tearDown()
  }

  func testPrecisionDefaultsAndSettingsKey() {
    XCTAssertEqual(DisplayPrecision.default, .seconds)
    XCTAssertEqual(OnTimeSettingsKeys.displayPrecision, "displayPrecision")
    XCTAssertEqual(OnTimeSettingsKeys.stopwatchPrecision, "stopwatchPrecision")
    XCTAssertEqual(DisplayPrecision.allCases.map(\.rawValue), ["seconds", "tenths"])
    XCTAssertEqual(DisplayPrecision.current(), .seconds)

    UserDefaults.standard.set(DisplayPrecision.tenths.rawValue, forKey: precisionKey)
    XCTAssertEqual(DisplayPrecision.current(), .tenths)

    UserDefaults.standard.set("not-a-precision", forKey: precisionKey)
    XCTAssertEqual(DisplayPrecision.current(), .seconds)
  }

  func testMigratesLegacyStopwatchPrecisionKey() {
    UserDefaults.standard.set(DisplayPrecision.tenths.rawValue, forKey: legacyKey)
    XCTAssertEqual(DisplayPrecision.current(), .tenths)

    DisplayPrecision.migrateIfNeeded()
    XCTAssertEqual(
      UserDefaults.standard.string(forKey: precisionKey),
      DisplayPrecision.tenths.rawValue
    )
    XCTAssertEqual(DisplayPrecision.current(), .tenths)

    // New key wins over a conflicting legacy value.
    UserDefaults.standard.set(DisplayPrecision.seconds.rawValue, forKey: precisionKey)
    UserDefaults.standard.set(DisplayPrecision.tenths.rawValue, forKey: legacyKey)
    XCTAssertEqual(DisplayPrecision.current(), .seconds)
  }

  func testMigrateDoesNotOverwriteExistingDisplayPrecision() {
    UserDefaults.standard.set(DisplayPrecision.seconds.rawValue, forKey: precisionKey)
    UserDefaults.standard.set(DisplayPrecision.tenths.rawValue, forKey: legacyKey)
    DisplayPrecision.migrateIfNeeded()
    XCTAssertEqual(
      UserDefaults.standard.string(forKey: precisionKey),
      DisplayPrecision.seconds.rawValue
    )
  }

  func testMigratesHundredthsToTenths() {
    UserDefaults.standard.set("hundredths", forKey: precisionKey)
    XCTAssertEqual(DisplayPrecision.current(), .tenths)

    DisplayPrecision.migrateIfNeeded()
    XCTAssertEqual(
      UserDefaults.standard.string(forKey: precisionKey),
      DisplayPrecision.tenths.rawValue
    )
    XCTAssertEqual(DisplayPrecision.current(), .tenths)
  }

  func testMigratesLegacyHundredthsStopwatchPrecision() {
    UserDefaults.standard.set("hundredths", forKey: legacyKey)
    DisplayPrecision.migrateIfNeeded()
    XCTAssertEqual(
      UserDefaults.standard.string(forKey: precisionKey),
      DisplayPrecision.tenths.rawValue
    )
    XCTAssertEqual(
      UserDefaults.standard.string(forKey: legacyKey),
      DisplayPrecision.tenths.rawValue
    )
  }

  func testFormatElapsedExamples() {
    XCTAssertEqual(
      DisplayPrecision.formatElapsed(elapsed: 70.0, precision: .seconds),
      "01:10"
    )
    XCTAssertEqual(
      DisplayPrecision.formatElapsed(elapsed: 70.9, precision: .tenths),
      "01:10.9"
    )
  }

  func testFormatElapsedTruncatesNotRounds() {
    XCTAssertEqual(
      DisplayPrecision.formatElapsed(elapsed: 70.99, precision: .tenths),
      "01:10.9"
    )
    XCTAssertEqual(
      DisplayPrecision.formatElapsed(elapsed: 59.9, precision: .seconds),
      "00:59"
    )
  }

  func testFormatElapsedIncludesHours() {
    XCTAssertEqual(
      DisplayPrecision.formatElapsed(elapsed: 3661.45, precision: .tenths),
      "01:01:01.4"
    )
  }

  func testFormatRemainingUsesCeilSemantics() {
    XCTAssertEqual(
      DisplayPrecision.formatRemaining(remaining: 70.0, precision: .seconds),
      "01:10"
    )
    XCTAssertEqual(
      DisplayPrecision.formatRemaining(remaining: 70.1, precision: .seconds),
      "01:11"
    )
    XCTAssertEqual(
      DisplayPrecision.formatRemaining(remaining: 70.15, precision: .tenths),
      "01:10.2"
    )
    XCTAssertEqual(
      DisplayPrecision.formatRemaining(remaining: 70.0, precision: .tenths),
      "01:10.0"
    )
    // Just above zero still shows a non-zero fractional quantum; true zero shows .0.
    XCTAssertEqual(
      DisplayPrecision.formatRemaining(remaining: 0.01, precision: .tenths),
      "00:00.1"
    )
    XCTAssertEqual(
      DisplayPrecision.formatRemaining(remaining: 0, precision: .tenths),
      "00:00.0"
    )
  }

  func testFormatRemainingIncludesHours() {
    XCTAssertEqual(
      DisplayPrecision.formatRemaining(remaining: 3661.45, precision: .tenths),
      "01:01:01.5"
    )
  }

  func testCountdownFormattingUsesPrecision() {
    UserDefaults.standard.set(DisplayPrecision.tenths.rawValue, forKey: precisionKey)
    let model = OnTimeModel()
    model.start(duration: 70)
    XCTAssertEqual(model.mode, .countdown)
    XCTAssertEqual(model.formattedRemaining, "01:10.0")
    model.pause()
    model.remaining = 70.15
    XCTAssertEqual(model.formattedRemaining, "01:10.2")
    model.stop()
  }

  func testPomodoroRemainingUsesPrecision() {
    UserDefaults.standard.set(DisplayPrecision.tenths.rawValue, forKey: precisionKey)
    let model = OnTimeModel()
    model.startPomodoro()
    XCTAssertEqual(model.mode, .countdown)
    XCTAssertNotNil(model.pomodoroSession)
    model.pause()
    model.remaining = 25.4
    XCTAssertEqual(model.formattedRemaining, "00:25.4")
    model.stop()
  }

  func testModelStopwatchUsesPrecision() {
    let model = OnTimeModel()
    model.startStopwatch()
    model.pause()
    model.elapsed = 70.9

    UserDefaults.standard.set(DisplayPrecision.tenths.rawValue, forKey: precisionKey)
    XCTAssertEqual(model.formattedRemaining, "01:10.9")

    UserDefaults.standard.set(DisplayPrecision.seconds.rawValue, forKey: precisionKey)
    XCTAssertEqual(model.formattedRemaining, "01:10")
    model.stop()
  }

  func testTickIntervalIsSubSecondForFractionalPrecision() {
    XCTAssertEqual(DisplayPrecision.seconds.tickInterval, 0.25, accuracy: 0.0001)
    XCTAssertEqual(DisplayPrecision.tenths.tickInterval, 0.05, accuracy: 0.0001)
  }

  func testCountdownDisplayUnitMatchesCeilFormatting() {
    let precision = DisplayPrecision.tenths
    XCTAssertEqual(precision.displayUnit(forRemaining: 70.15), 702)
    XCTAssertEqual(precision.displayUnit(forRemaining: 0.01), 1)
    XCTAssertEqual(precision.displayUnit(forRemaining: 0), 0)
    XCTAssertEqual(DisplayPrecision.seconds.displayUnit(forRemaining: 70.1), 71)
  }

  func testFractionalDigitWidthsAreStable() {
    let font = MenuBarFontStyle.systemMonospaced.menuBarFont(size: 13)
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let a = ("01:10.0" as NSString).size(withAttributes: attributes).width
    let b = ("01:10.9" as NSString).size(withAttributes: attributes).width
    XCTAssertEqual(a, b, accuracy: 0.5)
  }
}
