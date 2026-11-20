import SwiftUI

#if canImport(KeyboardShortcuts)
  import KeyboardShortcuts
#endif

struct OnTimeShortcutsSettingsPane: View {
  @State private var openHotkey: Hotkey?
  @State private var pauseResumeHotkey: Hotkey?
  @State private var clearHotkey: Hotkey?
  @State private var startPomodoroHotkey: Hotkey?
  @State private var startStopwatchHotkey: Hotkey?
  @State private var hasHotkeyConflict = false
  @State private var isUpdatingRecorder = false
  @State private var hotkeyErrorMessage: String?

  var body: some View {
    SettingsPaneScroll {
      SettingsSectionLabel(title: "Keyboard shortcuts")
      SettingsSectionCard {
        hotkeyRow("Open OnTime", name: .openRecorder, action: .open)
        hotkeyRow("Pause/resume", name: .pauseResumeRecorder, action: .pauseResume)
        hotkeyRow("Clear timer", name: .clearRecorder, action: .clear)
        hotkeyRow("Start Pomodoro", name: .startPomodoroRecorder, action: .startPomodoro)
        hotkeyRow(
          "Start stopwatch",
          name: .startStopwatchRecorder,
          action: .startStopwatch,
          showsDivider: false
        )

        if hasHotkeyConflict {
          SettingsErrorText(
            message:
              "Open, pause/resume, clear, start Pomodoro, and start stopwatch shortcuts must be different."
          )
        }
        if let hotkeyErrorMessage {
          SettingsErrorText(message: hotkeyErrorMessage)
        }
      }

      Text(
        "Click a field, then press the shortcut. Clear with ✕ to record a new one. Shortcuts need ⌘, ⌥, or ⌃."
      )
      .font(SettingsPanelStyle.subtitleFont)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, SettingsPanelStyle.rowHorizontalPadding)
    }
    .onAppear {
      #if canImport(KeyboardShortcuts)
        Hotkey.migrateRecorderDefaultsIfNeeded()
      #endif
      Hotkey.seedDefaultsIfNeeded()
      loadHotkeysFromDefaults()
      #if canImport(KeyboardShortcuts)
        Hotkey.disableRecorderGlobalCapture()
      #endif
    }
    .onReceive(NotificationCenter.default.publisher(for: Hotkey.registrationFailedNotification)) {
      notification in
      hotkeyErrorMessage = Self.formatHotkeyError(notification)
    }
  }

  @ViewBuilder
  private func hotkeyRow(
    _ title: String,
    name: KeyboardShortcuts.Name,
    action: HotkeyAction,
    showsDivider: Bool = true
  ) -> some View {
    SettingsRow(title: title, showsDivider: showsDivider) {
      #if canImport(KeyboardShortcuts)
        KeyboardShortcutsRecorderRepresentable(
          name: name,
          onChange: { shortcut in
            handleRecorderChange(action: action, shortcut: shortcut)
          }
        )
        .padding(.trailing, 8)
      #else
        Text("Add KeyboardShortcuts")
          .foregroundStyle(.secondary)
      #endif
    }
  }

  private func loadHotkeysFromDefaults() {
    openHotkey = Hotkey.load(for: .open)
    pauseResumeHotkey = Hotkey.load(for: .pauseResume)
    clearHotkey = Hotkey.load(for: .clear)
    startPomodoroHotkey = Hotkey.load(for: .startPomodoro)
    startStopwatchHotkey = Hotkey.load(for: .startStopwatch)
    hasHotkeyConflict = hotkeysHaveConflict([
      openHotkey, pauseResumeHotkey, clearHotkey, startPomodoroHotkey, startStopwatchHotkey,
    ])
    syncRecorderFromDefaults()
  }

  private func syncRecorderFromDefaults() {
    #if canImport(KeyboardShortcuts)
      isUpdatingRecorder = true
      Hotkey.updateRecorderUI(openHotkey, name: .openRecorder)
      Hotkey.updateRecorderUI(pauseResumeHotkey, name: .pauseResumeRecorder)
      Hotkey.updateRecorderUI(clearHotkey, name: .clearRecorder)
      Hotkey.updateRecorderUI(startPomodoroHotkey, name: .startPomodoroRecorder)
      Hotkey.updateRecorderUI(startStopwatchHotkey, name: .startStopwatchRecorder)
      // Keep Carbon as the only global registrant.
      Hotkey.disableRecorderGlobalCapture()
      isUpdatingRecorder = false
    #endif
  }

  #if canImport(KeyboardShortcuts)
    private func handleRecorderChange(action: HotkeyAction, shortcut: KeyboardShortcuts.Shortcut?) {
      guard !isUpdatingRecorder else { return }

      // Cleared via ✕ — persist empty; field shows “Record Shortcut” for a new capture.
      guard let shortcut else {
        commit(nil, for: action)
        Hotkey.disableRecorderGlobalCapture()
        return
      }

      guard let proposed = Hotkey(keyboardShortcut: shortcut) else {
        revertRecorder(for: action)
        return
      }

      if !Hotkey.isValid(modifierFlags: proposed.modifierFlags) {
        hotkeyErrorMessage =
          "Shortcuts need ⌘, ⌥, or ⌃ with the key (Shift or Fn alone isn’t enough)."
        hasHotkeyConflict = false
        revertRecorder(for: action)
        return
      }

      var nextOpen = openHotkey
      var nextPauseResume = pauseResumeHotkey
      var nextClear = clearHotkey
      var nextStartPomodoro = startPomodoroHotkey
      var nextStartStopwatch = startStopwatchHotkey
      switch action {
      case .open: nextOpen = proposed
      case .pauseResume: nextPauseResume = proposed
      case .clear: nextClear = proposed
      case .startPomodoro: nextStartPomodoro = proposed
      case .startStopwatch: nextStartStopwatch = proposed
      }

      if hotkeysHaveConflict([
        nextOpen, nextPauseResume, nextClear, nextStartPomodoro, nextStartStopwatch,
      ]) {
        hasHotkeyConflict = true
        hotkeyErrorMessage = nil
        revertRecorder(for: action)
        return
      }

      commit(proposed, for: action)
      Hotkey.disableRecorderGlobalCapture()
    }

    private func commit(_ proposed: Hotkey?, for action: HotkeyAction) {
      switch action {
      case .open: openHotkey = proposed
      case .pauseResume: pauseResumeHotkey = proposed
      case .clear: clearHotkey = proposed
      case .startPomodoro: startPomodoroHotkey = proposed
      case .startStopwatch: startStopwatchHotkey = proposed
      }
      // Library already wrote KeyboardShortcuts storage; only persist OnTime’s Hotkey.
      Hotkey.save(proposed, for: action)
      hasHotkeyConflict = false
      hotkeyErrorMessage = nil
    }

    private func revertRecorder(for action: HotkeyAction) {
      let existing: Hotkey?
      let name: KeyboardShortcuts.Name
      switch action {
      case .open:
        existing = openHotkey
        name = .openRecorder
      case .pauseResume:
        existing = pauseResumeHotkey
        name = .pauseResumeRecorder
      case .clear:
        existing = clearHotkey
        name = .clearRecorder
      case .startPomodoro:
        existing = startPomodoroHotkey
        name = .startPomodoroRecorder
      case .startStopwatch:
        existing = startStopwatchHotkey
        name = .startStopwatchRecorder
      }
      isUpdatingRecorder = true
      Hotkey.updateRecorderUI(existing, name: name)
      Hotkey.disableRecorderGlobalCapture()
      isUpdatingRecorder = false
    }
  #endif

  private static func formatHotkeyError(_ notification: Notification) -> String {
    guard
      let userInfo = notification.userInfo,
      let action = userInfo[Hotkey.registrationFailedActionKey] as? HotkeyAction,
      let status = userInfo[Hotkey.registrationFailedStatusKey] as? Int
    else {
      return "Hotkey registration failed."
    }

    let actionName: String
    switch action {
    case .open: actionName = "Open OnTime"
    case .pauseResume: actionName = "Pause/resume"
    case .clear: actionName = "Clear timer"
    case .startPomodoro: actionName = "Start Pomodoro"
    case .startStopwatch: actionName = "Start stopwatch"
    }
    return "\(actionName) shortcut failed to register (status \(status)). Try a different combination."
  }
}

fileprivate func hotkeysHaveConflict(_ hotkeys: [Hotkey?]) -> Bool {
  var seen: [Hotkey] = []
  for hotkey in hotkeys.compactMap({ $0 }) {
    if seen.contains(hotkey) {
      return true
    }
    seen.append(hotkey)
  }
  return false
}
