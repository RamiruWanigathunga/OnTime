import AppIntents

struct OnTimeShortcutsProvider: AppShortcutsProvider {
  /// At most 10 App Shortcuts. Parameterized phrases use AppEnum only (String/Int are not allowed).
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartPresetCountdownIntent(),
      phrases: [
        "Start a \(\.$minutes) minute timer in \(.applicationName)",
        "Countdown \(\.$minutes) minutes with \(.applicationName)",
      ],
      shortTitle: "Start Countdown",
      systemImageName: "timer"
    )
    AppShortcut(
      intent: StartPomodoroIntent(),
      phrases: [
        "Start Pomodoro in \(.applicationName)",
        "Pomodoro with \(.applicationName)",
      ],
      shortTitle: "Start Pomodoro",
      systemImageName: "flame"
    )
    AppShortcut(
      intent: StartStopwatchIntent(),
      phrases: [
        "Start stopwatch in \(.applicationName)",
        "Stopwatch with \(.applicationName)",
      ],
      shortTitle: "Start Stopwatch",
      systemImageName: "stopwatch"
    )
    AppShortcut(
      intent: PauseTimerIntent(),
      phrases: [
        "Pause timer in \(.applicationName)",
        "Pause \(.applicationName) timer",
      ],
      shortTitle: "Pause Timer",
      systemImageName: "pause.circle"
    )
    AppShortcut(
      intent: ResumeTimerIntent(),
      phrases: [
        "Resume timer in \(.applicationName)",
        "Resume \(.applicationName) timer",
      ],
      shortTitle: "Resume Timer",
      systemImageName: "play.circle"
    )
    AppShortcut(
      intent: StopTimerIntent(),
      phrases: [
        "Stop timer in \(.applicationName)",
        "Clear timer in \(.applicationName)",
      ],
      shortTitle: "Stop Timer",
      systemImageName: "xmark.circle"
    )
    AppShortcut(
      intent: GetTimerStatusIntent(),
      phrases: [
        "How much time is left in \(.applicationName)",
        "Timer status in \(.applicationName)",
      ],
      shortTitle: "Timer Status",
      systemImageName: "clock"
    )
    AppShortcut(
      intent: SkipPomodoroPhaseIntent(),
      phrases: [
        "Skip Pomodoro phase in \(.applicationName)",
        "Skip phase in \(.applicationName)",
      ],
      shortTitle: "Skip Phase",
      systemImageName: "forward.end"
    )
    AppShortcut(
      intent: AddPresetMinutesIntent(),
      phrases: [
        "Add \(\.$minutes) minutes in \(.applicationName)",
        "Add \(\.$minutes) minutes to \(.applicationName)",
      ],
      shortTitle: "Add Minutes",
      systemImageName: "plus.minus"
    )
    AppShortcut(
      intent: RunNaturalLanguageCommandIntent(),
      phrases: [
        "Run a timer command in \(.applicationName)",
        "Natural language timer in \(.applicationName)",
      ],
      shortTitle: "Run Command",
      systemImageName: "text.bubble"
    )
  }
}
