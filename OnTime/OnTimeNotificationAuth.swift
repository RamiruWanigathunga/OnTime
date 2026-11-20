import AppKit
import UserNotifications

/// Notification permission helpers for an LSUIElement / accessory menu-bar app.
/// System prompts often never appear unless the app briefly becomes `.regular` and active.
enum OnTimeNotificationAuth {
  static func openSystemSettings() {
    let candidates = [
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
      "x-apple.systempreferences:com.apple.preference.notifications",
    ]
    for raw in candidates {
      if let url = URL(string: raw), NSWorkspace.shared.open(url) {
        return
      }
    }
  }

  /// Activate as a regular app, then request alert (+ sound) authorization.
  static func requestAuthorization(completion: @escaping (_ granted: Bool) -> Void) {
    let previous = NSApp.activationPolicy()
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
      granted,
      _ in
      DispatchQueue.main.async {
        // Settings / About may still need a windowed policy; only restore accessory
        // when nothing else is visibly holding the app in the Dock.
        if previous == .accessory, NSApp.windows.allSatisfy({ !$0.isVisible || $0.isSheet }) {
          NSApp.setActivationPolicy(.accessory)
        }
        completion(granted)
      }
    }
  }

  static func getSettings(completion: @escaping (UNNotificationSettings) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        completion(settings)
      }
    }
  }
}
