import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct OnTimeSoundSettingsPane: View {
  @AppStorage(OnTimeSettingsKeys.tone) private var selectedTone = NotificationTone.default.rawValue
  @AppStorage(OnTimeSettingsKeys.repeatCount) private var repeatCount = NotificationRepeatOption
    .default.rawValue
  @AppStorage(OnTimeSettingsKeys.volume) private var toneVolume = AudioDefaults.focusSoundVolume
  @AppStorage(OnTimeSettingsKeys.windupVolume) private var windupVolume = AudioDefaults
    .focusSoundVolume
  @AppStorage(OnTimeSettingsKeys.tickingVolume) private var tickingVolume = AudioDefaults
    .focusSoundVolume
  @AppStorage(OnTimeSettingsKeys.focusAudioPomodoroWork) private var focusAudioPomodoroWork =
    AudioDefaults.focusAudioPomodoroWork
  @AppStorage(OnTimeSettingsKeys.focusAudioCountdown) private var focusAudioCountdown =
    AudioDefaults.focusAudioCountdown
  @AppStorage(OnTimeSettingsKeys.focusAudioStopwatch) private var focusAudioStopwatch =
    AudioDefaults.focusAudioStopwatch

  @State private var previewPlayer: AVAudioPlayer?
  @State private var previewPlayers: [String: AVAudioPlayer] = [:]
  @State private var hasCustomTone = CustomCompletionSound.hasInstalledCustom()
  @State private var customToneLabel = CustomCompletionSound.displayName()
  @State private var lastStableTone = NotificationTone.default.rawValue
  @State private var skipTonePreview = false

  var body: some View {
    SettingsPaneScroll {
      SettingsSectionLabel(title: "Completion")
      SettingsSectionCard {
        SettingsRow(title: "Notification tone") {
          Picker("", selection: $selectedTone) {
            ForEach(NotificationTone.allCases) { tone in
              Text(tone.displayName).tag(tone.rawValue)
            }
            if hasCustomTone {
              Text(customToneLabel).tag(CustomCompletionSound.toneRawValue)
            }
            Divider()
            Text("Add custom sound…").tag(CustomCompletionSound.addPickerTag)
            if hasCustomTone {
              Text("Remove custom sound…").tag(CustomCompletionSound.removePickerTag)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .fixedSize()
          .onChange(of: selectedTone) { _, newValue in
            handleToneSelectionChange(newValue)
          }
        }

        SettingsRow(title: "Play tone") {
          Picker("", selection: $repeatCount) {
            ForEach(NotificationRepeatOption.allCases) { option in
              Text(option.displayName).tag(option.rawValue)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .fixedSize()
        }

        focusVolumeRow(
          "Tone volume",
          volume: $toneVolume,
          showsDivider: false,
          help: "Double-click to reset to 50%.",
          onChange: { playPreviewTone(named: selectedTone) }
        )
      }

      SettingsSectionLabel(title: "Focus audio")
      SettingsSectionCard {
        SettingsToggleRow(
          title: "Pomodoro work",
          subtitle: "Windup and ticking during work intervals.",
          isOn: $focusAudioPomodoroWork
        )
        SettingsToggleRow(title: "Countdown", isOn: $focusAudioCountdown)
        SettingsToggleRow(
          title: "Stopwatch",
          subtitle: "Completion still uses the notification tone above.",
          isOn: $focusAudioStopwatch
        )

        focusVolumeRow(
          "Windup",
          volume: $windupVolume,
          help: "Double-click to reset to 50%."
        )
        focusVolumeRow(
          "Ticking",
          volume: $tickingVolume,
          showsDivider: false,
          help: "Double-click to reset to 50%."
        )
      }

      Text("Volume sliders run from 0% (mute) to 100%. The default is 50%.")
        .font(SettingsPanelStyle.subtitleFont)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, SettingsPanelStyle.rowHorizontalPadding)
    }
    .onAppear {
      AudioDefaults.migrateNotificationVolumeIfNeeded()
      refreshCustomToneState()
      let recoveredTone = CustomCompletionSound.recoverSelectionIfNeeded()
      if selectedTone != recoveredTone {
        skipTonePreview = true
        selectedTone = recoveredTone
      }
      lastStableTone = selectedTone
    }
    .onDisappear {
      stopPreviewTone()
      // Drop cached preview players when leaving Sound so WAV buffers aren’t retained.
      previewPlayers.removeAll(keepingCapacity: false)
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: SettingsWindowController.settingsWillCloseNotification)
    ) { _ in
      stopPreviewTone()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: SettingsWindowController.settingsDidResignKeyNotification)
    ) { _ in
      stopPreviewTone()
    }
  }

  private func focusVolumeRow(
    _ title: String,
    volume: Binding<Double>,
    showsDivider: Bool = true,
    help: String? = nil,
    onChange: (() -> Void)? = nil
  ) -> some View {
    SettingsRow(title: title, showsDivider: showsDivider) {
      HStack(spacing: 8) {
        Slider(value: volume, in: 0...AudioDefaults.focusSoundVolumeMax)
          .frame(width: 120)
          .onChange(of: volume.wrappedValue) { _, _ in
            onChange?()
          }
          .simultaneousGesture(
            TapGesture(count: 2).onEnded {
              volume.wrappedValue = AudioDefaults.focusSoundVolume
              onChange?()
            }
          )
        Text("\(AudioDefaults.percent(fromGain: volume.wrappedValue))%")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 40, alignment: .trailing)
      }
      .padding(.trailing, 4)
      .help(help ?? "")
    }
  }

  private func handleToneSelectionChange(_ newValue: String) {
    if skipTonePreview {
      skipTonePreview = false
      return
    }

    if newValue == CustomCompletionSound.addPickerTag {
      skipTonePreview = true
      selectedTone = lastStableTone
      presentCustomSoundOpenPanel()
      return
    }

    if newValue == CustomCompletionSound.removePickerTag {
      CustomCompletionSound.clear()
      refreshCustomToneState()
      let fallback = CustomCompletionSound.fallbackBuiltIn().rawValue
      skipTonePreview = true
      selectedTone = fallback
      lastStableTone = fallback
      playPreviewTone(named: fallback)
      return
    }

    if newValue == CustomCompletionSound.toneRawValue {
      let recovered = CustomCompletionSound.recoverSelectionIfNeeded()
      if recovered != CustomCompletionSound.toneRawValue {
        refreshCustomToneState()
        skipTonePreview = true
        selectedTone = recovered
        lastStableTone = recovered
        playPreviewTone(named: recovered)
        return
      }
      lastStableTone = newValue
      playPreviewTone(named: newValue)
      return
    }

    if let tone = NotificationTone(rawValue: newValue) {
      CustomCompletionSound.rememberBuiltIn(tone)
      lastStableTone = newValue
      playPreviewTone(named: newValue)
      return
    }

    let fallback = CustomCompletionSound.fallbackBuiltIn().rawValue
    skipTonePreview = true
    selectedTone = fallback
    lastStableTone = fallback
  }

  private func presentCustomSoundOpenPanel() {
    SettingsWindowController.shared.isPresentingModal = true
    defer { SettingsWindowController.shared.isPresentingModal = false }

    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    var types: [UTType] = [.wav, .aiff, .mp3, .mpeg4Audio]
    if let caf = UTType(filenameExtension: "caf") { types.append(caf) }
    if let aif = UTType(filenameExtension: "aif") { types.append(aif) }
    panel.allowedContentTypes = types
    panel.message = "Choose a completion sound (WAV, AIFF, MP3, M4A, or CAF)."
    panel.prompt = "Add"

    guard panel.runModal() == .OK, let url = panel.url else { return }

    if let tone = NotificationTone(rawValue: lastStableTone) {
      CustomCompletionSound.rememberBuiltIn(tone)
    }

    do {
      _ = try CustomCompletionSound.install(from: url)
      refreshCustomToneState()
      skipTonePreview = true
      selectedTone = CustomCompletionSound.toneRawValue
      lastStableTone = CustomCompletionSound.toneRawValue
      playPreviewTone(named: CustomCompletionSound.toneRawValue)
    } catch {
      let alert = NSAlert()
      alert.messageText = "Couldn’t add that sound"
      alert.informativeText = "Choose a playable WAV, AIFF, MP3, M4A, or CAF file."
      alert.alertStyle = .warning
      alert.runModal()
    }
  }

  private func refreshCustomToneState() {
    hasCustomTone = CustomCompletionSound.hasInstalledCustom()
    customToneLabel = CustomCompletionSound.displayName()
  }

  private func playPreviewTone(named rawValue: String) {
    stopPreviewTone()
    if rawValue == CustomCompletionSound.toneRawValue {
      if let url = CustomCompletionSound.resolvePlayableURL(),
        let player = try? AVAudioPlayer(contentsOf: url)
      {
        previewPlayer = player
      }
    } else if let cached = previewPlayers[rawValue] {
      previewPlayer = cached
    } else if let url = Bundle.main.url(forResource: rawValue, withExtension: "wav"),
      let player = try? AVAudioPlayer(contentsOf: url)
    {
      previewPlayers[rawValue] = player
      previewPlayer = player
    }

    previewPlayer?.volume = AudioDefaults.playerVolume(fromGain: toneVolume)
    previewPlayer?.currentTime = 0
    previewPlayer?.play()
  }

  private func stopPreviewTone() {
    previewPlayer?.stop()
    previewPlayer?.currentTime = 0
    previewPlayer = nil
  }
}
