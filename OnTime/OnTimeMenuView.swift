import AppKit
import SwiftUI

struct OnTimeMenuView: View {
  @EnvironmentObject private var model: OnTimeModel
  @Environment(\.menuDismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @AppStorage(OnTimeSettingsKeys.menuButtonSize) private var menuButtonSize = MenuButtonSize.default.rawValue
  @AppStorage(OnTimeSettingsKeys.menuButtonBrightness) private var menuButtonBrightness =
    MenuButtonBrightness.default.rawValue
  @State private var placeholder = OnTimeInputPlaceholders.defaults.randomElement() ?? "10s"
  @FocusState private var isInputFocused: Bool

  private func refreshPlaceholder() {
    placeholder = OnTimeInputPlaceholders.pool(
      isRunning: model.isRunning,
      isFinished: model.isFinished,
      mode: model.mode,
      isPomodoroActive: model.pomodoroSession?.isActive == true
    ).randomElement() ?? "10s"
  }

  private struct IconStyle {
    let color: Color
    let opacity: Double
  }

  private func iconStyle(for brightness: MenuButtonBrightness, scheme: ColorScheme) -> IconStyle {
    switch brightness {
    case .dim:
      return IconStyle(color: .primary, opacity: 0.45)
    case .normal:
      return IconStyle(color: .primary, opacity: 0.7)
    case .bright:
      return IconStyle(color: scheme == .light ? .black : .white, opacity: 0.92)
    }
  }

  var body: some View {
    let buttonSize = MenuButtonSize(rawValue: menuButtonSize) ?? .default
    let brightnessSetting = MenuButtonBrightness(rawValue: menuButtonBrightness) ?? .default
    let style = iconStyle(for: brightnessSetting, scheme: colorScheme)

    VStack(alignment: .leading, spacing: 12) {
      inputField
      controlsRow(buttonSize: buttonSize, style: style)
    }
    .padding(16)
    .frame(width: 220)
    .background(
      Color.clear
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
    )
  }

  private var inputField: some View {
    ZStack(alignment: .leading) {
      if model.inputDuration.isEmpty {
        Text(placeholder)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      TextField("", text: $model.inputDuration)
        .focused($isInputFocused)
        .textFieldStyle(.plain)
        .lineLimit(1)
        .onSubmit {
          if model.startFromInputs() {
            dismiss()
          }
        }
    }
    .font(.system(size: 22, weight: .regular))
    .padding(.vertical, 8)
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .leading)
    .clipped()
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.22))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
    )
    .onAppear {
      refreshPlaceholder()
      DispatchQueue.main.async { isInputFocused = true }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: Notification.Name("OnTimePopoverWillShow"))
    ) { _ in
      refreshPlaceholder()
      DispatchQueue.main.async { isInputFocused = true }
    }
  }

  private func controlsRow(buttonSize: MenuButtonSize, style: IconStyle) -> some View {
    let pauseDisabled = model.isRunning && !model.isPaused && model.isTimeOfDayCountdown

    return HStack(spacing: 4) {
      iconButton(
        systemName: "gearshape",
        accessibilityLabel: "Settings",
        help: "Open settings",
        buttonSize: buttonSize,
        style: style
      ) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
          appDelegate.openSettingsClosingPopover()
        } else {
          dismiss()
          SettingsWindowController.shared.show()
        }
      }

      Spacer()

      if model.canRepeat {
        iconButton(
          systemName: "arrow.clockwise",
          accessibilityLabel: "Repeat",
          help: "Repeat last timer",
          buttonSize: buttonSize,
          style: style
        ) {
          if model.repeatLastInput() { dismiss() }
        }
      }

      iconButton(
        systemName: (model.isRunning && !model.isPaused) ? "pause.fill" : "play.fill",
        accessibilityLabel: (model.isRunning && !model.isPaused) ? "Pause" : "Play",
        help: (model.isRunning && !model.isPaused) ? "Pause timer" : "Start or resume",
        buttonSize: buttonSize,
        style: style,
        disabled: pauseDisabled
      ) {
        if model.isRunning {
          if model.isPaused {
            if model.isFinished {
              model.startStopwatch()
              dismiss()
            } else {
              model.resume()
            }
          } else {
            model.pause()
          }
        } else {
          model.startStopwatch()
          dismiss()
        }
      }

      iconButton(
        systemName: "xmark",
        accessibilityLabel: "Clear",
        help: "Clear timer",
        buttonSize: buttonSize,
        style: style,
        disabled: !model.isRunning
      ) {
        model.stop()
        dismiss()
      }
    }
  }

  private func iconButton(
    systemName: String,
    accessibilityLabel: String,
    help: String,
    buttonSize: MenuButtonSize,
    style: IconStyle,
    disabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: buttonSize.iconPointSize * 0.85, weight: .medium))
        .frame(width: max(28, buttonSize.buttonPointSize), height: max(28, buttonSize.buttonPointSize))
        .foregroundStyle(style.color)
        .opacity(style.opacity)
    }
    .buttonStyle(HoverPillButtonStyle())
    .disabled(disabled)
    .opacity(disabled ? 0.45 : 1)
    .help(help)
    .accessibilityLabel(accessibilityLabel)
  }
}

private struct HoverPillButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    HoverPillButton(configuration: configuration)
  }

  private struct HoverPillButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    let configuration: ButtonStyle.Configuration
    @State private var isHovering = false

    var body: some View {
      configuration.label
        .padding(2)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color(nsColor: .quaternaryLabelColor).opacity(fillOpacity))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(
              Color(nsColor: .separatorColor).opacity(isHovering || configuration.isPressed ? 0.55 : 0),
              lineWidth: 1
            )
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .scaleEffect(configuration.isPressed ? 0.965 : 1)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var fillOpacity: Double {
      guard isEnabled else { return 0 }
      let base: Double = colorScheme == .dark ? 0.28 : 0.18
      return (isHovering || configuration.isPressed) ? base : 0
    }
  }
}

/// Input placeholder pools: common durations plus context-aware relative / skip examples.
enum OnTimeInputPlaceholders {
  /// Default suggestions, including `stopwatch` for OnTime.
  static let defaults = [
    "10s", "30 sec", "45 secs",
    "1 min", "5 mins", "12 minutes",
    "20m", "25 min", "45 minutes",
    "1h", "1 hr", "1.5 hrs", "2 hours",
    "3h", "4 hours", "17m 45s", "1h 30m",
    "25:00", "10pm", "6:15a", "noon",
    "pomodoro", "stopwatch",
  ]

  /// Relative forms the NL parser already accepts (shown only when adjust is available).
  static let relativeWhenAdjustable = ["+5 min", "-2 min", "+45 sec", "Add 30min"]

  static func pool(
    isRunning: Bool,
    isFinished: Bool,
    mode: OnTimeModel.TimerMode,
    isPomodoroActive: Bool
  ) -> [String] {
    var pool = defaults
    let timerActive = isRunning && !isFinished
    let isStopwatch = mode == .stopwatch

    if timerActive && !isStopwatch {
      pool.append(contentsOf: relativeWhenAdjustable)
    }
    if timerActive && isPomodoroActive {
      pool.append("skip")
    }
    return pool
  }
}

#Preview {
  OnTimeMenuView()
    .environmentObject(OnTimeModel())
}
