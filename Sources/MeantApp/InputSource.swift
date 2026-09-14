import Carbon
import Foundation
import MeantCore

enum InputSource {
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
    if let chosen {
      TISSelectInputSource(chosen)
    }
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

  private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let raw = TISGetInputSourceProperty(source, key) else {
      return nil
    }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
  }
}
