public enum Flip {
  public static func force(_ token: String) -> Suggestion? {
    let parts = TokenAffix.split(token)
    let core = parts.core
    guard !core.isEmpty else {
      return nil
    }

    if core.allSatisfy(\.isASCII), core.allSatisfy(\.isLetter) {
      let hangul = Converter.enToKo(core)
      guard hangul != core else {
        return nil
      }
      return Suggestion(
        original: parts.joined,
        replacement: parts.wrapped(hangul),
        direction: .englishToKorean
      )
    }

    if core.contains(where: Hangul.isLetter),
      !core.contains(where: { $0.isASCII && $0.isLetter })
    {
      let latin = Converter.koToEn(core)
      guard latin != core else {
        return nil
      }
      return Suggestion(
        original: parts.joined,
        replacement: parts.wrapped(latin),
        direction: .koreanToEnglish
      )
    }

    return nil
  }
}
