import Foundation

public enum Converter {
  public static func enToKo(_ text: String) -> String {
    var composer = Composer()
    var output = String()
    output.reserveCapacity(text.count)
    for character in text {
      if let stroke = Dubeolsik.stroke(for: character) {
        output.append(contentsOf: composer.feed(stroke))
      } else {
        output.append(contentsOf: composer.flush())
        output.append(character)
      }
    }
    output.append(contentsOf: composer.flush())
    return output
  }

  public static func koToEn(_ text: String) -> String {
    let normalized = text.precomposedStringWithCanonicalMapping
    var output = String()
    output.reserveCapacity(normalized.count * 2)
    for character in normalized {
      if let keys = keys(forHangul: character) {
        output.append(contentsOf: keys)
      } else {
        output.append(character)
      }
    }
    return output
  }
}

private struct Composer {
  private var choseong: Int?
  private var jungseong: Int?
  private var jongseong: Int?

  mutating func feed(_ stroke: Stroke) -> String {
    switch stroke {
    case .consonant(let index):
      return feedConsonant(index)
    case .vowel(let index):
      return feedVowel(index)
    }
  }

  mutating func flush() -> String {
    defer {
      choseong = nil
      jungseong = nil
      jongseong = nil
    }
    return emit()
  }

  private mutating func feedConsonant(_ index: Int) -> String {
    guard choseong != nil else {
      let committed = emit()
      choseong = index
      jungseong = nil
      jongseong = nil
      return committed
    }
    guard jungseong != nil else {
      let committed = emit()
      choseong = index
      return committed
    }
    guard let jong = jongseong else {
      if let jong = Dubeolsik.jongseong(fromChoseong: index) {
        jongseong = jong
        return ""
      }
      let committed = emit()
      choseong = index
      jungseong = nil
      return committed
    }
    if let combined = Dubeolsik.compoundJongseong(jong, incomingChoseong: index) {
      jongseong = combined
      return ""
    }
    let committed = emit()
    choseong = index
    jungseong = nil
    jongseong = nil
    return committed
  }

  private mutating func feedVowel(_ index: Int) -> String {
    switch (choseong, jungseong, jongseong) {
    case (_, nil, nil):
      jungseong = index
      return ""
    case (nil, let jung?, nil):
      if let combined = Dubeolsik.compoundJungseong(jung, index) {
        jungseong = combined
        return ""
      }
      let committed = emit()
      choseong = nil
      jungseong = index
      jongseong = nil
      return committed
    case (_, let jung?, nil):
      if let combined = Dubeolsik.compoundJungseong(jung, index) {
        jungseong = combined
        return ""
      }
      let committed = emit()
      choseong = nil
      jungseong = index
      jongseong = nil
      return committed
    case (_, _, let jong?):
      if let split = Dubeolsik.splitJongseong(jong) {
        jongseong = split.rest
        let committed = emit()
        choseong = split.trailingChoseong
        jungseong = index
        jongseong = nil
        return committed
      }
      let nextChoseong = Dubeolsik.choseong(fromJongseong: jong)
      jongseong = nil
      let committed = emit()
      choseong = nextChoseong
      jungseong = index
      jongseong = nil
      return committed
    }
  }

  private func emit() -> String {
    switch (choseong, jungseong, jongseong) {
    case (let cho?, let jung?, let jong):
      return String(syllable(choseong: cho, jungseong: jung, jongseong: jong ?? 0))
    case (let cho?, nil, nil):
      return String(Dubeolsik.compatibilityChoseong(cho))
    case (nil, let jung?, nil):
      return String(Dubeolsik.compatibilityJungseong(jung))
    default:
      return ""
    }
  }
}

private func keys(forHangul character: Character) -> String? {
  guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
    return Dubeolsik.compatibilityJamoKeys(character)
  }
  let value = scalar.value
  if (0xAC00...0xD7A3).contains(value) {
    let offset = Int(value - 0xAC00)
    let choseong = offset / 588
    let jungseong = (offset % 588) / 28
    let jongseong = offset % 28
    return Dubeolsik.keys(choseong: choseong)
      + Dubeolsik.keys(jungseong: jungseong)
      + Dubeolsik.keys(jongseong: jongseong)
  }
  return Dubeolsik.compatibilityJamoKeys(character)
}

private func syllable(choseong: Int, jungseong: Int, jongseong: Int) -> Character {
  Character(UnicodeScalar(0xAC00 + (choseong * 21 + jungseong) * 28 + jongseong)!)
}
