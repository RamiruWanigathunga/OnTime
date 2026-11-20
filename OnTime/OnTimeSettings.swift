import AppKit
import AVFoundation
import Foundation

enum OnTimeSettingsKeys {
  static let tone = "notificationTone"
  /// Last built-in completion tone; used when a custom tone is missing/unreadable.
  static let lastBuiltInTone = "lastBuiltInNotificationTone"
  /// Filename of the copied custom tone under Application Support/OnTime/Sounds/.
  static let customToneFileName = "customNotificationToneFileName"
  /// Original basename shown in the tone picker for a custom sound.
  static let customToneDisplayName = "customNotificationToneDisplayName"
  static let repeatCount = "notificationRepeatCount"
  static let repeatCountMigrationVersion = "notificationRepeatCountMigrationVersion"
  static let volume = "notificationVolume"
  static let defaultUnit = "defaultTimeUnit"
  static let openHotkey = "hotkeyOpen"
  static let pauseResumeHotkey = "hotkeyPauseResume"
  static let clearHotkey = "hotkeyClear"
  static let startPomodoroHotkey = "hotkeyStartPomodoro"
  static let startStopwatchHotkey = "hotkeyStartStopwatch"
  static let didPromptLoginItem = "didPromptLoginItem"
  static let showNotifications = "showNotifications"
  static let menuBarIconSize = "menuBarIconSize"
  static let menuBarIcon = "menuBarIcon"
  static let menuButtonSize = "menuButtonSize"
  static let menuButtonBrightness = "menuButtonBrightness"
  static let menuBarStyle = "menuBarStyle"
  static let menuBarFontStyle = "menuBarFontStyle"
  static let pomodoroWorkMinutes = "pomodoroWorkMinutes"
  static let pomodoroShortBreakMinutes = "pomodoroShortBreakMinutes"
  static let pomodoroLongBreakMinutes = "pomodoroLongBreakMinutes"
  static let pomodoroCyclesPerSet = "pomodoroCyclesPerSet"
  static let pomodoroShouldLoop = "pomodoroShouldLoop"
  static let pauseAfterBreak = "pauseAfterBreak"
  static let windupVolume = "windupVolume"
  static let dingVolume = "dingVolume"
  static let tickingVolume = "tickingVolume"
  static let focusAudioPomodoroWork = "focusAudioPomodoroWork"
  static let focusAudioCountdown = "focusAudioCountdown"
  static let focusAudioStopwatch = "focusAudioStopwatch"
  static let overrunTimeLimit = "overrunTimeLimit"
  /// Display precision for countdown, Pomodoro, and stopwatch readouts.
  static let displayPrecision = "displayPrecision"
  /// Legacy key; migrated into `displayPrecision` on launch.
  static let stopwatchPrecision = "stopwatchPrecision"
  /// Drag down from the menu bar icon to set a countdown (GesTimer-style). Default OFF.
  static let stretchToSetTimer = "stretchToSetTimer"
}

enum StretchTimerDefaults {
  /// Drag-to-stretch is on by default; disable in Settings → Behavior if unwanted.
  static let isEnabled = true
}

enum AudioDefaults {
  /// Default focus/notification gain (UI shows 50%; max 2.0 shows as 100%).
  static let focusSoundVolume: Double = 1.0
  static let focusSoundVolumeMax: Double = 2.0
  static let overrunTimeLimit: Double = -60
  /// Per-mode focus audio (windup / ticking / ding) defaults — all on when unset.
  static let focusAudioPomodoroWork = true
  static let focusAudioCountdown = true
  static let focusAudioStopwatch = true

  /// Gain 0...2 → percent 0...100 (1.0 → 50%, 2.0 → 100%).
  static func percent(fromGain gain: Double) -> Int {
    let clamped = min(max(gain, 0), focusSoundVolumeMax)
    return Int((clamped / focusSoundVolumeMax * 100).rounded())
  }

  static func gain(fromPercent percent: Double) -> Double {
    min(max(percent / 100.0 * focusSoundVolumeMax, 0), focusSoundVolumeMax)
  }

  /// AVAudioPlayer.volume is 0...1; map gain so 100% = full output.
  static func playerVolume(fromGain gain: Double) -> Float {
    Float(min(max(gain, 0), focusSoundVolumeMax) / focusSoundVolumeMax)
  }

  /// Migrate legacy `notificationVolume` string enum → continuous gain Double.
  static func migrateNotificationVolumeIfNeeded(defaults: UserDefaults = .standard) {
    let key = OnTimeSettingsKeys.volume
    if let raw = defaults.string(forKey: key),
      let legacy = NotificationVolume(rawValue: raw)
    {
      defaults.set(legacy.gainEquivalent, forKey: key)
      return
    }
    if defaults.object(forKey: key) == nil {
      defaults.set(focusSoundVolume, forKey: key)
    }
  }

  static func notificationGain(defaults: UserDefaults = .standard) -> Double {
    migrateNotificationVolumeIfNeeded(defaults: defaults)
    if let raw = defaults.string(forKey: OnTimeSettingsKeys.volume),
      let legacy = NotificationVolume(rawValue: raw)
    {
      return legacy.gainEquivalent
    }
    let value = defaults.double(forKey: OnTimeSettingsKeys.volume)
    return min(max(value, 0), focusSoundVolumeMax)
  }
}

/// Where windup / ticking / ding focus audio may play.
enum FocusAudioMode: String, CaseIterable {
  case pomodoroWork
  case countdown
  case stopwatch

  var settingsKey: String {
    switch self {
    case .pomodoroWork: return OnTimeSettingsKeys.focusAudioPomodoroWork
    case .countdown: return OnTimeSettingsKeys.focusAudioCountdown
    case .stopwatch: return OnTimeSettingsKeys.focusAudioStopwatch
    }
  }

  var defaultEnabled: Bool {
    switch self {
    case .pomodoroWork: return AudioDefaults.focusAudioPomodoroWork
    case .countdown: return AudioDefaults.focusAudioCountdown
    case .stopwatch: return AudioDefaults.focusAudioStopwatch
    }
  }

  static func isEnabled(_ mode: FocusAudioMode, defaults: UserDefaults = .standard) -> Bool {
    if defaults.object(forKey: mode.settingsKey) == nil {
      return mode.defaultEnabled
    }
    return defaults.bool(forKey: mode.settingsKey)
  }
}

enum PomodoroDefaults {
  static let workMinutes = 25
  static let shortBreakMinutes = 5
  static let longBreakMinutes = 15
  static let cyclesPerSet = 4
  static let shouldLoop = false
  static let maximumDurationMinutes = 480
  static let maximumCyclesPerSet = 100
}

enum NotificationTone: String, CaseIterable, Identifiable {
  case alarmFrenzy = "alarm-frenzy"
  case discreet
  case fingerlicking
  case gladToKnow = "glad-to-know"
  case goodMorning = "good-morning"
  case joyousChime = "joyous-chime"
  case lightHearted = "light-hearted"
  case openYourEyes = "open-your-eyes"
  case rush
  case wailing
  case wakeUp = "wake-up"
  case whistling

  static let `default` = NotificationTone.wakeUp

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .alarmFrenzy:
      return "Alarm frenzy"
    case .discreet:
      return "Discreet"
    case .fingerlicking:
      return "Finger licking"
    case .gladToKnow:
      return "Glad to know"
    case .goodMorning:
      return "Good morning"
    case .joyousChime:
      return "Joyous chime"
    case .lightHearted:
      return "Light-hearted"
    case .openYourEyes:
      return "Open your eyes"
    case .rush:
      return "Rush"
    case .wailing:
      return "Wailing"
    case .wakeUp:
      return "Wake up"
    case .whistling:
      return "Whistling"
    }
  }
}

/// Custom completion-tone storage under Application Support, with silent fallback to a built-in.
enum CustomCompletionSound {
  static let toneRawValue = "custom"
  static let addPickerTag = "__add_custom_sound__"
  static let removePickerTag = "__remove_custom_sound__"
  static let allowedExtensions = ["wav", "aiff", "aif", "mp3", "m4a", "caf"]

  /// Unit-test override for the Sounds directory; nil uses Application Support/OnTime/Sounds.
  static var soundsDirectoryOverrideForTesting: URL?

  static func soundsDirectory(fileManager: FileManager = .default) -> URL {
    if let override = soundsDirectoryOverrideForTesting {
      return override
    }
    let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return support
      .appendingPathComponent("OnTime", isDirectory: true)
      .appendingPathComponent("Sounds", isDirectory: true)
  }

  static func displayName(defaults: UserDefaults = .standard) -> String {
    let name = defaults.string(forKey: OnTimeSettingsKeys.customToneDisplayName)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let name, !name.isEmpty {
      return "Custom (\(name))"
    }
    return "Custom"
  }

  static func isCustomSelected(defaults: UserDefaults = .standard) -> Bool {
    defaults.string(forKey: OnTimeSettingsKeys.tone) == toneRawValue
  }

  static func hasInstalledCustom(defaults: UserDefaults = .standard, fileManager: FileManager = .default)
    -> Bool
  {
    guard let url = customFileURL(defaults: defaults, fileManager: fileManager) else { return false }
    return fileManager.fileExists(atPath: url.path)
  }

  static func customFileURL(defaults: UserDefaults = .standard, fileManager: FileManager = .default)
    -> URL?
  {
    guard let name = defaults.string(forKey: OnTimeSettingsKeys.customToneFileName),
      !name.isEmpty,
      !name.contains("/"),
      !name.contains(":")
    else { return nil }
    return soundsDirectory(fileManager: fileManager).appendingPathComponent(name)
  }

  static func rememberBuiltIn(_ tone: NotificationTone, defaults: UserDefaults = .standard) {
    defaults.set(tone.rawValue, forKey: OnTimeSettingsKeys.lastBuiltInTone)
  }

  static func fallbackBuiltIn(defaults: UserDefaults = .standard) -> NotificationTone {
    if let raw = defaults.string(forKey: OnTimeSettingsKeys.lastBuiltInTone),
      let tone = NotificationTone(rawValue: raw)
    {
      return tone
    }
    if let raw = defaults.string(forKey: OnTimeSettingsKeys.tone),
      let tone = NotificationTone(rawValue: raw)
    {
      return tone
    }
    return .default
  }

  static func isPlayable(url: URL) -> Bool {
    (try? AVAudioPlayer(contentsOf: url)) != nil
  }

  /// Resolves a playable completion-tone URL. If custom is selected but missing/unreadable,
  /// silently switches `notificationTone` back to the remembered built-in (or default).
  @discardableResult
  static func resolvePlayableURL(
    defaults: UserDefaults = .standard,
    bundle: Bundle = .main,
    fileManager: FileManager = .default
  ) -> URL? {
    let raw = defaults.string(forKey: OnTimeSettingsKeys.tone) ?? NotificationTone.default.rawValue

    if raw == toneRawValue {
      if let url = customFileURL(defaults: defaults, fileManager: fileManager),
        fileManager.fileExists(atPath: url.path),
        isPlayable(url: url)
      {
        return url
      }
      return recoverToBuiltIn(defaults: defaults, bundle: bundle, fileManager: fileManager)
    }

    if let tone = NotificationTone(rawValue: raw),
      let url = bundle.url(forResource: tone.rawValue, withExtension: "wav")
    {
      return url
    }

    let fallback = fallbackBuiltIn(defaults: defaults)
    defaults.set(fallback.rawValue, forKey: OnTimeSettingsKeys.tone)
    return bundle.url(forResource: fallback.rawValue, withExtension: "wav")
  }

  /// Settings-load recovery: if custom is selected but broken, reset picker to fallback.
  static func recoverSelectionIfNeeded(
    defaults: UserDefaults = .standard,
    fileManager: FileManager = .default
  ) -> String {
    let raw = defaults.string(forKey: OnTimeSettingsKeys.tone) ?? NotificationTone.default.rawValue
    guard raw == toneRawValue else {
      if let tone = NotificationTone(rawValue: raw) {
        return tone.rawValue
      }
      let fallback = fallbackBuiltIn(defaults: defaults)
      defaults.set(fallback.rawValue, forKey: OnTimeSettingsKeys.tone)
      return fallback.rawValue
    }
    if let url = customFileURL(defaults: defaults, fileManager: fileManager),
      fileManager.fileExists(atPath: url.path),
      isPlayable(url: url)
    {
      return toneRawValue
    }
    let fallback = fallbackBuiltIn(defaults: defaults)
    defaults.set(fallback.rawValue, forKey: OnTimeSettingsKeys.tone)
    if !hasInstalledCustom(defaults: defaults, fileManager: fileManager) {
      clearMetadata(defaults: defaults)
    }
    return fallback.rawValue
  }

  @discardableResult
  static func install(
    from sourceURL: URL,
    defaults: UserDefaults = .standard,
    fileManager: FileManager = .default
  ) throws -> URL {
    let ext = sourceURL.pathExtension.lowercased()
    guard allowedExtensions.contains(ext) else {
      throw CustomSoundError.unsupportedType
    }

    let directory = soundsDirectory(fileManager: fileManager)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    // Replace any previous custom copy so only one file is retained.
    if let existing = try? fileManager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    {
      for file in existing {
        try? fileManager.removeItem(at: file)
      }
    }

    let destName = "custom.\(ext)"
    let destination = directory.appendingPathComponent(destName)
    try fileManager.copyItem(at: sourceURL, to: destination)

    guard isPlayable(url: destination) else {
      try? fileManager.removeItem(at: destination)
      throw CustomSoundError.unreadable
    }

    let label = sourceURL.deletingPathExtension().lastPathComponent
    defaults.set(destName, forKey: OnTimeSettingsKeys.customToneFileName)
    defaults.set(label, forKey: OnTimeSettingsKeys.customToneDisplayName)
    defaults.set(toneRawValue, forKey: OnTimeSettingsKeys.tone)
    return destination
  }

  static func clear(
    defaults: UserDefaults = .standard,
    fileManager: FileManager = .default
  ) {
    if let url = customFileURL(defaults: defaults, fileManager: fileManager) {
      try? fileManager.removeItem(at: url)
    }
    // Best-effort: clear leftover files in the sounds directory.
    let directory = soundsDirectory(fileManager: fileManager)
    if let existing = try? fileManager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    {
      for file in existing {
        try? fileManager.removeItem(at: file)
      }
    }
    clearMetadata(defaults: defaults)
    let fallback = fallbackBuiltIn(defaults: defaults)
    defaults.set(fallback.rawValue, forKey: OnTimeSettingsKeys.tone)
  }

  private static func clearMetadata(defaults: UserDefaults) {
    defaults.removeObject(forKey: OnTimeSettingsKeys.customToneFileName)
    defaults.removeObject(forKey: OnTimeSettingsKeys.customToneDisplayName)
  }

  private static func recoverToBuiltIn(
    defaults: UserDefaults,
    bundle: Bundle,
    fileManager: FileManager
  ) -> URL? {
    let fallback = fallbackBuiltIn(defaults: defaults)
    defaults.set(fallback.rawValue, forKey: OnTimeSettingsKeys.tone)
    if !hasInstalledCustom(defaults: defaults, fileManager: fileManager) {
      clearMetadata(defaults: defaults)
    }
    return bundle.url(forResource: fallback.rawValue, withExtension: "wav")
  }

  enum CustomSoundError: Error {
    case unsupportedType
    case unreadable
  }
}

enum NotificationRepeatOption: Int, CaseIterable, Identifiable {
  case none = 0
  case five = 5
  case ten = 10
  case infinite = -1

  static let `default` = NotificationRepeatOption.none

  var id: Int { rawValue }

  var displayName: String {
    switch self {
    case .none:
      return "Once"
    case .five:
      return "5 times"
    case .ten:
      return "10 times"
    case .infinite:
      return "Until cleared"
    }
  }

  var repeatLimit: Int? {
    switch self {
    case .none:
      return 1
    case .five:
      return 5
    case .ten:
      return 10
    case .infinite:
      return nil
    }
  }
}

/// Legacy discrete tone volumes — kept for UserDefaults migration only.
enum NotificationVolume: String, CaseIterable, Identifiable {
  case ultraLow = "ultra-low"
  case low
  case medium
  case high

  static let `default` = NotificationVolume.medium

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .ultraLow:
      return "Very low"
    case .low:
      return "Low"
    case .medium:
      return "Medium"
    case .high:
      return "High"
    }
  }

  var level: Float {
    switch self {
    case .ultraLow:
      return 0.2
    case .low:
      return 0.35
    case .medium:
      return 0.7
    case .high:
      return 1.0
    }
  }

  /// Map old presets onto the 0...2 gain scale (medium → 50% default).
  var gainEquivalent: Double {
    switch self {
    case .ultraLow:
      return 0.4
    case .low:
      return 0.7
    case .medium:
      return AudioDefaults.focusSoundVolume
    case .high:
      return AudioDefaults.focusSoundVolumeMax
    }
  }
}

enum DefaultTimeUnit: String, CaseIterable, Identifiable {
  case seconds
  case minutes
  case hours

  static let `default` = DefaultTimeUnit.minutes

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .seconds:
      return "Seconds"
    case .minutes:
      return "Minutes"
    case .hours:
      return "Hours"
    }
  }

  var multiplier: Double {
    switch self {
    case .seconds:
      return 1
    case .minutes:
      return 60
    case .hours:
      return 3600
    }
  }
}

/// Shared Seconds / Tenths readout for countdown, Pomodoro, and stopwatch.
enum DisplayPrecision: String, CaseIterable, Identifiable {
  case seconds
  case tenths

  /// Removed option; migrated to `.tenths` (closest remaining sub-second precision).
  private static let legacyHundredthsRawValue = "hundredths"

  static let `default` = DisplayPrecision.seconds

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .seconds:
      return "Seconds"
    case .tenths:
      return "Tenths"
    }
  }

  /// Fractional digits after MM:SS (0 / 1).
  var fractionDigits: Int {
    switch self {
    case .seconds: return 0
    case .tenths: return 1
    }
  }

  /// Main-run-loop timer interval while any timer mode is running.
  var tickInterval: TimeInterval {
    switch self {
    case .seconds: return 0.25
    case .tenths: return 0.05
    }
  }

  var tickTolerance: TimeInterval {
    switch self {
    case .seconds: return 0.05
    case .tenths: return 0.02
    }
  }

  /// Copy legacy `stopwatchPrecision` into `displayPrecision`, and coerce removed hundredths → tenths.
  static func migrateIfNeeded(defaults: UserDefaults = .standard) {
    if defaults.object(forKey: OnTimeSettingsKeys.displayPrecision) == nil,
      let legacy = defaults.string(forKey: OnTimeSettingsKeys.stopwatchPrecision)
    {
      defaults.set(legacy, forKey: OnTimeSettingsKeys.displayPrecision)
    }
    coerceHundredthsIfNeeded(key: OnTimeSettingsKeys.displayPrecision, defaults: defaults)
    coerceHundredthsIfNeeded(key: OnTimeSettingsKeys.stopwatchPrecision, defaults: defaults)
  }

  private static func coerceHundredthsIfNeeded(key: String, defaults: UserDefaults) {
    guard defaults.string(forKey: key) == legacyHundredthsRawValue else { return }
    defaults.set(DisplayPrecision.tenths.rawValue, forKey: key)
  }

  private static func parse(_ raw: String) -> DisplayPrecision? {
    if raw == legacyHundredthsRawValue { return .tenths }
    return DisplayPrecision(rawValue: raw)
  }

  static func current(defaults: UserDefaults = .standard) -> DisplayPrecision {
    if let raw = defaults.string(forKey: OnTimeSettingsKeys.displayPrecision),
      let value = parse(raw)
    {
      return value
    }
    if let raw = defaults.string(forKey: OnTimeSettingsKeys.stopwatchPrecision),
      let value = parse(raw)
    {
      return value
    }
    return .default
  }

  /// Formats elapsed stopwatch time. Truncates (does not round) so each full
  /// fractional cycle advances the next higher unit.
  static func formatElapsed(elapsed: TimeInterval, precision: DisplayPrecision) -> String {
    let clamped = max(0, elapsed)
    let scale = pow(10.0, Double(precision.fractionDigits))
    let quantized = floor(clamped * scale + 1e-9) / scale
    return formatQuantized(quantized, precision: precision)
  }

  /// Formats countdown / Pomodoro remaining. Ceils to the display quantum so the
  /// readout never shows all zeros while time remains; completion still uses true zero.
  static func formatRemaining(remaining: TimeInterval, precision: DisplayPrecision) -> String {
    let clamped = max(0, remaining)
    let scale = pow(10.0, Double(precision.fractionDigits))
    let quantized = ceil(clamped * scale) / scale
    return formatQuantized(quantized, precision: precision)
  }

  private static func formatQuantized(_ quantized: TimeInterval, precision: DisplayPrecision) -> String {
    let wholeSeconds = Int(floor(quantized + 1e-9))
    let fractional = max(0, quantized - Double(wholeSeconds))

    let hours = wholeSeconds / 3600
    let minutes = (wholeSeconds % 3600) / 60
    let seconds = wholeSeconds % 60
    let base: String
    if hours > 0 {
      base = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    } else {
      base = String(format: "%02d:%02d", minutes, seconds)
    }

    switch precision {
    case .seconds:
      return base
    case .tenths:
      let tenths = Int(floor(fractional * 10 + 1e-9)) % 10
      return base + String(format: ".%d", tenths)
    }
  }

  /// Discrete display unit for elapsed time (floor) — avoids redundant `@Published` updates.
  func displayUnit(forElapsed elapsed: TimeInterval) -> Int {
    let clamped = max(0, elapsed)
    let scale = pow(10.0, Double(fractionDigits))
    return Int(floor(clamped * scale + 1e-9))
  }

  /// Discrete display unit for remaining time (ceil) — matches `formatRemaining`.
  func displayUnit(forRemaining remaining: TimeInterval) -> Int {
    let clamped = max(0, remaining)
    let scale = pow(10.0, Double(fractionDigits))
    return Int(ceil(clamped * scale))
  }
}

enum MenuBarIconSize: String, CaseIterable, Identifiable {
  case small
  case medium
  case large

  static let `default` = MenuBarIconSize.medium

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .small:
      return "Small"
    case .medium:
      return "Medium"
    case .large:
      return "Large"
    }
  }
}

enum MenuBarIcon: String, CaseIterable, Identifiable {
  case timer
  case clock
  case deskClock
  case graduationCap
  case hourglassBottomHalfFilled
  case rosette
  case stopwatch
  case hourglass
  case gaugeRange

  static let `default` = MenuBarIcon.gaugeRange

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .timer:
      return "Timer"
    case .clock:
      return "Clock"
    case .deskClock:
      return "Desk clock"
    case .graduationCap:
      return "Graduation cap"
    case .hourglassBottomHalfFilled:
      return "Hourglass half"
    case .rosette:
      return "Rosette"
    case .stopwatch:
      return "Stopwatch"
    case .hourglass:
      return "Hourglass"
    case .gaugeRange:
      return "Gauge"
    }
  }

  /// SF Symbol name used to render the menu-bar glyph. Not shown in UI.
  var systemSymbolName: String {
    switch self {
    case .timer:
      return "timer"
    case .clock:
      return "clock"
    case .deskClock:
      return "deskclock"
    case .graduationCap:
      return "graduationcap"
    case .hourglassBottomHalfFilled:
      return "hourglass.bottomhalf.filled"
    case .rosette:
      return "rosette"
    case .stopwatch:
      return "stopwatch"
    case .hourglass:
      return "hourglass"
    case .gaugeRange:
      return "gauge.range.33to100.dotted.with.needle"
    }
  }

  static func current(defaults: UserDefaults = .standard) -> MenuBarIcon {
    let raw = defaults.string(forKey: OnTimeSettingsKeys.menuBarIcon) ?? ""
    return MenuBarIcon(rawValue: raw) ?? .default
  }

  func templateImage(size: NSSize) -> NSImage {
    let cacheKey = "\(rawValue)_\(Int(size.width * 10))x\(Int(size.height * 10))"
    if let cached = Self.templateImageCache[cacheKey] {
      return cached
    }

    let pointSize = max(size.width, size.height)
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    let image: NSImage
    if let symbol = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: displayName),
      let configured = symbol.withSymbolConfiguration(config)
    {
      image = configured.copy() as? NSImage ?? configured
    } else {
      let base = NSImage(named: "hourglass") ?? NSImage()
      image = base.copy() as? NSImage ?? base
    }
    image.isTemplate = true
    image.size = size
    Self.templateImageCache[cacheKey] = image
    return image
  }

  private static var templateImageCache: [String: NSImage] = [:]
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
  case classic
  case ringAndTime
  case ringOnly
  case iconOnly

  static let `default` = MenuBarStyle.classic

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .classic:
      return "Classic"
    case .ringAndTime:
      return "Ring + time"
    case .ringOnly:
      return "Ring only"
    case .iconOnly:
      return "Icon only"
    }
  }

  var revealsTimeOnHover: Bool {
    self == .ringOnly || self == .iconOnly
  }

  /// Stopwatch has no progress ring — fall back to a non-ring presentation.
  func styleForStopwatch() -> MenuBarStyle {
    switch self {
    case .ringAndTime:
      return .classic
    case .ringOnly:
      return .iconOnly
    case .classic, .iconOnly:
      return self
    }
  }
}

enum MenuBarFontStyle: String, CaseIterable, Identifiable {
  case systemMonospaced
  case sfMono
  case rounded
  case serif
  case manrope

  static let `default` = MenuBarFontStyle.systemMonospaced

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .systemMonospaced:
      return "System mono"
    case .sfMono:
      return "SF Mono"
    case .rounded:
      return "Rounded"
    case .serif:
      return "Serif"
    case .manrope:
      return "Manrope"
    }
  }

  func menuBarFont(size: CGFloat = NSFont.systemFontSize) -> NSFont {
    let base: NSFont
    switch self {
    case .systemMonospaced:
      // Already tabular; still run through withMonospacedDigits for a single path.
      base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    case .sfMono:
      base = NSFont(name: "SF Mono", size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    case .rounded:
      base = NSFont.systemFont(ofSize: size, weight: .regular).withDesign(.rounded)
        ?? NSFont.systemFont(ofSize: size)
    case .serif:
      base = NSFont.systemFont(ofSize: size, weight: .regular).withDesign(.serif)
        ?? NSFont.systemFont(ofSize: size)
    case .manrope:
      base = NSFont(name: "Manrope", size: size)
        ?? NSFont.systemFont(ofSize: size, weight: .medium)
    }
    return base.withMonospacedDigits()
  }
}

private extension NSFont {
  func withDesign(_ design: NSFontDescriptor.SystemDesign) -> NSFont? {
    guard let descriptor = fontDescriptor.withDesign(design) else { return nil }
    return NSFont(descriptor: descriptor, size: pointSize)
  }

  /// Prefer tabular/monospaced digit glyphs so menu-bar timer width stays stable as digits change.
  func withMonospacedDigits() -> NSFont {
    let featureSettings: [[NSFontDescriptor.FeatureKey: Any]] = [[
      .typeIdentifier: kNumberSpacingType,
      .selectorIdentifier: kMonospacedNumbersSelector
    ]]
    let descriptor = fontDescriptor.addingAttributes([.featureSettings: featureSettings])
    return NSFont(descriptor: descriptor, size: pointSize) ?? self
  }
}

enum MenuButtonSize: String, CaseIterable, Identifiable {
  case small
  case medium
  case large

  static let `default` = MenuButtonSize.medium

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .small:
      return "Small"
    case .medium:
      return "Medium"
    case .large:
      return "Large"
    }
  }

  var iconPointSize: CGFloat {
    switch self {
    case .small:
      return 16
    case .medium:
      return 20
    case .large:
      return 24
    }
  }

  var buttonPointSize: CGFloat {
    switch self {
    case .small:
      return 24
    case .medium:
      return 28
    case .large:
      return 34
    }
  }
}

enum MenuButtonBrightness: String, CaseIterable, Identifiable {
  case dim
  case normal
  case bright

  static let `default` = MenuButtonBrightness.normal

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .dim:
      return "Dim"
    case .normal:
      return "Normal"
    case .bright:
      return "Bright"
    }
  }
}
