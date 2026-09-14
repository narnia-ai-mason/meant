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
    while start > 0 {
      let unit = ns.substring(with: NSRange(location: start - 1, length: 1))
      if isWhitespace(unit) {
        break
      }
      start -= 1
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

  private static func isWhitespace(_ unit: String) -> Bool {
    unit.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
  }
}
