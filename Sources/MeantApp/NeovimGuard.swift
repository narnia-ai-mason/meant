import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import MeantCore

/// While nvim is in a command mode, keep the Mac input source on English so a 두벌식
/// key does not insert Hangul or send the input method's backspaces into the buffer.
final class NeovimGuard: @unchecked Sendable {
  static let shared = NeovimGuard()

  private let lock = NSLock()
  private var cache = Cache()
  private var generation = 0
  private var inflight = false
  private var timer: Timer?

  func start() {
    let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
      self?.poll()
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  /// Rewrites a command key that the Korean input method already turned into Hangul.
  func adjust(_ event: CGEvent) {
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let control = flags.contains(.maskControl)
    let command = flags.contains(.maskCommand)
    let option = flags.contains(.maskAlternate)
    var shouldConfirm = false
    var guarding = false
    lock.lock()
    if isLeaveInsert(code, control: control, command: command), cache.typing {
      cache.typing = false
      cache.pendingNormal = true
      shouldConfirm = true
    }
    guarding = cache.guarding || cache.pendingNormal
    let insertEntry = isInsertEntry(code, shift: flags.contains(.maskShift) || flags.contains(.maskAlphaShift))
    lock.unlock()

    if shouldConfirm { confirm() }
    guard guarding, !control, !command, !option else { return }
    rewrite(event, code: code, flags: flags)
    if insertEntry {
      scheduleRestore()
    } else {
      InputSource.parkNonASCIIForCommands()
    }
  }

  private func poll() {
    let token = beginFetch(markInflight: true)
    guard token != nil else { return }
    guard
      let app = NSWorkspace.shared.frontmostApplication,
      TerminalApps.matches(app.bundleIdentifier)
    else {
      finish(token: token!, mode: nil)
      return
    }
    let pid = app.processIdentifier
    let bundlePath = app.bundleURL?.path
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let mode = Neovim.mode(appPID: pid, bundlePath: bundlePath)
      DispatchQueue.main.async {
        self?.finish(token: token!, mode: mode)
      }
    }
  }

  private func confirm() {
    guard let token = beginFetch(markInflight: false) else { return }
    guard
      let app = NSWorkspace.shared.frontmostApplication,
      TerminalApps.matches(app.bundleIdentifier)
    else {
      finish(token: token, mode: nil)
      return
    }
    let pid = app.processIdentifier
    let bundlePath = app.bundleURL?.path
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let mode = Neovim.mode(appPID: pid, bundlePath: bundlePath)
      DispatchQueue.main.async {
        self?.finish(token: token, mode: mode)
      }
    }
  }

  private func scheduleRestore() {
    guard InputSource.isParked else { return }
    guard
      let app = NSWorkspace.shared.frontmostApplication,
      TerminalApps.matches(app.bundleIdentifier)
    else { return }
    let pid = app.processIdentifier
    let bundlePath = app.bundleURL?.path
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let mode = Neovim.mode(appPID: pid, bundlePath: bundlePath)
      DispatchQueue.main.async {
        guard let mode, NeovimMode.isTyping(mode) else { return }
        self?.note(mode)
      }
    }
  }

  private func beginFetch(markInflight: Bool) -> Int? {
    lock.lock()
    defer { lock.unlock() }
    if markInflight {
      if inflight { return nil }
      inflight = true
    }
    generation += 1
    return generation
  }

  private func finish(token: Int, mode: String?) {
    lock.lock()
    inflight = false
    let current = token == generation
    lock.unlock()
    guard current else { return }
    note(mode)
  }

  private func note(_ mode: String?) {
    enum Action { case park, restore, none }
    var action = Action.none
    lock.lock()
    if let mode {
      if NeovimMode.isTyping(mode) {
        cache.typing = true
        cache.guarding = false
        cache.pendingNormal = false
        action = .restore
      } else if NeovimMode.guardsHangul(mode) {
        cache.typing = false
        cache.guarding = true
        cache.pendingNormal = false
        action = .park
      } else {
        cache.typing = false
        cache.guarding = false
        cache.pendingNormal = false
      }
    } else {
      cache = Cache()
      action = .restore
    }
    lock.unlock()
    switch action {
    case .park:
      InputSource.parkNonASCIIForCommands()
    case .restore:
      InputSource.restoreParkedInput()
    case .none:
      break
    }
  }

  private func rewrite(_ event: CGEvent, code: Int64, flags: CGEventFlags) {
    let unicode = unicodeString(from: event)
    guard unicode.contains(where: isHangul) else { return }
    let shift = flags.contains(.maskShift) || flags.contains(.maskAlphaShift)
    guard let ascii = ASCIIKey.character(keyCode: CGKeyCode(code), shift: shift), ascii != unicode else {
      return
    }
    var units = Array(ascii.utf16)
    units.withUnsafeMutableBufferPointer { buffer in
      guard let base = buffer.baseAddress else { return }
      event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
    }
  }

  private func isLeaveInsert(_ code: Int64, control: Bool, command: Bool) -> Bool {
    if command { return false }
    if code == Int64(kVK_Escape) { return true }
    return control && (code == Int64(kVK_ANSI_LeftBracket) || code == Int64(kVK_ANSI_C))
  }

  private func isInsertEntry(_ code: Int64, shift: Bool) -> Bool {
    switch Int(code) {
    case kVK_ANSI_I, kVK_ANSI_A, kVK_ANSI_O, kVK_ANSI_C, kVK_ANSI_S:
      return true
    case kVK_ANSI_R:
      return shift
    default:
      return false
    }
  }
}

private struct Cache {
  var typing = false
  var guarding = false
  var pendingNormal = false
}

private func isHangul(_ character: Character) -> Bool {
  character.unicodeScalars.contains { scalar in
    (0x1100...0x11FF).contains(scalar.value)
      || (0x3130...0x318F).contains(scalar.value)
      || (0xAC00...0xD7A3).contains(scalar.value)
  }
}

private func unicodeString(from event: CGEvent) -> String {
  var length = 0
  event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
  guard length > 0 else { return "" }
  var characters = [UniChar](repeating: 0, count: Int(length))
  characters.withUnsafeMutableBufferPointer { buffer in
    event.keyboardGetUnicodeString(
      maxStringLength: length,
      actualStringLength: &length,
      unicodeString: buffer.baseAddress
    )
  }
  return String(utf16CodeUnits: characters, count: Int(length))
}
