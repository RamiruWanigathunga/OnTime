import AppKit
import Sparkle

/// Owns the Sparkle standard updater for the menu-bar app.
@MainActor
final class OnTimeUpdater {
  static let shared = OnTimeUpdater()

  private let controller: SPUStandardUpdaterController

  private init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  /// User-initiated check from Settings → About.
  func checkForUpdates(_ sender: Any? = nil) {
    controller.checkForUpdates(sender)
  }

  var canCheckForUpdates: Bool {
    controller.updater.canCheckForUpdates
  }
}
