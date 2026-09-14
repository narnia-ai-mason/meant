import Carbon.HIToolbox
import CoreGraphics
import Foundation

final class SpaceMonitor: @unchecked Sendable {
  var onSpace: (@MainActor () -> Void)?
  var onOtherKey: (@MainActor () -> Void)?
  var onHUDCommit: (@MainActor () -> Void)?
  var onHUDCancel: (@MainActor () -> Void)?
  var onHUDIgnore: (@MainActor () -> Void)?
  var isHUDVisible: @MainActor () -> Bool = { false }

  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var inspectWork: DispatchWorkItem?
  private var hudVisible = false

  func setHUDVisible(_ visible: Bool) {
    hudVisible = visible
  }

  func start() {
    stop()
    let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
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
    guard type == .keyDown else {
      return false
    }
    if event.getIntegerValueField(.eventSourceUserData) == MeantEvent.signature {
      return false
    }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let hasCommandish =
      flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
    let hasShift = flags.contains(.maskShift)
    let isPlainSpace = code == Int64(kVK_Space) && !hasCommandish && !hasShift

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
      self?.dispatchOnMain(code: code, isPlainSpace: isPlainSpace)
    }
    return false
  }

  @MainActor
  private func dispatchOnMain(code: Int64, isPlainSpace: Bool) {
    if isPlainSpace {
      if isHUDVisible() {
        onOtherKey?()
        return
      }
      scheduleInspect()
      return
    }
    if isHUDVisible(), !isHUDKey(code) {
      onOtherKey?()
    }
  }

  @MainActor
  private func scheduleInspect() {
    inspectWork?.cancel()
    let work = DispatchWorkItem { [onSpace] in
      Task { @MainActor in
        onSpace?()
      }
    }
    inspectWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
  }

  private func isHUDKey(_ code: Int64) -> Bool {
    code == Int64(kVK_Return)
      || code == Int64(kVK_ANSI_KeypadEnter)
      || code == Int64(kVK_Tab)
      || code == Int64(kVK_Escape)
  }
}
