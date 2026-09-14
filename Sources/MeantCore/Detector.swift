public struct Suggestion: Equatable, Sendable {
  public var original: String
  public var replacement: String
  public var direction: Direction

  public enum Direction: Equatable, Sendable {
    case englishToKorean
    case koreanToEnglish
  }
}

public struct Detector: Sendable {
  public var english: WordList
  public var ignored: Set<String>

  public init(english: WordList = .commonEnglish, ignored: some Sequence<String> = []) {
    self.english = english
    self.ignored = Set(ignored.map { $0.lowercased() })
  }

  public static let standard = Detector()

  public func ignoring(_ words: some Sequence<String>) -> Detector {
    Detector(english: english, ignored: ignored.union(words.map { $0.lowercased() }))
  }

  public func inspect(_ token: String) -> Suggestion? {
    let parts = TokenAffix.split(token)
    let core = parts.core
    guard !core.isEmpty else { return nil }
    guard !isIgnored(core) else { return nil }

    if core.allSatisfy(\.isASCII), core.allSatisfy(\.isLetter) {
      return englishToKorean(parts)
    }
    if core.contains(where: Hangul.isLetter) {
      guard !core.contains(where: { $0.isASCII && $0.isLetter }) else { return nil }
      return koreanToEnglish(parts)
    }
    return nil
  }

  private func englishToKorean(_ parts: TokenAffix) -> Suggestion? {
    let core = parts.core
    guard core.count >= 4 else { return nil }
    let hangul = Converter.enToKo(core)
    guard hangul != core, hangul.contains(where: Hangul.isLetter) else { return nil }
    guard !isIgnored(hangul) else { return nil }
    let sourceLooksWrong = !english.contains(core)
    let destinationLooksRight = Hangul.shape(of: hangul).isComposedKorean
    guard sourceLooksWrong || destinationLooksRight else { return nil }
    if isCodeLike(core), !destinationLooksRight {
      return nil
    }
    return Suggestion(
      original: parts.joined,
      replacement: parts.wrapped(hangul),
      direction: .englishToKorean
    )
  }

  private func koreanToEnglish(_ parts: TokenAffix) -> Suggestion? {
    let core = parts.core
    let latin = Converter.koToEn(core)
    guard latin.count >= 2, latin.allSatisfy(\.isLetter), latin != core else { return nil }
    guard !isIgnored(latin) else { return nil }
    let sourceLooksWrong = Hangul.shape(of: core).hasJamo
    let destinationLooksRight = latin.count >= 4 && english.contains(latin)
    guard sourceLooksWrong || destinationLooksRight else { return nil }
    return Suggestion(
      original: parts.joined,
      replacement: parts.wrapped(latin),
      direction: .koreanToEnglish
    )
  }

  private func isIgnored(_ word: String) -> Bool {
    ignored.contains(word.lowercased())
  }
}

extension Suggestion {
  public var ignoreKeys: [String] {
    let parts = TokenAffix.split(original)
    return [original, replacement, parts.core]
  }
}

struct TokenAffix {
  var leading: String
  var core: String
  var trailing: String

  var joined: String { leading + core + trailing }

  func wrapped(_ replacement: String) -> String {
    leading + replacement + trailing
  }

  static func split(_ token: String) -> TokenAffix {
    let characters = Array(token)
    var start = 0
    var end = characters.count
    while start < end && !isCore(characters[start]) {
      start += 1
    }
    while end > start && !isCore(characters[end - 1]) {
      end -= 1
    }
    return TokenAffix(
      leading: String(characters[..<start]),
      core: String(characters[start..<end]),
      trailing: String(characters[end...])
    )
  }

  private static func isCore(_ character: Character) -> Bool {
    character.isLetter || Hangul.isLetter(character)
  }
}

private func isCodeLike(_ token: String) -> Bool {
  if token.contains("_") || token.contains("@") || token.contains("/") {
    return true
  }
  if token.contains(where: \.isNumber) {
    return true
  }
  let letters = token.filter(\.isLetter)
  if letters.count >= 2 && letters.allSatisfy(\.isUppercase) {
    return true
  }
  var seenLower = false
  for character in letters {
    if character.isLowercase {
      seenLower = true
    } else if character.isUppercase, seenLower {
      return true
    }
  }
  return false
}
