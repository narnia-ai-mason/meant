import Foundation

public enum CaretToken {
  public static func resolve(
    text: String,
    caretUTF16: Int,
    skipTrailingWhitespace: Bool
  ) -> (token: String, utf16: Range<Int>)? {
    let ns = text as NSString
    var end = min(max(caretUTF16, 0), ns.length)
    if skipTrailingWhitespace {
      while end > 0 {
        let unit = ns.substring(with: NSRange(location: end - 1, length: 1))
        if isWhitespace(unit) {
          end -= 1
        } else {
          break
        }
      }
    }
    var start = end
    var kind: LetterKind?
    while start > 0 {
      let unit = ns.substring(with: NSRange(location: start - 1, length: 1))
      if isBoundary(unit) {
        break
      }
      if let unitKind = letterKind(unit) {
        if let kind, unitKind != kind {
          break
        }
        kind = unitKind
        start -= 1
        continue
      }
      if kind == nil {
        start -= 1
        continue
      }
      break
    }
    guard start < end else {
      return nil
    }
    let token = ns.substring(with: NSRange(location: start, length: end - start))
    return (token, start..<end)
  }

  public static func extendingThroughTrailingSpaces(
    token: Range<Int>,
    caretUTF16: Int,
    text: String
  ) -> Range<Int> {
    let ns = text as NSString
    var end = token.upperBound
    let limit = min(max(caretUTF16, token.upperBound), ns.length)
    while end < limit {
      let unit = ns.substring(with: NSRange(location: end, length: 1))
      if unit == " " || unit == "\t" {
        end += 1
      } else {
        break
      }
    }
    return token.lowerBound..<end
  }

  public static func locate(
    _ original: String,
    preferring location: Int,
    in text: String
  ) -> Range<Int>? {
    let ns = text as NSString
    let needle = original as NSString
    guard needle.length > 0, ns.length >= needle.length else {
      return nil
    }
    var search = NSRange(location: 0, length: ns.length)
    var best: NSRange?
    while true {
      let found = ns.range(of: original, options: [], range: search)
      guard found.location != NSNotFound else {
        break
      }
      if found.location == location {
        return found.location..<(found.location + found.length)
      }
      if best == nil || abs(found.location - location) < abs(best!.location - location) {
        best = found
      }
      let next = found.location + max(found.length, 1)
      guard next < ns.length else {
        break
      }
      search = NSRange(location: next, length: ns.length - next)
    }
    guard let best else {
      return nil
    }
    return best.location..<(best.location + best.length)
  }

  private enum LetterKind {
    case latin
    case hangul
  }

  private static func letterKind(_ unit: String) -> LetterKind? {
    guard let character = unit.first else {
      return nil
    }
    if Hangul.isLetter(character) {
      return .hangul
    }
    if character.isASCII, character.isLetter {
      return .latin
    }
    return nil
  }

  private static func isBoundary(_ unit: String) -> Bool {
    if isWhitespace(unit) {
      return true
    }
    return unit == "\u{FFFC}"
  }

  private static func isWhitespace(_ unit: String) -> Bool {
    unit.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
  }
}
