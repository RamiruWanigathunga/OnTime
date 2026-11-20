import AppKit
import XCTest
@testable import OnTime

final class MenuBarStyleTests: XCTestCase {
  func testMenuBarStyleDefaultsAndHoverReveal() {
    XCTAssertEqual(MenuBarStyle.default, .classic)
    XCTAssertTrue(MenuBarStyle.ringOnly.revealsTimeOnHover)
    XCTAssertTrue(MenuBarStyle.iconOnly.revealsTimeOnHover)
    XCTAssertFalse(MenuBarStyle.classic.revealsTimeOnHover)
    XCTAssertEqual(MenuBarStyle.allCases.count, 4)
    XCTAssertNil(MenuBarStyle(rawValue: "compactBadge"))
  }

  func testRingStylesFallBackForStopwatch() {
    XCTAssertEqual(MenuBarStyle.ringAndTime.styleForStopwatch(), .classic)
    XCTAssertEqual(MenuBarStyle.ringOnly.styleForStopwatch(), .iconOnly)
    XCTAssertEqual(MenuBarStyle.classic.styleForStopwatch(), .classic)
    XCTAssertEqual(MenuBarStyle.iconOnly.styleForStopwatch(), .iconOnly)
  }

  func testMenuBarFontStylesResolveFonts() {
    for style in MenuBarFontStyle.allCases {
      let font = style.menuBarFont(size: 13)
      XCTAssertGreaterThan(font.pointSize, 0)
    }
    XCTAssertEqual(MenuBarFontStyle.default, .systemMonospaced)
  }

  func testMenuBarFontsUseStableDigitWidths() {
    let size: CGFloat = 13
    let narrow = "11:11"
    let wide = "55:58"
    let pomodoroNarrow = "W 1/4 11:11"
    let pomodoroWide = "W 1/4 55:58"

    for style in MenuBarFontStyle.allCases {
      let font = style.menuBarFont(size: size)
      let attributes: [NSAttributedString.Key: Any] = [.font: font]

      let narrowWidth = (narrow as NSString).size(withAttributes: attributes).width
      let wideWidth = (wide as NSString).size(withAttributes: attributes).width
      XCTAssertEqual(
        narrowWidth,
        wideWidth,
        accuracy: 0.5,
        "\(style.rawValue): timer digit widths should match (got \(narrowWidth) vs \(wideWidth))"
      )

      let pomodoroNarrowWidth = (pomodoroNarrow as NSString).size(withAttributes: attributes).width
      let pomodoroWideWidth = (pomodoroWide as NSString).size(withAttributes: attributes).width
      XCTAssertEqual(
        pomodoroNarrowWidth,
        pomodoroWideWidth,
        accuracy: 0.5,
        "\(style.rawValue): pomodoro prefix + timer digit widths should match (got \(pomodoroNarrowWidth) vs \(pomodoroWideWidth))"
      )
    }
  }

  func testRingImageIsTemplate() {
    let image = MenuBarRingImage.make(progress: 0.4, size: NSSize(width: 18, height: 18))
    XCTAssertTrue(image.isTemplate)
    XCTAssertEqual(image.size.width, 18, accuracy: 0.1)
  }

  func testMenuBarIconDefaultsAndSymbols() {
    XCTAssertEqual(MenuBarIcon.default, .gaugeRange)
    XCTAssertEqual(MenuBarIcon.allCases.count, 9)
    XCTAssertEqual(OnTimeSettingsKeys.menuBarIcon, "menuBarIcon")

    let expectedSymbols: [(MenuBarIcon, String)] = [
      (.timer, "timer"),
      (.clock, "clock"),
      (.deskClock, "deskclock"),
      (.graduationCap, "graduationcap"),
      (.hourglassBottomHalfFilled, "hourglass.bottomhalf.filled"),
      (.rosette, "rosette"),
      (.stopwatch, "stopwatch"),
      (.hourglass, "hourglass"),
      (.gaugeRange, "gauge.range.33to100.dotted.with.needle"),
    ]
    for (icon, symbol) in expectedSymbols {
      XCTAssertEqual(icon.systemSymbolName, symbol)
      XCTAssertFalse(icon.displayName.lowercased().contains("sf"))
    }
  }

  func testMenuBarIconTemplateImages() {
    let size = NSSize(width: 18, height: 18)
    for icon in MenuBarIcon.allCases {
      let image = icon.templateImage(size: size)
      XCTAssertTrue(image.isTemplate, "\(icon.rawValue) should be template")
      XCTAssertEqual(image.size.width, 18, accuracy: 0.1)
      XCTAssertEqual(image.size.height, 18, accuracy: 0.1)
    }
  }

  func testMenuBarIconCurrentFallsBackToDefault() {
    let suiteName = "MenuBarIconTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    XCTAssertEqual(MenuBarIcon.current(defaults: defaults), .gaugeRange)
    defaults.set("not-a-real-icon", forKey: OnTimeSettingsKeys.menuBarIcon)
    XCTAssertEqual(MenuBarIcon.current(defaults: defaults), .gaugeRange)
    defaults.set(MenuBarIcon.clock.rawValue, forKey: OnTimeSettingsKeys.menuBarIcon)
    XCTAssertEqual(MenuBarIcon.current(defaults: defaults), .clock)
  }
}
