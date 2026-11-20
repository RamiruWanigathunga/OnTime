import AppKit
import SwiftUI

struct OnTimeTimerSettingsPane: View {
  @AppStorage(OnTimeSettingsKeys.pomodoroWorkMinutes) private var pomodoroWorkMinutes =
    PomodoroDefaults.workMinutes
  @AppStorage(OnTimeSettingsKeys.pomodoroShortBreakMinutes) private var pomodoroShortBreakMinutes =
    PomodoroDefaults.shortBreakMinutes
  @AppStorage(OnTimeSettingsKeys.pomodoroLongBreakMinutes) private var pomodoroLongBreakMinutes =
    PomodoroDefaults.longBreakMinutes
  @AppStorage(OnTimeSettingsKeys.pomodoroCyclesPerSet) private var pomodoroCyclesPerSet =
    PomodoroDefaults.cyclesPerSet
  @AppStorage(OnTimeSettingsKeys.pomodoroShouldLoop) private var pomodoroShouldLoop =
    PomodoroDefaults.shouldLoop
  @AppStorage(OnTimeSettingsKeys.pauseAfterBreak) private var pauseAfterBreak = false

  var body: some View {
    SettingsPaneScroll {
      SettingsSectionLabel(title: "Pomodoro durations (minutes)")
      SettingsSectionCard {
        timerNumberRow(
          "Work interval",
          value: $pomodoroWorkMinutes,
          maximum: PomodoroDefaults.maximumDurationMinutes
        )
        timerNumberRow(
          "Short break",
          value: $pomodoroShortBreakMinutes,
          maximum: PomodoroDefaults.maximumDurationMinutes
        )
        timerNumberRow(
          "Long break",
          value: $pomodoroLongBreakMinutes,
          maximum: PomodoroDefaults.maximumDurationMinutes
        )
        timerNumberRow(
          "Cycles per set",
          value: $pomodoroCyclesPerSet,
          maximum: PomodoroDefaults.maximumCyclesPerSet,
          showsDivider: false
        )
      }

      SettingsSectionLabel(title: "Behavior")
      SettingsSectionCard {
        SettingsToggleRow(title: "Loop continuously", isOn: $pomodoroShouldLoop)
        SettingsToggleRow(
          title: "Pause after break",
          subtitle: "Next work phase waits until you resume.",
          isOn: $pauseAfterBreak
        )
        SettingsRow(title: "Restore defaults", showsDivider: false) {
          Button("Restore") {
            resetPomodoroSettings()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }
    }
  }

  private func resetPomodoroSettings() {
    pomodoroWorkMinutes = PomodoroDefaults.workMinutes
    pomodoroShortBreakMinutes = PomodoroDefaults.shortBreakMinutes
    pomodoroLongBreakMinutes = PomodoroDefaults.longBreakMinutes
    pomodoroCyclesPerSet = PomodoroDefaults.cyclesPerSet
    pomodoroShouldLoop = PomodoroDefaults.shouldLoop
    pauseAfterBreak = false
  }

  private func timerNumberRow(
    _ title: String,
    value: Binding<Int>,
    maximum: Int,
    showsDivider: Bool = true
  ) -> some View {
    SettingsRow(title: title, showsDivider: showsDivider) {
      HStack(spacing: 4) {
        TextField("", value: value, format: .number)
          .textFieldStyle(.roundedBorder)
          .frame(width: 52)
          .controlSize(.small)
          .onChange(of: value.wrappedValue) { _, newValue in
            if newValue < 1 {
              value.wrappedValue = 1
            } else if newValue > maximum {
              value.wrappedValue = maximum
            }
          }
          .onKeyPress(.upArrow) {
            value.wrappedValue = min(maximum, value.wrappedValue + 1)
            return .handled
          }
          .onKeyPress(.downArrow) {
            value.wrappedValue = max(1, value.wrappedValue - 1)
            return .handled
          }

        Stepper("", value: value, in: 1...maximum)
          .labelsHidden()
          .controlSize(.small)
          .focusable(false)
      }
    }
  }
}
