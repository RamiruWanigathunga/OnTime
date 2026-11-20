import AppKit
import Sparkle

/// Owns the Sparkle standard updater for the menu-bar app.
///
/// LSUIElement / `.accessory` apps hide Sparkle’s progress and “You’re up to date”
/// windows unless we briefly become a regular app for the update session.
@MainActor
final class OnTimeUpdater: NSObject, SPUUpdaterDelegate {
  static let shared = OnTimeUpdater()

  private lazy var controller: SPUStandardUpdaterController = {
    SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: self,
      userDriverDelegate: nil
    )
  }()

  private var presentedAsRegularForUpdate = false

  private override init() {
    super.init()
    // Start Sparkle at launch (automatic checks remain off via Info.plist).
    _ = controller
  }

  /// User-initiated check from Settings → About.
  func checkForUpdates(_ sender: Any? = nil) {
    presentAsRegularForUpdateUI()
    controller.checkForUpdates(sender)
  }

  var canCheckForUpdates: Bool {
    controller.updater.canCheckForUpdates
  }

  private func presentAsRegularForUpdateUI() {
    presentedAsRegularForUpdate = true
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func restoreAccessoryAfterUpdateUI() {
    guard presentedAsRegularForUpdate else { return }
    presentedAsRegularForUpdate = false
    NSApp.setActivationPolicy(.accessory)
  }

  // MARK: - SPUUpdaterDelegate

  nonisolated func updater(
    _ updater: SPUUpdater,
    didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
    error: (any Error)?
  ) {
    Task { @MainActor in
      self.restoreAccessoryAfterUpdateUI()
    }
  }
}
