import Carbon.HIToolbox
import CoreGraphics
import Foundation
import MeantCore

final class SpaceMonitor: @unchecked Sendable {
  var onSpace: (@MainActor (_ typed: String) -> Void)?
  var onOtherKey: (@MainActor () -> Void)?
  var onHUDCommit: (@MainActor () -> Void)?
  var onHUDCancel: (@MainActor () -> Void)?
  var onHUDIgnore: (@MainActor () -> Void)?
  var isHUDVisible: @MainActor () -> Bool = { false }

  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var inspectWork: DispatchWorkItem?
  private var hudVisible = false
  private var typed = ""
  private var lastWord = ""
  private var typedOnASCIILayout = true

  var currentWord: String {
    lastWord.isEmpty ? typed : lastWord
  }

  func setHUDVisible(_ visible: Bool) {
    hudVisible = visible
  }

  func start() {
    stop()
    let mask =
      CGEventMask(1 << CGEventType.keyDown.rawValue)
      | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
      | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
      | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
    let context = Unmanaged.passUnretained(self).toOpaque()
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { _, type, event, refcon in
          guard let refcon else {
            return Unmanaged.passUnretained(event)
          }
          let monitor = Unmanaged<SpaceMonitor>.fromOpaque(refcon).takeUnretainedValue()
          if monitor.handle(type: type, event: event) {
            return nil
          }
          return Unmanaged.passUnretained(event)
        },
        userInfo: context
      )
    else {
      return
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    self.tap = tap
    self.source = source
  }

  func stop() {
    inspectWork?.cancel()
    inspectWork = nil
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
      self.tap = nil
    }
    if let source {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      CFRunLoopSourceInvalidate(source)
      self.source = source
    }
  }

  private func handle(type: CGEventType, event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return false
    }
    if event.getIntegerValueField(.eventSourceUserData) == MeantEvent.signature {
      return false
    }
    if isMouseDown(type) {
      DispatchQueue.main.async { [weak self] in
        self?.resetTyped()
      }
      return false
    }
    guard type == .keyDown else {
      return false
    }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let hasCommandish =
      flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
    let hasShift = flags.contains(.maskShift)
    let isShortcut = flags.contains(.maskCommand) || flags.contains(.maskControl)
    let isPlainSpace = code == Int64(kVK_Space) && !hasCommandish && !hasShift
    let unicode = unicodeString(from: event)
    let isDelimiter = !isShortcut && WordEnd.isDelimiter(unicode)
    let asciiLayout = InputSource.isASCIILayout

    if hudVisible, isHUDKey(code) {
      if hasCommandish || hasShift {
        DispatchQueue.main.async { [onHUDCancel] in
          onHUDCancel?()
        }
        return false
      }
      DispatchQueue.main.async { [onHUDCommit, onHUDCancel, onHUDIgnore] in
        if code == Int64(kVK_Escape) {
          onHUDCancel?()
        } else if code == Int64(kVK_Tab) {
          onHUDIgnore?()
        } else {
          onHUDCommit?()
        }
      }
      return true
    }

    DispatchQueue.main.async { [weak self] in
      self?.dispatchOnMain(
        code: code,
        isPlainSpace: isPlainSpace,
        isDelimiter: isDelimiter,
        resetsWord: hasCommandish || isWordReset(code),
        isDelete: code == Int64(kVK_Delete),
        unicode: unicode,
        asciiLayout: asciiLayout
      )
    }
    return false
  }

  @MainActor
  private func dispatchOnMain(
    code: Int64,
    isPlainSpace: Bool,
    isDelimiter: Bool,
    resetsWord: Bool,
    isDelete: Bool,
    unicode: String,
    asciiLayout: Bool
  ) {
    if isPlainSpace {
      lastWord = typed
      typed = ""
      if isHUDVisible() {
        onOtherKey?()
        return
      }
      scheduleInspect()
      return
    }
    if isDelimiter {
      let hadWord = !typed.isEmpty
      if hadWord {
        lastWord = typed
        typed = ""
      }
      if isHUDVisible() {
        if hadWord {
          onOtherKey?()
        }
        return
      }
      if hadWord {
        scheduleInspect()
      }
      return
    }
    if isHUDVisible(), !isHUDKey(code) {
      onOtherKey?()
    }
    if resetsWord {
      resetTyped()
      return
    }
    if isDelete {
      if !typed.isEmpty {
        typed.removeLast()
      }
      lastWord = ""
      return
    }
    appendTyped(unicode, asciiLayout: asciiLayout)
  }

  @MainActor
  private func scheduleInspect() {
    inspectWork?.cancel()
    let word = lastWord
    let work = DispatchWorkItem { [onSpace] in
      Task { @MainActor in
        onSpace?(word)
      }
    }
    inspectWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
  }

  @MainActor
  private func appendTyped(_ unicode: String, asciiLayout: Bool) {
    guard !unicode.isEmpty, !unicode.contains(where: \.isNewline) else {
      return
    }
    if unicode.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
      return
    }
    if typed.isEmpty {
      typedOnASCIILayout = asciiLayout
    }
    typed.append(unicode)
    lastWord = ""
  }

  @MainActor
  private func resetTyped() {
    typed = ""
    lastWord = ""
    typedOnASCIILayout = true
  }

  private func isHUDKey(_ code: Int64) -> Bool {
    code == Int64(kVK_Return)
      || code == Int64(kVK_ANSI_KeypadEnter)
      || code == Int64(kVK_Tab)
      || code == Int64(kVK_Escape)
  }
}

extension SpaceMonitor {
  var typedFromASCIILayout: Bool {
    typedOnASCIILayout
  }
}

private func isMouseDown(_ type: CGEventType) -> Bool {
  type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
}

private func isWordReset(_ code: Int64) -> Bool {
  switch Int(code) {
  case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape,
    kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
    kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete:
    return true
  default:
    return false
  }
}

private func unicodeString(from event: CGEvent) -> String {
  var length = 0
  event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
  guard length > 0 else {
    return ""
  }
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
