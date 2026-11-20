import Foundation

enum NotificationIdentifiers {
  static let timerFinishedCategory = "ontime.timerFinished"
  static let pomodoroAdvancingCategory = "ontime.pomodoroAdvancing"
  static let pomodoroCompleteCategory = "ontime.pomodoroComplete"
  static let overrunExpiredCategory = "ontime.overrunExpired"

  static let clearAction = "ontime.timerFinished.clear"
  static let repeatAction = "ontime.timerFinished.repeat"
  static let stopPomodoroAction = "ontime.pomodoro.stop"
  static let skipBreakAction = "ontime.pomodoro.skip"
  static let pauseAction = "ontime.timer.pause"
  static let addFiveMinutesAction = "ontime.timer.addFive"
}
