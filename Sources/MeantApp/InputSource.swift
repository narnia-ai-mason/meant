import Carbon
import CoreGraphics
import Foundation
import MeantCore

enum InputSource {
  static var isASCIILayout: Bool {
    !isInputMethod(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
  }

  static func select(_ direction: Suggestion.Direction) {
    let sources = keyboardSources()
    let chosen: TISInputSource?
    switch direction {
    case .englishToKorean:
      chosen =
        sources.first { $0.id.contains("2SetKorean") }?.source
        ?? sources.first { $0.id.contains("Korean") }?.source
    case .koreanToEnglish:
      chosen =
        sources.first { $0.id == "com.apple.keylayout.ABC" }?.source
        ?? sources.first { $0.id == "com.apple.keylayout.ABC-Extended" }?.source
        ?? sources.first { $0.id == "com.apple.keylayout.US" }?.source
        ?? sources.first { $0.id.contains("keylayout") && !$0.id.contains("Korean") }?.source
    }
    guard let chosen else {
      return
    }
    activate(chosen)
  }

  private static func activate(_ source: TISInputSource) {
    TISSelectInputSource(source)
    guard isInputMethod(source) else {
      return
    }
    guard let latin = latinSource(), !same(latin, source) else {
      return
    }
    TISSelectInputSource(latin)
    if let shortcut = previousInputSourceShortcut() {
      postShortcut(shortcut)
    } else {
      TISSelectInputSource(source)
    }
  }

  private static func latinSource() -> TISInputSource? {
    let sources = keyboardSources()
    return
      sources.first { $0.id == "com.apple.keylayout.ABC" }?.source
      ?? sources.first { $0.id == "com.apple.keylayout.ABC-Extended" }?.source
      ?? sources.first { $0.id == "com.apple.keylayout.US" }?.source
      ?? sources.first { !isInputMethod($0.source) }?.source
  }

  private static func isInputMethod(_ source: TISInputSource) -> Bool {
    if let type = string(source, kTISPropertyInputSourceType),
      type.contains("InputMethod") || type.contains("InputMode")
    {
      return true
    }
    guard let id = string(source, kTISPropertyInputSourceID) else {
      return false
    }
    return id.contains("inputmethod") || id.contains("Korean") || id.contains("Japanese")
      || id.contains("Kotoeri") || id.contains("Pinyin") || id.contains("Zhuyin")
      || id.contains("Cangjie") || id.contains("Vietnamese") || id.contains("TCIM")
      || id.contains("SCIM")
  }

  private static func same(_ left: TISInputSource, _ right: TISInputSource) -> Bool {
    string(left, kTISPropertyInputSourceID) == string(right, kTISPropertyInputSourceID)
  }

  private struct Source {
    var id: String
    var source: TISInputSource
  }

  private static func keyboardSources() -> [Source] {
    guard
      let raw = TISCreateInputSourceList(nil, false)?.takeRetainedValue()
        as? [TISInputSource]
    else {
      return []
    }
    return raw.compactMap { source in
      guard
        let category = string(source, kTISPropertyInputSourceCategory),
        category == String(kTISCategoryKeyboardInputSource),
        let id = string(source, kTISPropertyInputSourceID)
      else {
        return nil
      }
      return Source(id: id, source: source)
    }
  }

  private static func previousInputSourceShortcut() -> (CGKeyCode, CGEventFlags)? {
    guard
      let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
      let keys = domain["AppleSymbolicHotKeys"] as? [String: Any],
      let entry = keys["60"] as? [String: Any],
      (entry["enabled"] as? NSNumber)?.boolValue == true,
      let value = entry["value"] as? [String: Any],
      let parameters = value["parameters"] as? [Any],
      parameters.count >= 3,
      let keyCode = (parameters[1] as? NSNumber)?.intValue,
      let modifiers = (parameters[2] as? NSNumber)?.uint64Value
    else {
      return nil
    }
    return (CGKeyCode(keyCode), CGEventFlags(rawValue: modifiers))
  }

  private static func postShortcut(_ shortcut: (CGKeyCode, CGEventFlags)) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
      guard
        let event = CGEvent(
          keyboardEventSource: source,
          virtualKey: shortcut.0,
          keyDown: down
        )
      else {
        continue
      }
      event.flags = shortcut.1
      event.setIntegerValueField(.eventSourceUserData, value: MeantEvent.signature)
      event.post(tap: .cghidEventTap)
    }
  }

  private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let raw = TISGetInputSourceProperty(source, key) else {
      return nil
    }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
  }
}
