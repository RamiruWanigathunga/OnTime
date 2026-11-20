import AppKit
import XCTest
@testable import OnTime

final class PhaseControlsTests: XCTestCase {
  private var model: OnTimeModel!

  override func setUp() {
    super.setUp()
    model = OnTimeModel()
    let defaults = UserDefaults.standard
    defaults.set(1, forKey: OnTimeSettingsKeys.pomodoroWorkMinutes)
    defaults.set(1, forKey: OnTimeSettingsKeys.pomodoroShortBreakMinutes)
    defaults.set(1, forKey: OnTimeSettingsKeys.pomodoroLongBreakMinutes)
    defaults.set(2, forKey: OnTimeSettingsKeys.pomodoroCyclesPerSet)
    defaults.set(false, forKey: OnTimeSettingsKeys.pomodoroShouldLoop)
    defaults.set(false, forKey: OnTimeSettingsKeys.pauseAfterBreak)
    defaults.set(AudioDefaults.overrunTimeLimit, forKey: OnTimeSettingsKeys.overrunTimeLimit)
  }

  override func tearDown() {
    model.stop()
    model = nil
    let defaults = UserDefaults.standard
    [
      OnTimeSettingsKeys.pomodoroWorkMinutes,
      OnTimeSettingsKeys.pomodoroShortBreakMinutes,
      OnTimeSettingsKeys.pomodoroLongBreakMinutes,
      OnTimeSettingsKeys.pomodoroCyclesPerSet,
      OnTimeSettingsKeys.pomodoroShouldLoop,
      OnTimeSettingsKeys.pauseAfterBreak,
      OnTimeSettingsKeys.overrunTimeLimit,
      OnTimeSettingsKeys.focusAudioPomodoroWork,
      OnTimeSettingsKeys.focusAudioCountdown,
      OnTimeSettingsKeys.focusAudioStopwatch,
    ].forEach { defaults.removeObject(forKey: $0) }
    super.tearDown()
  }

  func testSkipPomodoroPhaseAdvances() {
    model.startPomodoro()
    XCTAssertEqual(model.pomodoroSession?.currentPhase, .work)
    XCTAssertTrue(model.skipPomodoroPhase())
    XCTAssertEqual(model.pomodoroSession?.currentPhase, .shortBreak)
  }

  func testAddFiveMinutes() {
    model.start(duration: 60)
    model.addTime(5 * 60)
    XCTAssertEqual(model.remaining, 360, accuracy: 1)
  }

  func testPauseAfterBreakLeavesPausedWork() {
    UserDefaults.standard.set(true, forKey: OnTimeSettingsKeys.pauseAfterBreak)
    model.startPomodoro()
    // work -> short break
    XCTAssertTrue(model.skipPomodoroPhase())
    XCTAssertEqual(model.pomodoroSession?.currentPhase, .shortBreak)
    // short break -> work, should pause because pauseAfterBreak
    XCTAssertTrue(model.skipPomodoroPhase())
    XCTAssertEqual(model.pomodoroSession?.currentPhase, .work)
    XCTAssertTrue(model.isPaused)
  }

  func testSleepOverrunCancelsStaleTimer() {
    UserDefaults.standard.set(-60.0, forKey: OnTimeSettingsKeys.overrunTimeLimit)
    model.start(duration: 5)
    XCTAssertTrue(model.isRunning)
    // Simulate waking long after the target date.
    model.checkSleepOverrun(now: Date().addingTimeInterval(500))
    XCTAssertFalse(model.isRunning)
    XCTAssertEqual(model.remaining, 0, accuracy: 0.1)
  }

  func testBundledNotificationTonesExist() {
    XCTAssertEqual(NotificationTone.allCases.count, 12)
    for tone in NotificationTone.allCases {
      let url = Bundle(for: OnTimeModel.self).url(forResource: tone.rawValue, withExtension: "wav")
        ?? Bundle.main.url(forResource: tone.rawValue, withExtension: "wav")
      XCTAssertNotNil(url, "Missing bundled tone: \(tone.rawValue).wav")
    }
  }

  func testCustomToneFallsBackWhenMissing() {
    let defaults = UserDefaults.standard
    let toneKeys = [
      OnTimeSettingsKeys.tone,
      OnTimeSettingsKeys.lastBuiltInTone,
      OnTimeSettingsKeys.customToneFileName,
      OnTimeSettingsKeys.customToneDisplayName,
    ]
    defer { toneKeys.forEach { defaults.removeObject(forKey: $0) } }

    defaults.set(NotificationTone.discreet.rawValue, forKey: OnTimeSettingsKeys.lastBuiltInTone)
    defaults.set(CustomCompletionSound.toneRawValue, forKey: OnTimeSettingsKeys.tone)
    defaults.set("missing-custom.wav", forKey: OnTimeSettingsKeys.customToneFileName)
    defaults.set("Gone", forKey: OnTimeSettingsKeys.customToneDisplayName)

    let bundle = Bundle(for: OnTimeModel.self)
    let url = CustomCompletionSound.resolvePlayableURL(bundle: bundle)
    XCTAssertEqual(defaults.string(forKey: OnTimeSettingsKeys.tone), NotificationTone.discreet.rawValue)
    XCTAssertEqual(url?.deletingPathExtension().lastPathComponent, "discreet")
  }

  func testCustomToneInstallAndClear() throws {
    let defaults = UserDefaults.standard
    let toneKeys = [
      OnTimeSettingsKeys.tone,
      OnTimeSettingsKeys.lastBuiltInTone,
      OnTimeSettingsKeys.customToneFileName,
      OnTimeSettingsKeys.customToneDisplayName,
    ]
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("OnTimeCustomToneTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    CustomCompletionSound.soundsDirectoryOverrideForTesting = tempRoot
    defer {
      CustomCompletionSound.soundsDirectoryOverrideForTesting = nil
      try? FileManager.default.removeItem(at: tempRoot)
      toneKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    let bundle = Bundle(for: OnTimeModel.self)
    guard let source = bundle.url(forResource: "wake-up", withExtension: "wav")
      ?? Bundle.main.url(forResource: "wake-up", withExtension: "wav")
    else {
      XCTFail("Missing wake-up.wav for install fixture")
      return
    }

    defaults.set(NotificationTone.rush.rawValue, forKey: OnTimeSettingsKeys.lastBuiltInTone)
    let installed = try CustomCompletionSound.install(from: source, defaults: defaults)
    XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
    XCTAssertEqual(defaults.string(forKey: OnTimeSettingsKeys.tone), CustomCompletionSound.toneRawValue)
    XCTAssertTrue(CustomCompletionSound.hasInstalledCustom(defaults: defaults))
    XCTAssertEqual(
      CustomCompletionSound.resolvePlayableURL(defaults: defaults, bundle: bundle)?.path,
      installed.path
    )

    CustomCompletionSound.clear(defaults: defaults)
    XCTAssertFalse(CustomCompletionSound.hasInstalledCustom(defaults: defaults))
    XCTAssertEqual(defaults.string(forKey: OnTimeSettingsKeys.tone), NotificationTone.rush.rawValue)
    XCTAssertNil(defaults.string(forKey: OnTimeSettingsKeys.customToneFileName))
  }

  func testFocusSoundDataAssetsExist() {
    let bundle = Bundle(for: OnTimeModel.self)
    for name in ["windup", "ding", "ticking"] {
      XCTAssertNotNil(
        NSDataAsset(name: name, bundle: bundle), "Missing NSDataAsset: \(name)")
    }
  }

  func testFocusAudioDefaultsEnableAllModes() {
    let defaults = UserDefaults.standard
    [
      OnTimeSettingsKeys.focusAudioPomodoroWork,
      OnTimeSettingsKeys.focusAudioCountdown,
      OnTimeSettingsKeys.focusAudioStopwatch,
    ].forEach { defaults.removeObject(forKey: $0) }

    XCTAssertTrue(FocusAudioMode.isEnabled(.pomodoroWork))
    XCTAssertTrue(FocusAudioMode.isEnabled(.countdown))
    XCTAssertTrue(FocusAudioMode.isEnabled(.stopwatch))
  }

  func testCountdownTickingRespectsSetting() {
    UserDefaults.standard.set(true, forKey: OnTimeSettingsKeys.focusAudioCountdown)
    model.start(duration: 60)
    XCTAssertTrue(model.shouldPlayFocusAudio())
    XCTAssertEqual(model.focusAudioModeForCurrentSession(), .countdown)
    XCTAssertTrue(model.isFocusTickingForTesting)

    model.pause()
    XCTAssertFalse(model.shouldPlayFocusAudio())
    XCTAssertFalse(model.isFocusTickingForTesting)

    model.resume()
    XCTAssertTrue(model.shouldPlayFocusAudio())
    XCTAssertTrue(model.isFocusTickingForTesting)

    UserDefaults.standard.set(false, forKey: OnTimeSettingsKeys.focusAudioCountdown)
    let expectation = expectation(description: "countdown focus toggle")
    DispatchQueue.main.async {
      XCTAssertFalse(self.model.shouldPlayFocusAudio())
      XCTAssertFalse(self.model.isFocusTickingForTesting)
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 1.0)
  }

  func testStopwatchTickingRespectsSetting() {
    UserDefaults.standard.set(true, forKey: OnTimeSettingsKeys.focusAudioStopwatch)
    model.startStopwatch()
    XCTAssertEqual(model.focusAudioModeForCurrentSession(), .stopwatch)
    XCTAssertTrue(model.shouldPlayFocusAudio())
    XCTAssertTrue(model.isFocusTickingForTesting)

    model.pause()
    XCTAssertFalse(model.isFocusTickingForTesting)

    model.resume()
    XCTAssertTrue(model.isFocusTickingForTesting)

    UserDefaults.standard.set(false, forKey: OnTimeSettingsKeys.focusAudioStopwatch)
    let expectation = expectation(description: "stopwatch focus toggle")
    DispatchQueue.main.async {
      XCTAssertFalse(self.model.shouldPlayFocusAudio())
      XCTAssertFalse(self.model.isFocusTickingForTesting)
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 1.0)
  }

  func testPomodoroWorkTicksAndBreakDoesNot() {
    UserDefaults.standard.set(true, forKey: OnTimeSettingsKeys.focusAudioPomodoroWork)
    model.startPomodoro()
    XCTAssertEqual(model.focusAudioModeForCurrentSession(), .pomodoroWork)
    XCTAssertTrue(model.shouldPlayFocusAudio())
    XCTAssertTrue(model.isFocusTickingForTesting)

    XCTAssertTrue(model.skipPomodoroPhase())
    XCTAssertEqual(model.pomodoroSession?.currentPhase, .shortBreak)
    XCTAssertNil(model.focusAudioModeForCurrentSession())
    XCTAssertFalse(model.shouldPlayFocusAudio())
    XCTAssertFalse(model.isFocusTickingForTesting)
  }

  func testPomodoroWorkTickingCanBeDisabled() {
    UserDefaults.standard.set(false, forKey: OnTimeSettingsKeys.focusAudioPomodoroWork)
    model.startPomodoro()
    XCTAssertEqual(model.focusAudioModeForCurrentSession(), .pomodoroWork)
    XCTAssertFalse(model.shouldPlayFocusAudio())
    XCTAssertFalse(model.isFocusTickingForTesting)
  }

  func testFocusSoundVolumesApplyLiveFromUserDefaults() {
    let defaults = UserDefaults.standard
    let keys = [
      OnTimeSettingsKeys.windupVolume,
      OnTimeSettingsKeys.dingVolume,
      OnTimeSettingsKeys.tickingVolume,
    ]
    let previous = keys.map { ($0, defaults.object(forKey: $0)) }
    defer {
      for (key, value) in previous {
        if let value {
          defaults.set(value, forKey: key)
        } else {
          defaults.removeObject(forKey: key)
        }
      }
    }

    defaults.set(1.0, forKey: OnTimeSettingsKeys.windupVolume)
    defaults.set(1.0, forKey: OnTimeSettingsKeys.dingVolume)
    defaults.set(1.0, forKey: OnTimeSettingsKeys.tickingVolume)

    let player = OnTimeFocusPlayer()
    let expectation = expectation(description: "live volume apply")
    defaults.set(0.4, forKey: OnTimeSettingsKeys.windupVolume)
    defaults.set(1.6, forKey: OnTimeSettingsKeys.dingVolume)
    defaults.set(0.0, forKey: OnTimeSettingsKeys.tickingVolume)

    // UserDefaults.didChangeNotification is delivered on the observer's queue (.main).
    DispatchQueue.main.async {
      let volumes = player.playerVolumesForTesting
      XCTAssertEqual(volumes.windup, 0.4, accuracy: 0.001)
      XCTAssertEqual(volumes.ding, 1.6, accuracy: 0.001)
      XCTAssertEqual(volumes.ticking, 0.0, accuracy: 0.001)
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 1.0)
  }
}
