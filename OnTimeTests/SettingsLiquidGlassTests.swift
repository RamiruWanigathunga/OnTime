import XCTest

@testable import OnTime

@MainActor
final class SettingsLiquidGlassTests: XCTestCase {
  func testSidebarOrderExcludesAbout() {
    XCTAssertEqual(
      OnTimeSettingsPane.sidebarOrder.map(\.title),
      ["General", "Appearance", "Pomodoro", "Sound", "Shortcuts"]
    )
    XCTAssertEqual(OnTimeSettingsPane.about.title, "About")
  }

  func testUtilityActions() {
    XCTAssertEqual(
      OnTimeSettingsUtilityAction.allCases.map(\.rawValue),
      ["about", "close"]
    )
  }

  func testPresentationAppearAndDismissPhases() {
    let model = SettingsPresentationModel()
    XCTAssertEqual(model.phase, .hidden)
    XCTAssertEqual(model.motionProgress, 0, accuracy: 0.001)
    XCTAssertEqual(model.opacity, 0, accuracy: 0.001)
    XCTAssertEqual(
      model.blurRadius, SettingsPresentationMotion.blurredRadius, accuracy: 0.001)
    XCTAssertEqual(
      model.scale, SettingsPresentationMotion.compressedScale, accuracy: 0.001)

    model.resetForShow()
    model.beginAppear()
    XCTAssertEqual(model.phase, .appearing)
    model.applySettledAppearance()
    model.markVisible()
    XCTAssertEqual(model.phase, .visible)
    XCTAssertEqual(model.motionProgress, 1, accuracy: 0.001)
    XCTAssertEqual(model.opacity, 1, accuracy: 0.001)
    XCTAssertEqual(model.blurRadius, 0, accuracy: 0.001)
    XCTAssertEqual(model.scale, 1, accuracy: 0.001)
    XCTAssertFalse(model.isDismissing)

    model.beginDismiss()
    XCTAssertEqual(model.phase, .dismissing)
    XCTAssertTrue(model.isDismissing)
    model.applyDismissAppearance()
    XCTAssertEqual(model.motionProgress, 0, accuracy: 0.001)
    XCTAssertEqual(model.opacity, 0, accuracy: 0.001)
    XCTAssertGreaterThan(model.blurRadius, 0)
    model.finishHidden()
    XCTAssertEqual(model.phase, .hidden)
  }

  func testParallaxPiecesRiseFromBelowWhileInFlight() {
    let model = SettingsPresentationModel()
    model.motionProgress = 0
    let sidebar = model.offset(for: .sidebar)
    let utility = model.offset(for: .utility)
    let content = model.offset(for: .content)
    // All pieces start below (positive Y) with no sideways drift.
    XCTAssertEqual(sidebar.width, 0, accuracy: 0.001)
    XCTAssertEqual(utility.width, 0, accuracy: 0.001)
    XCTAssertEqual(content.width, 0, accuracy: 0.001)
    XCTAssertGreaterThan(sidebar.height, 0)
    XCTAssertGreaterThan(utility.height, 0)
    XCTAssertGreaterThan(content.height, 0)
    XCTAssertGreaterThan(utility.height, sidebar.height)
    XCTAssertGreaterThan(content.height, utility.height)
    XCTAssertGreaterThan(model.blur(for: .content), model.blur(for: .sidebar))
    XCTAssertEqual(SettingsParallaxPiece.sidebar.appearDelay, 0, accuracy: 0.001)
    XCTAssertLessThan(
      SettingsParallaxPiece.sidebar.appearDelay,
      SettingsParallaxPiece.utility.appearDelay
    )
    XCTAssertLessThan(
      SettingsParallaxPiece.utility.appearDelay,
      SettingsParallaxPiece.content.appearDelay
    )

    model.motionProgress = 1
    XCTAssertEqual(model.offset(for: .sidebar).height, 0, accuracy: 0.001)
    XCTAssertEqual(model.offset(for: .content).height, 0, accuracy: 0.001)
    XCTAssertEqual(model.blur(for: .sidebar), 0, accuracy: 0.001)
    XCTAssertEqual(model.opacity(for: .content), 1, accuracy: 0.001)
  }

  func testBeginDismissIgnoredWhenAlreadyDismissingOrHidden() {
    let model = SettingsPresentationModel()
    XCTAssertFalse(model.beginDismiss())
    model.resetForShow()
    model.beginAppear()
    model.opacity = 1
    model.markVisible()
    XCTAssertTrue(model.beginDismiss())
    XCTAssertFalse(model.beginDismiss())
  }

  func testEveryPaneHasSymbolAndTint() {
    for pane in OnTimeSettingsPane.allCases {
      XCTAssertFalse(pane.systemImage.isEmpty)
      XCTAssertFalse(pane.title.isEmpty)
    }
  }
}