import Carbon
import CoreGraphics
import Foundation

/// The character a physical key produces on the ABC layout. Used when nvim is in a
/// command mode and the Korean input method has already turned that key into Hangul.
enum ASCIIKey {
  static func character(keyCode: CGKeyCode, shift: Bool) -> String? {
    guard let source = latinSource(),
      let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    var deadKeyState: UInt32 = 0
    var characters = [UniChar](repeating: 0, count: 4)
    var length = 0
    let modifiers: UInt32 = shift ? UInt32(shiftKey >> 8) : 0
    let status = data.withUnsafeBytes { buffer -> OSStatus in
      guard let base = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
        return -1
      }
      return UCKeyTranslate(
        base,
        keyCode,
        UInt16(kUCKeyActionDisplay),
        modifiers,
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        characters.count,
        &length,
        &characters
      )
    }
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: characters, count: Int(length))
  }

  private static func latinSource() -> TISInputSource? {
    guard
      let raw = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]
    else { return nil }
    let identifiers = raw.compactMap { source -> (String, TISInputSource)? in
      guard
        let category = string(source, kTISPropertyInputSourceCategory),
        category == String(kTISCategoryKeyboardInputSource),
        let id = string(source, kTISPropertyInputSourceID)
      else { return nil }
      return (id, source)
    }
    return identifiers.first { $0.0 == "com.apple.keylayout.ABC" }?.1
      ?? identifiers.first { $0.0 == "com.apple.keylayout.US" }?.1
  }

  private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
  }
}
