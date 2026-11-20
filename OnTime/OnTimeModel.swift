import AVFoundation
import AppKit
import Foundation
import UserNotifications

final class OnTimeModel: ObservableObject {
  /// Live session used by the menu bar, `ontime://` URL handling, and App Intents.
  @MainActor static let shared = OnTimeModel()

  enum TimerMode {
    case countdown
    case stopwatch
  }

  private enum NotificationContext {
    case duration(TimeInterval)
    case timeOfDay(String)
  }

  @Published var remaining: TimeInterval = 0
  @Published var elapsed: TimeInterval = 0
  @Published var mode: TimerMode = .countdown
  @Published var isRunning = false
  @Published var isPaused = false
  @Published var isFinished = false
  @Published var inputDuration = ""
  @Published private(set) var isTimeOfDayCountdown = false
  @Published private(set) var canRepeat = false
  @Published private(set) var pomodoroSession: PomodoroSession?
  @Published private(set) var pomodoroLabel: String = ""
  @Published private(set) var pomodoroCompleted = false

  private var timer: Timer?
  private var targetDate: Date?
  private var startDate: Date?
  private var alarmPlayer: AVAudioPlayer?
  private var alarmRepeatTimer: Timer?
  private var alarmRepeatCount = 0
  private var alarmRepeatLimit: Int?
  private let alarmMinInterval: TimeInterval = 0.1
  /// Last published display quantum (precision unit for countdown / Pomodoro / stopwatch).
  private var lastDisplayedSecond: Int?
  private var notificationContext: NotificationContext?
  private var lastInput: String?
  private var totalDuration: TimeInterval = 0
  private let maxAdjustmentSeconds: TimeInterval = 24 * 60 * 60
  private let focusPlayer = OnTimeFocusPlayer()
  private var audioDefaultsObserver: NSObjectProtocol?
  /// Fingerprint of settings that affect live audio / tick rate — skip no-op churn.
  private var lastRelevantDefaultsFingerprint: String?
  /// Optional hook for session logging (Phase 4).
  var eventLogger: ((String, [String: String]) -> Void)?

  init() {
    lastRelevantDefaultsFingerprint = relevantDefaultsFingerprint()
    audioDefaultsObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: UserDefaults.standard,
      queue: .main
    ) { [weak self] _ in
      self?.handleRelevantDefaultsChange()
    }
  }

  deinit {
    if let audioDefaultsObserver {
      NotificationCenter.default.removeObserver(audioDefaultsObserver)
    }
  }

  /// 0...1 progress for countdown; stopwatch returns 0.
  var progressFraction: Double {
    guard mode == .countdown, totalDuration > 0 else { return 0 }
    let clamped = min(max(remaining, 0), totalDuration)
    return 1.0 - (clamped / totalDuration)
  }

  var endsAtSublabel: String? {
    guard isRunning, mode == .countdown, !isFinished else { return nil }
    guard let targetDate else { return nil }
    return "Ends at \(formattedTimeString(for: targetDate))"
  }

  var phaseBadgeText: String? {
    guard let session = pomodoroSession, session.isActive else {
      if mode == .stopwatch { return "Stopwatch" }
      return isRunning ? "Countdown" : nil
    }
    return session.phaseDescription(includeCycle: session.currentPhase == .work)
  }

  var formattedRemaining: String {
    let precision = DisplayPrecision.current()
    switch mode {
    case .stopwatch:
      return DisplayPrecision.formatElapsed(elapsed: elapsed, precision: precision)
    case .countdown:
      return DisplayPrecision.formatRemaining(remaining: remaining, precision: precision)
    }
  }

  var formattedStatusText: String {
    pomodoroLabel.isEmpty ? formattedRemaining : "\(pomodoroLabel) \(formattedRemaining)"
  }

  var timeOfDayEndTooltip: String? {
    endsAtSublabel
  }

  func previewForInput(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let lower = trimmed.lowercased()

    if lower == "p" || lower == "pom" || lower == "pomo" || lower == "pomodoro" {
      return "Start Pomodoro"
    }
    if lower == "sw" || lower == "stopwatch" {
      return "Start stopwatch"
    }
    if isSkipInput(lower) {
      return skipPomodoroPreview()
    }
    if let relative = parsedRelativeAdjustment(from: lower) {
      // Stopwatch is count-up; relative add/subtract does not apply.
      if mode == .stopwatch, isRunning, !isFinished {
        return nil
      }
      let magnitude = formatCompactDuration(abs(relative))
      if relative >= 0 {
        if hasAdjustableCountdown {
          return "Add \(magnitude) to current timer"
        }
        // Idle / finished: positive relative starts a fresh countdown — never "Add …".
        return "Start \(magnitude) timer"
      }
      // Negative relative only makes sense with an adjustable countdown.
      if hasAdjustableCountdown {
        return "Subtract \(magnitude) from current timer"
      }
      return nil
    }
    if parsedTimeOfDayInterval(from: lower) != nil {
      return "Until \(trimmed)"
    }
    let duration = parsedDuration(from: lower)
    guard duration > 0 else { return nil }
    return formatCompactDuration(duration)
  }

  @discardableResult
  func startFromInputs() -> Bool {
    let rawInput = inputDuration.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmed = rawInput.lowercased()
    guard !trimmed.isEmpty else { return false }
    if trimmed == "p" || trimmed == "pom" || trimmed == "pomo" || trimmed == "pomodoro" {
      notificationContext = nil
      lastInput = nil
      startPomodoro()
      inputDuration = ""
      return true
    }

    if trimmed == "sw" || trimmed == "stopwatch" {
      notificationContext = nil
      lastInput = nil
      startStopwatch()
      inputDuration = ""
      return true
    }

    if isSkipInput(trimmed) {
      guard skipPomodoroPhase() else { return false }
      inputDuration = ""
      return true
    }

    if let relative = parsedRelativeAdjustment(from: trimmed) {
      return applyRelativeAdjustment(relative, clearingInput: true)
    }

    if let interval = parsedTimeOfDayInterval(from: trimmed) {
      notificationContext = .timeOfDay(rawInput)
      start(duration: interval, isTimeOfDay: true)
      lastInput = rawInput
      inputDuration = ""
      updateRepeatAvailability()
      return true
    }
    let duration = parsedDuration(from: trimmed)
    guard duration > 0 else { return false }
    notificationContext = .duration(duration)
    start(duration: duration, isTimeOfDay: false)
    lastInput = rawInput
    inputDuration = ""
    updateRepeatAvailability()
    return true
  }

  @discardableResult
  func applyRelativeAdjustment(_ delta: TimeInterval, clearingInput: Bool = false) -> Bool {
    let clampedDelta = min(max(delta, -maxAdjustmentSeconds), maxAdjustmentSeconds)
    guard clampedDelta != 0 else { return false }

    // Active countdown or Pomodoro (running or paused): shift remaining + targetDate.
    if hasAdjustableCountdown {
      addTime(clampedDelta)
      if clearingInput { inputDuration = "" }
      return true
    }

    // Stopwatch: relative adjustments are intentionally ignored.
    if mode == .stopwatch, isRunning, !isFinished {
      return false
    }

    // Idle or finished alarm: positive relative starts a fresh countdown; negative is invalid.
    if clampedDelta > 0 {
      notificationContext = .duration(clampedDelta)
      start(duration: clampedDelta, isTimeOfDay: false)
      lastInput = nil
      if clearingInput { inputDuration = "" }
      updateRepeatAvailability()
      return true
    }
    return false
  }

  func addTime(_ interval: TimeInterval) {
    guard hasAdjustableCountdown else { return }
    let next = min(max(remaining + interval, 0), maxAdjustmentSeconds)
    let applied = next - remaining
    remaining = next
    totalDuration = max(totalDuration + applied, next)
    if isPaused {
      targetDate = nil
    } else if let targetDate {
      self.targetDate = targetDate.addingTimeInterval(applied)
    } else {
      self.targetDate = Date().addingTimeInterval(next)
    }
    lastDisplayedSecond = nil
    if next <= 0 {
      finish()
    }
  }

  func startPomodoro() {
    let preferences = PomodoroPreferences()
    let session = PomodoroSession(from: preferences)

    start(duration: session.workDuration, isTimeOfDay: false, playFocusAudio: false)

    pomodoroSession = session
    updatePomodoroLabel()
    updateFocusAudio(playWindup: true)
  }

  func start(
    duration: TimeInterval, isTimeOfDay: Bool = false, playFocusAudio: Bool = true
  ) {
    stop()
    mode = .countdown
    remaining = duration
    totalDuration = duration
    isRunning = true
    isPaused = false
    isFinished = false
    isTimeOfDayCountdown = isTimeOfDay
    targetDate = Date().addingTimeInterval(duration)
    if isTimeOfDay {
      if notificationContext == nil, let targetDate {
        notificationContext = .timeOfDay(formattedTimeString(for: targetDate))
      }
    } else {
      notificationContext = .duration(duration)
    }
    lastDisplayedSecond = nil
    scheduleTimer()
    if playFocusAudio {
      updateFocusAudio(playWindup: true)
    }
    eventLogger?("timer_start", [
      "mode": "countdown",
      "duration": String(Int(duration.rounded())),
    ])
  }

  /// Starts a countdown from the menu-bar stretch gesture and enables Repeat after finish.
  func startStretchedCountdown(duration: TimeInterval) {
    let clamped = max(1, duration)
    let label = formatCompactDuration(clamped)
    start(duration: clamped, isTimeOfDay: false, playFocusAudio: true)
    // `start` → `stop` clears `lastInput`; restore after so Repeat works.
    lastInput = label
    inputDuration = label
    updateRepeatAvailability()
  }

  func startStopwatch() {
    stop()
    mode = .stopwatch
    elapsed = 0
    isRunning = true
    isPaused = false
    isFinished = false
    isTimeOfDayCountdown = false
    startDate = Date()
    lastDisplayedSecond = nil
    notificationContext = nil
    scheduleTimer()
    updateFocusAudio(playWindup: true)
    eventLogger?("timer_start", ["mode": "stopwatch"])
  }

  func pause() {
    guard isRunning, !isPaused, !isTimeOfDayCountdown else { return }
    if mode == .countdown, let targetDate {
      remaining = max(0, targetDate.timeIntervalSinceNow)
    } else if mode == .stopwatch, let startDate {
      // Freeze fractional digits at the pause instant.
      elapsed = Date().timeIntervalSince(startDate)
    }
    isPaused = true
    targetDate = nil
    timer?.invalidate()
    timer = nil
    focusPlayer.stopTicking()
    eventLogger?("timer_pause", [:])
  }

  func resume() {
    guard isRunning, isPaused else { return }
    stopAlarm()
    guard !isFinished else { return }
    switch mode {
    case .countdown:
      guard remaining > 0 else { return }
      isPaused = false
      targetDate = Date().addingTimeInterval(remaining)
      lastDisplayedSecond = nil
      scheduleTimer()
    case .stopwatch:
      isPaused = false
      startDate = Date().addingTimeInterval(-elapsed)
      lastDisplayedSecond = nil
      scheduleTimer()
    }
    updateFocusAudio(playWindup: false)
    eventLogger?("timer_resume", [:])
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    targetDate = nil
    startDate = nil
    isRunning = false
    isPaused = false
    isTimeOfDayCountdown = false
    isFinished = false
    remaining = 0
    elapsed = 0
    totalDuration = 0
    inputDuration = ""
    lastInput = nil
    mode = .countdown
    lastDisplayedSecond = nil
    notificationContext = nil
    pomodoroSession = nil
    pomodoroLabel = ""
    pomodoroCompleted = false
    stopAlarm()
    focusPlayer.stopTicking()
    updateRepeatAvailability()
    eventLogger?("timer_stop", [:])
  }

  @discardableResult
  func skipPomodoroPhase() -> Bool {
    guard isRunning, !isFinished, mode == .countdown, pomodoroSession?.isActive == true else {
      return false
    }
    finish(skipped: true)
    return true
  }

  /// Called on timer tick and after wake to drop stale countdowns past the overrun limit.
  func checkSleepOverrun(now: Date = Date()) {
    guard isRunning, !isPaused, !isFinished, mode == .countdown, let targetDate else { return }
    let timeLeft = targetDate.timeIntervalSince(now)
    let limit = currentOverrunTimeLimit()
    if timeLeft < limit {
      handleOverrunExpired(timeLeft: timeLeft)
    }
  }

  /// Testable duration parser for absolute NL inputs (no relative tokens).
  func parsedDuration(from input: String) -> TimeInterval {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return 0 }

    if let interval = parsedColonDuration(from: trimmed) {
      return interval
    }

    if let composite = parsedCompositeDuration(from: trimmed) {
      return composite
    }

    let numberChars = "0123456789."
    let numberPart = trimmed.prefix { numberChars.contains($0) }
    let unitPart = trimmed.dropFirst(numberPart.count)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let value = Double(numberPart) ?? 0
    guard value > 0 else { return 0 }

    let multiplier: Double
    if unitPart.isEmpty {
      multiplier = currentDefaultUnit().multiplier
    } else {
      guard let parsedUnit = unitForToken(unitPart) else { return 0 }
      multiplier = parsedUnit.multiplier
    }

    return max(0, value * multiplier)
  }

  func parsedRelativeAdjustment(from input: String) -> TimeInterval? {
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !text.isEmpty else { return nil }

    // Normalize common unicode plus/minus signs to ASCII.
    if text.hasPrefix("＋") || text.hasPrefix("⁺") {
      text = "+" + text.dropFirst()
    } else if text.hasPrefix("−") || text.hasPrefix("–") || text.hasPrefix("—") || text.hasPrefix("﹣") {
      text = "-" + text.dropFirst()
    }

    var sign: Double = 0
    if text.hasPrefix("+") {
      sign = 1
      text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    } else if text.hasPrefix("-") {
      sign = -1
      text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    } else if text.hasPrefix("add ") || text.hasPrefix("plus ") {
      sign = 1
      text = text.replacingOccurrences(of: "^(add|plus)\\s+", with: "", options: .regularExpression)
    } else if text.hasPrefix("subtract ") || text.hasPrefix("minus ") {
      sign = -1
      text = text.replacingOccurrences(of: "^(subtract|minus)\\s+", with: "", options: .regularExpression)
    } else {
      return nil
    }

    let duration = parsedDuration(from: text)
    guard duration > 0 else { return nil }
    return sign * duration
  }

  /// Countdown/Pomodoro that can accept +/− remaining adjustments (running or paused).
  private var hasAdjustableCountdown: Bool {
    isRunning && mode == .countdown && !isFinished
  }

  private func isSkipInput(_ lower: String) -> Bool {
    switch lower {
    case "skip", "skip phase", "skip break", "skip work":
      return true
    default:
      return false
    }
  }

  private func skipPomodoroPreview() -> String? {
    guard isRunning, !isFinished, mode == .countdown,
      let session = pomodoroSession, session.isActive
    else {
      return nil
    }
    switch session.currentPhase {
    case .work:
      return "Skip Work"
    case .shortBreak, .longBreak:
      return "Skip Break"
    }
  }

  private func parsedCompositeDuration(from input: String) -> TimeInterval? {
    var cleaned = input
    let conjunctions = [" and ", " plus ", " & ", ",", "+"]
    for token in conjunctions {
      cleaned = cleaned.replacingOccurrences(of: token, with: " ")
    }
    cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let scanner = Scanner(string: cleaned)
    scanner.charactersToBeSkipped = .whitespacesAndNewlines

    var total: Double = 0
    var lastUnit: ParsedUnit?
    var matchedAny = false

    while !scanner.isAtEnd {
      guard let value = scanner.scanDouble(), value > 0 else { return nil }

      let unit = scanner.scanCharacters(from: .letters)?.lowercased()
      if let unit, !unit.isEmpty {
        guard let parsedUnit = unitForToken(unit) else { return nil }
        total += value * parsedUnit.multiplier
        lastUnit = parsedUnit
        matchedAny = true
      } else {
        guard let currentUnit = lastUnit,
          let nextUnit = nextSmallerUnit(after: currentUnit)
        else {
          return nil
        }
        total += value * nextUnit.multiplier
        lastUnit = nextUnit
        matchedAny = true
      }
    }

    return matchedAny && total > 0 ? total : nil
  }

  func formatCompactDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(0, Int(duration.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    var parts: [String] = []
    if hours > 0 { parts.append("\(hours)h") }
    if minutes > 0 { parts.append("\(minutes)m") }
    if seconds > 0 || parts.isEmpty { parts.append("\(seconds)s") }
    return parts.joined(separator: " ")
  }

  private func parsedColonDuration(from input: String) -> TimeInterval? {
    guard input.contains(":") else { return nil }
    let compact = input.replacingOccurrences(of: " ", with: "")
    guard !compact.contains("am"), !compact.contains("pm") else { return nil }

    let parts = compact.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2 || parts.count == 3 else { return nil }
    let firstPart = String(parts[0])
    let secondPart = String(parts[1])
    let first: Int
    if firstPart.isEmpty, compact.hasPrefix(":") {
      first = 0
    } else if let parsed = Int(firstPart) {
      first = parsed
    } else {
      return nil
    }
    guard let second = Int(secondPart) else { return nil }
    guard first >= 0, second >= 0 else { return nil }

    if parts.count == 2 {
      guard second < 60 else { return nil }
      return Double(first * 60 + second)
    }

    guard let third = Int(parts[2]), third >= 0 else { return nil }
    guard second < 60, third < 60 else { return nil }
    return Double(first * 3600 + second * 60 + third)
  }

  private enum ParsedUnit {
    case hour
    case minute
    case second

    var multiplier: Double {
      switch self {
      case .hour:
        return 3600
      case .minute:
        return 60
      case .second:
        return 1
      }
    }
  }

  private func unitForToken(_ unit: String) -> ParsedUnit? {
    switch unit {
    case "m", "min", "mins", "minute", "minutes":
      return .minute
    case "s", "sec", "secs", "second", "seconds":
      return .second
    case "h", "hr", "hrs", "hour", "hours":
      return .hour
    default:
      return nil
    }
  }

  private func nextSmallerUnit(after unit: ParsedUnit) -> ParsedUnit? {
    switch unit {
    case .hour:
      return .minute
    case .minute:
      return .second
    case .second:
      return nil
    }
  }

  private func parsedTimeOfDayInterval(from input: String) -> TimeInterval? {
    var compact = input.replacingOccurrences(of: " ", with: "")
    compact = compact.replacingOccurrences(of: ".", with: "")
    if compact == "noon" {
      return intervalUntil(hour: 12, minute: 0)
    }
    if compact == "midnight" {
      return intervalUntil(hour: 0, minute: 0)
    }

    if compact.hasSuffix("a") {
      compact.removeLast()
      compact += "am"
    } else if compact.hasSuffix("p") {
      compact.removeLast()
      compact += "pm"
    }

    guard compact.contains("am") || compact.contains("pm") else {
      return nil
    }

    if !compact.contains(":") {
      let suffix = compact.suffix(2)
      let prefix = compact.dropLast(2)
      if suffix == "am" || suffix == "pm", prefix.count >= 3, prefix.allSatisfy({ $0.isNumber }) {
        let minutes = prefix.suffix(2)
        let hours = prefix.dropLast(2)
        compact = "\(hours):\(minutes)\(suffix)"
      }
    }

    let formats = ["h:mma", "ha", "H:mm", "HH:mm"]
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current

    for format in formats {
      formatter.dateFormat = format
      guard let parsed = formatter.date(from: compact) else { continue }
      let components = Calendar.current.dateComponents([.hour, .minute], from: parsed)
      guard let hour = components.hour, let minute = components.minute else { continue }
      if let interval = intervalUntil(hour: hour, minute: minute) {
        return interval
      }
    }

    return nil
  }

  private func intervalUntil(hour: Int, minute: Int) -> TimeInterval? {
    let calendar = Calendar.current
    let now = Date()
    guard var target = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else {
      return nil
    }
    if target <= now {
      guard let next = calendar.date(byAdding: .day, value: 1, to: target) else { return nil }
      target = next
    }
    let interval = target.timeIntervalSince(now)
    return interval > 0 ? interval : nil
  }

  private func scheduleTimer() {
    timer?.invalidate()
    let precision = DisplayPrecision.current()
    let newTimer = Timer(timeInterval: precision.tickInterval, repeats: true) { [weak self] _ in
      self?.tick()
    }
    newTimer.tolerance = precision.tickTolerance
    RunLoop.main.add(newTimer, forMode: .common)
    timer = newTimer
  }

  private func tick() {
    switch mode {
    case .countdown:
      guard let targetDate else { return }
      let newRemaining = targetDate.timeIntervalSinceNow
      if newRemaining <= 0 {
        if newRemaining < currentOverrunTimeLimit() {
          handleOverrunExpired(timeLeft: newRemaining)
        } else {
          finish()
        }
      } else {
        let precision = DisplayPrecision.current()
        let displayUnit = precision.displayUnit(forRemaining: newRemaining)
        if displayUnit != lastDisplayedSecond {
          remaining = newRemaining
          lastDisplayedSecond = displayUnit
        }
      }
    case .stopwatch:
      guard let startDate else { return }
      let newElapsed = Date().timeIntervalSince(startDate)
      let precision = DisplayPrecision.current()
      let displayUnit = precision.displayUnit(forElapsed: newElapsed)
      if displayUnit != lastDisplayedSecond {
        elapsed = newElapsed
        lastDisplayedSecond = displayUnit
      }
    }
  }

  /// Live precision changes should refresh any running/paused readout and tick rate.
  private func handleDisplayPrecisionDefaultsChange() {
    guard isRunning else { return }
    let precision = DisplayPrecision.current()
    if isPaused {
      // Re-publish so menu bar / observers re-format with the new precision.
      switch mode {
      case .stopwatch:
        elapsed = elapsed
      case .countdown:
        remaining = remaining
      }
      return
    }
    lastDisplayedSecond = nil
    switch mode {
    case .stopwatch:
      if let startDate {
        elapsed = Date().timeIntervalSince(startDate)
        lastDisplayedSecond = precision.displayUnit(forElapsed: elapsed)
      }
    case .countdown:
      if let targetDate {
        let newRemaining = targetDate.timeIntervalSinceNow
        if newRemaining > 0 {
          remaining = newRemaining
          lastDisplayedSecond = precision.displayUnit(forRemaining: newRemaining)
        }
      }
    }
    scheduleTimer()
  }

  private func finish(skipped: Bool = false) {
    timer?.invalidate()
    timer = nil
    remaining = 0
    isRunning = true
    isPaused = true
    isTimeOfDayCountdown = false
    isFinished = true
    targetDate = nil
    mode = .countdown
    focusPlayer.stopTicking()

    // Handle Pomodoro auto-advance
    if var session = pomodoroSession, session.isActive {
      let completedPhase = session.phaseDescription(includeCycle: session.currentPhase == .work)
      let previousPhase = session.currentPhase
      let nextDuration = session.advanceToNextPhase()
      pomodoroSession = session
      updatePomodoroLabel()
      let completedDuration: TimeInterval = {
        switch previousPhase {
        case .work: return session.workDuration
        case .shortBreak: return session.shortBreakDuration
        case .longBreak: return session.longBreakDuration
        }
      }()
      eventLogger?(
        "phase_transition",
        [
          "from": "\(previousPhase)",
          "to": session.isActive ? "\(session.currentPhase)" : "done",
          "skipped": skipped ? "1" : "0",
          "duration": String(Int(completedDuration)),
          "cycle": String(session.currentCycle),
        ]
      )

      if nextDuration > 0 {
        let nextPhase = session.phaseDescription(includeCycle: session.currentPhase == .work)
        if !skipped {
          sendPomodoroAdvancingNotification(completedPhase: completedPhase, nextPhase: nextPhase)
        }

        // start() calls stop(), so restore the active Pomodoro session afterward.
        start(duration: nextDuration, isTimeOfDay: false, playFocusAudio: false)
        pomodoroSession = session
        updatePomodoroLabel()
        let pauseAfterBreak = UserDefaults.standard.bool(forKey: OnTimeSettingsKeys.pauseAfterBreak)
        let completedBreak =
          previousPhase == .shortBreak || previousPhase == .longBreak
        if pauseAfterBreak && completedBreak {
          pause()
        } else {
          updateFocusAudio(playWindup: session.currentPhase == .work)
        }
        // Completion uses the Notification tone only — do not also play focus ding
        // (that stacked a second “default” sound under custom tones).
        if !skipped {
          startAlarm()
        }
        return
      } else {
        pomodoroSession = nil
        pomodoroLabel = ""
        pomodoroCompleted = true
        sendPomodoroCompleteNotification(completedPhase: completedPhase)
        if !skipped {
          startAlarm()
        }
        updateRepeatAvailability()
        eventLogger?("timer_complete", ["mode": "pomodoro"])
        return
      }
    }

    let context = notificationContext
    let completedDuration: TimeInterval = {
      if case .duration(let duration) = context { return duration }
      return totalDuration
    }()
    notificationContext = nil
    sendFinishedNotificationIfNeeded(context: context)
    if !skipped {
      startAlarm()
    }
    updateRepeatAvailability()
    eventLogger?(
      "timer_complete",
      ["mode": "countdown", "duration": String(Int(completedDuration))]
    )
  }

  private func handleOverrunExpired(timeLeft: TimeInterval) {
    let staleRemaining = timeLeft
    timer?.invalidate()
    timer = nil
    targetDate = nil
    startDate = nil
    isRunning = false
    isPaused = false
    isFinished = false
    remaining = 0
    elapsed = 0
    totalDuration = 0
    isTimeOfDayCountdown = false
    pomodoroSession = nil
    pomodoroLabel = ""
    pomodoroCompleted = false
    stopAlarm()
    focusPlayer.stopTicking()
    updateRepeatAvailability()
    eventLogger?("overrun_expired", ["remaining": String(format: "%.1f", staleRemaining)])
    sendOverrunExpiredNotification()
  }

  /// Active focus-audio mode for the current session, if any.
  /// Pomodoro breaks return `nil` (no ticking by default). Stopwatch never dings on stop.
  func focusAudioModeForCurrentSession() -> FocusAudioMode? {
    if let session = pomodoroSession, session.isActive {
      return session.currentPhase == .work ? .pomodoroWork : nil
    }
    switch mode {
    case .countdown:
      return .countdown
    case .stopwatch:
      return .stopwatch
    }
  }

  /// Whether windup / ticking should run for the current running (non-paused) session.
  func shouldPlayFocusAudio() -> Bool {
    guard isRunning, !isPaused, !isFinished else { return false }
    guard let mode = focusAudioModeForCurrentSession() else { return false }
    return FocusAudioMode.isEnabled(mode)
  }

  /// Windup + looping tick when the active mode’s setting allows it.
  private func updateFocusAudio(playWindup: Bool) {
    guard shouldPlayFocusAudio() else {
      focusPlayer.stopTicking()
      return
    }

    if playWindup {
      focusPlayer.playWindup()
    }
    focusPlayer.startTicking()
  }

  /// Test hook: whether the focus tick sample is currently looping.
  var isFocusTickingForTesting: Bool { focusPlayer.isTickingForTesting }

  private func sendOverrunExpiredNotification() {
    guard UserDefaults.standard.bool(forKey: OnTimeSettingsKeys.showNotifications) else { return }
    let content = UNMutableNotificationContent()
    content.title = "Timer cleared"
    content.body = "A timer expired while the Mac was asleep."
    content.categoryIdentifier = NotificationIdentifiers.overrunExpiredCategory
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  private func currentOverrunTimeLimit() -> TimeInterval {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: OnTimeSettingsKeys.overrunTimeLimit) == nil {
      return AudioDefaults.overrunTimeLimit
    }
    return defaults.double(forKey: OnTimeSettingsKeys.overrunTimeLimit)
  }

  #if DEBUG
    func advancePomodoroPhaseForTesting() -> Bool {
      guard isRunning, !isFinished, mode == .countdown, pomodoroSession?.isActive == true else {
        return false
      }
      finish()
      return true
    }
  #endif

  private func sendFinishedNotificationIfNeeded(context: NotificationContext?) {
    guard UserDefaults.standard.bool(forKey: OnTimeSettingsKeys.showNotifications) else { return }
    guard let context else { return }

    let body: String
    switch context {
    case .duration(let duration):
      body = formattedDurationDescription(duration)
    case .timeOfDay(let input):
      let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
      let timeString = trimmed.isEmpty ? formattedTimeString(for: Date()) : trimmed
      body = "Reached \(timeString)"
    }

    let content = UNMutableNotificationContent()
    content.title = "Timer finished"
    content.body = body
    content.categoryIdentifier = NotificationIdentifiers.timerFinishedCategory

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }

  private func sendPomodoroAdvancingNotification(completedPhase: String, nextPhase: String) {
    guard UserDefaults.standard.bool(forKey: OnTimeSettingsKeys.showNotifications) else { return }

    let content = UNMutableNotificationContent()
    content.title = "Pomodoro"
    content.body = "\(completedPhase) complete. \(nextPhase) starting."
    content.categoryIdentifier = NotificationIdentifiers.pomodoroAdvancingCategory

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }

  private func sendPomodoroCompleteNotification(completedPhase: String) {
    guard UserDefaults.standard.bool(forKey: OnTimeSettingsKeys.showNotifications) else { return }

    let content = UNMutableNotificationContent()
    content.title = "Pomodoro"
    content.body = "\(completedPhase) complete. Session finished."
    content.categoryIdentifier = NotificationIdentifiers.pomodoroCompleteCategory

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }

  private func updatePomodoroLabel() {
    guard let session = pomodoroSession else {
      pomodoroLabel = ""
      return
    }
    pomodoroLabel = session.displayLabel()
  }

  private func formattedDurationDescription(_ duration: TimeInterval) -> String {
    let totalSeconds = max(1, Int(ceil(duration)))
    if totalSeconds < 60 {
      return "\(formattedUnit(totalSeconds, unit: "second")) timer"
    }

    let totalMinutes = Int(ceil(duration / 60.0))
    if totalMinutes < 60 {
      return "\(formattedUnit(totalMinutes, unit: "minute")) timer"
    }

    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    let hoursPart = formattedUnit(hours, unit: "hour")
    if minutes == 0 {
      return "\(hoursPart) timer"
    }
    let minutesPart = formattedUnit(minutes, unit: "minute")
    return "\(hoursPart) \(minutesPart) timer"
  }

  private func formattedUnit(_ value: Int, unit: String) -> String {
    return "\(value)-\(unit)"
  }

  private func formattedTimeString(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: date)
      .replacingOccurrences(of: "AM", with: "a.m.")
      .replacingOccurrences(of: "PM", with: "p.m.")
      .replacingOccurrences(of: "am", with: "a.m.")
      .replacingOccurrences(of: "pm", with: "p.m.")
  }

  private func startAlarm() {
    stopAlarm()
    alarmRepeatCount = 0
    alarmRepeatLimit = currentRepeatLimit()

    guard let url = CustomCompletionSound.resolvePlayableURL() else {
      NSSound(named: "Glass")?.play()
      return
    }

    do {
      let player = try AVAudioPlayer(contentsOf: url)
      player.volume = currentTonePlayerVolume()
      alarmPlayer = player
      player.play()
      alarmRepeatCount = 1

      guard alarmRepeatLimit != 1 else {
        return
      }

      let interval = max(alarmMinInterval, player.duration)
      let repeatTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
        guard let self else { return }
        if let alarmRepeatLimit = self.alarmRepeatLimit,
          self.alarmRepeatCount >= alarmRepeatLimit
        {
          self.stopAlarm()
          return
        }
        self.alarmPlayer?.currentTime = 0
        self.alarmPlayer?.play()
        self.alarmRepeatCount += 1
      }
      RunLoop.main.add(repeatTimer, forMode: .common)
      alarmRepeatTimer = repeatTimer
    } catch {
      alarmPlayer = nil
      // Custom may have become unreadable between resolve and open — fall back once more.
      if CustomCompletionSound.isCustomSelected(),
        let fallbackURL = CustomCompletionSound.resolvePlayableURL(),
        let player = try? AVAudioPlayer(contentsOf: fallbackURL)
      {
        player.volume = currentTonePlayerVolume()
        alarmPlayer = player
        player.play()
        alarmRepeatCount = 1
        return
      }
      NSSound(named: "Glass")?.play()
    }
  }

  private func stopAlarm() {
    alarmRepeatTimer?.invalidate()
    alarmRepeatTimer = nil
    alarmPlayer?.stop()
    alarmPlayer = nil
    alarmRepeatCount = 0
    alarmRepeatLimit = nil
  }

  @discardableResult
  func repeatLastInput() -> Bool {
    if pomodoroCompleted {
      startPomodoro()
      return true
    }
    guard let lastInput else { return false }
    inputDuration = lastInput
    return startFromInputs()
  }

  private func updateRepeatAvailability() {
    canRepeat = isFinished && (lastInput != nil || pomodoroCompleted)
  }

  private func currentRepeatLimit() -> Int? {
    let defaults = UserDefaults.standard
    let storedValue = defaults.object(forKey: OnTimeSettingsKeys.repeatCount) as? Int
    let option =
      NotificationRepeatOption(rawValue: storedValue ?? NotificationRepeatOption.default.rawValue)
      ?? .default
    return option.repeatLimit
  }

  private func currentTonePlayerVolume() -> Float {
    AudioDefaults.playerVolume(fromGain: AudioDefaults.notificationGain())
  }

  private func applyLiveAlarmVolumeFromDefaults() {
    guard let alarmPlayer else { return }
    alarmPlayer.setVolume(currentTonePlayerVolume(), fadeDuration: 0)
  }

  private func handleRelevantDefaultsChange() {
    let fingerprint = relevantDefaultsFingerprint()
    guard fingerprint != lastRelevantDefaultsFingerprint else { return }
    lastRelevantDefaultsFingerprint = fingerprint
    applyLiveAlarmVolumeFromDefaults()
    // Per-mode focus toggles and volumes can change while a session runs.
    updateFocusAudio(playWindup: false)
    handleDisplayPrecisionDefaultsChange()
  }

  private func relevantDefaultsFingerprint() -> String {
    let defaults = UserDefaults.standard
    let keys = [
      OnTimeSettingsKeys.volume,
      OnTimeSettingsKeys.windupVolume,
      OnTimeSettingsKeys.dingVolume,
      OnTimeSettingsKeys.tickingVolume,
      OnTimeSettingsKeys.focusAudioPomodoroWork,
      OnTimeSettingsKeys.focusAudioCountdown,
      OnTimeSettingsKeys.focusAudioStopwatch,
      OnTimeSettingsKeys.displayPrecision,
    ]
    return keys.map { key in
      String(describing: defaults.object(forKey: key) ?? "")
    }.joined(separator: "|")
  }

  private func currentDefaultUnit() -> DefaultTimeUnit {
    let raw = UserDefaults.standard.string(forKey: OnTimeSettingsKeys.defaultUnit)
    return DefaultTimeUnit(rawValue: raw ?? "") ?? .default
  }
}
