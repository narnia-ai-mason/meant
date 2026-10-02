public enum WordEnd: Sendable {
  public static func isDelimiter(_ text: String) -> Bool {
    text.count == 1 && text.unicodeScalars.allSatisfy { delimiters.contains($0) }
  }

  private static let delimiters: Set<Unicode.Scalar> = [
    ".", ",", "?", "!", ":", ";", "…", "~",
    "(", ")", "[", "]", "{", "}",
    "\"", "'",
    "\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}",
    "「", "」", "『", "』",
    "。", "，", "？", "！", "：", "；",
    "（", "）", "［", "］", "｛", "｝",
    "〜", "～",
  ]
}
