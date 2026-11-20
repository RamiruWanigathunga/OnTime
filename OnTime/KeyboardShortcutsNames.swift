import Foundation

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let openRecorder = Self("hotkeyOpenRecorder")
  static let pauseResumeRecorder = Self("hotkeyPauseResumeRecorder")
  static let clearRecorder = Self("hotkeyClearRecorder")
  static let startPomodoroRecorder = Self("hotkeyStartPomodoroRecorder")
  static let startStopwatchRecorder = Self("hotkeyStartStopwatchRecorder")
  static let legacyOpenRecorder = Self(OnTimeSettingsKeys.openHotkey)
  static let legacyClearRecorder = Self(OnTimeSettingsKeys.clearHotkey)
}
#endif
