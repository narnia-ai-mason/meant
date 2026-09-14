import AppKit
import Carbon
import Foundation
import MeantCore

@MainActor
final class HotKeyMonitor {
  static let shared = HotKeyMonitor()

  var onFlip: (() -> Void)?

  private var flipRef: EventHotKeyRef?
  private var handlerInstalled = false

  func register(_ binding: HotkeyBinding = .default) {
    installHandlerIfNeeded()
    if let flipRef {
      UnregisterEventHotKey(flipRef)
      self.flipRef = nil
    }
    flipRef = registerKey(UInt32(binding.keyCode), binding.carbonModifiers, id: 1)
  }

  private func installHandlerIfNeeded() {
    guard !handlerInstalled else {
      return
    }
    handlerInstalled = true
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ in
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        guard status == noErr else {
          return noErr
        }
        DispatchQueue.main.async {
          HotKeyMonitor.shared.dispatch(hotKeyID)
        }
        return noErr
      },
      1,
      &eventType,
      nil,
      nil
    )
  }

  private func dispatch(_ hotKeyID: EventHotKeyID) {
    if hotKeyID.id == 1 {
      onFlip?()
    }
  }

  private func registerKey(_ key: UInt32, _ modifiers: UInt32, id: UInt32) -> EventHotKeyRef? {
    var ref: EventHotKeyRef?
    let identifier = EventHotKeyID(signature: 0x4D4E_5420, id: id)
    RegisterEventHotKey(key, modifiers, identifier, GetApplicationEventTarget(), 0, &ref)
    return ref
  }
}
