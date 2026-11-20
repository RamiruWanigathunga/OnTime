import AppKit
import AVFoundation
import Foundation

/// Plays buddhabeats timer samples (windup / ding / ticking) from the asset catalog.
/// No programmatic PCM synthesis — exact WAV data via `NSDataAsset`.
///
/// Samples load lazily on first use so idle menu-bar runtime doesn’t keep three
/// decoded WAVs resident. Volume keys are read from `UserDefaults` (Settings
/// `@AppStorage` sliders) and apply live to any currently playing samples.
final class OnTimeFocusPlayer {
  private var windupSound: AVAudioPlayer?
  private var dingSound: AVAudioPlayer?
  private var tickingSound: AVAudioPlayer?
  private var isTicking = false
  private var defaultsObserver: NSObjectProtocol?
  private var appliedVolumes: (windup: Double, ding: Double, ticking: Double)?

  init() {
    applyVolumesFromDefaults()
    defaultsObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: UserDefaults.standard,
      queue: .main
    ) { [weak self] _ in
      self?.applyVolumesFromDefaults()
    }
  }

  deinit {
    if let defaultsObserver {
      NotificationCenter.default.removeObserver(defaultsObserver)
    }
  }

  func applyVolumesFromDefaults() {
    let windup = Self.volume(forKey: OnTimeSettingsKeys.windupVolume)
    let ding = Self.volume(forKey: OnTimeSettingsKeys.dingVolume)
    let ticking = Self.volume(forKey: OnTimeSettingsKeys.tickingVolume)
    if let appliedVolumes,
      appliedVolumes.windup == windup,
      appliedVolumes.ding == ding,
      appliedVolumes.ticking == ticking
    {
      return
    }
    appliedVolumes = (windup, ding, ticking)
    setVolume(windupSound, windup)
    setVolume(dingSound, ding)
    setVolume(tickingSound, ticking)
  }

  func playWindup() {
    applyVolumesFromDefaults()
    let sound = ensureWindup()
    sound?.currentTime = 0
    sound?.play()
  }

  func playDing() {
    applyVolumesFromDefaults()
    let sound = ensureDing()
    sound?.currentTime = 0
    sound?.play()
  }

  func startTicking() {
    applyVolumesFromDefaults()
    guard let tickingSound = ensureTicking() else { return }
    if !isTicking {
      tickingSound.currentTime = 0
      tickingSound.play()
      isTicking = true
    }
  }

  func stopTicking() {
    guard isTicking else { return }
    tickingSound?.stop()
    tickingSound?.currentTime = 0
    isTicking = false
  }

  private func ensureWindup() -> AVAudioPlayer? {
    if let windupSound { return windupSound }
    windupSound = loadPlayer(named: "windup", loops: 0)
    setVolume(windupSound, Self.volume(forKey: OnTimeSettingsKeys.windupVolume))
    return windupSound
  }

  private func ensureDing() -> AVAudioPlayer? {
    if let dingSound { return dingSound }
    dingSound = loadPlayer(named: "ding", loops: 0)
    setVolume(dingSound, Self.volume(forKey: OnTimeSettingsKeys.dingVolume))
    return dingSound
  }

  private func ensureTicking() -> AVAudioPlayer? {
    if let tickingSound { return tickingSound }
    tickingSound = loadPlayer(named: "ticking", loops: -1)
    setVolume(tickingSound, Self.volume(forKey: OnTimeSettingsKeys.tickingVolume))
    return tickingSound
  }

  private func loadPlayer(named name: String, loops: Int) -> AVAudioPlayer? {
    guard let asset = NSDataAsset(name: name) else { return nil }
    let player = try? AVAudioPlayer(data: asset.data, fileTypeHint: AVFileType.wav.rawValue)
    player?.numberOfLoops = loops
    player?.prepareToPlay()
    return player
  }

  private func setVolume(_ sound: AVAudioPlayer?, _ volume: Double) {
    sound?.setVolume(Float(volume), fadeDuration: 0)
  }

  static func volume(forKey key: String) -> Double {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: key) == nil {
      return AudioDefaults.focusSoundVolume
    }
    return min(max(defaults.double(forKey: key), 0), AudioDefaults.focusSoundVolumeMax)
  }

  /// Test hook: volumes currently applied (player volume if loaded, else stored target).
  var playerVolumesForTesting: (windup: Float, ding: Float, ticking: Float) {
    (
      windupSound?.volume ?? Float(appliedVolumes?.windup ?? -1),
      dingSound?.volume ?? Float(appliedVolumes?.ding ?? -1),
      tickingSound?.volume ?? Float(appliedVolumes?.ticking ?? -1)
    )
  }

  /// Test hook: whether the looping tick sample is currently active.
  var isTickingForTesting: Bool { isTicking }
}
