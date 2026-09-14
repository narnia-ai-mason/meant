enum Hangul {
  static func isLetter(_ character: Character) -> Bool {
    character.unicodeScalars.contains { isLetter($0.value) }
  }

  static func isSyllable(_ character: Character) -> Bool {
    character.unicodeScalars.contains { isSyllable($0.value) }
  }

  static func isJamo(_ character: Character) -> Bool {
    character.unicodeScalars.contains { isJamo($0.value) }
  }

  static func shape(of text: String) -> Shape {
    var shape = Shape()
    for character in text {
      if isSyllable(character) {
        shape.syllables += 1
      } else if isJamo(character) {
        shape.jamo += 1
      }
    }
    return shape
  }

  struct Shape: Equatable {
    var syllables = 0
    var jamo = 0

    var isComposedKorean: Bool {
      syllables >= 2 && jamo == 0
    }

    var hasJamo: Bool {
      jamo > 0
    }
  }

  private static func isLetter(_ value: UInt32) -> Bool {
    isSyllable(value) || isJamo(value)
  }

  private static func isSyllable(_ value: UInt32) -> Bool {
    (0xAC00...0xD7A3).contains(value)
  }

  private static func isJamo(_ value: UInt32) -> Bool {
    (0x1100...0x11FF).contains(value)
      || (0x3131...0x318E).contains(value)
      || (0xA960...0xA97F).contains(value)
      || (0xD7B0...0xD7FF).contains(value)
  }
}
