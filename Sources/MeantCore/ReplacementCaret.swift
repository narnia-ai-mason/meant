import Foundation

public enum ReplacementCaret {
  public static func endUTF16(
    before: String,
    replaced: Range<Int>,
    replacement: String,
    after: String
  ) -> Int? {
    let beforeNS = before as NSString
    guard replaced.lowerBound >= 0, replaced.upperBound <= beforeNS.length else {
      return nil
    }
    let prefix = beforeNS.substring(to: replaced.lowerBound)
    let suffix = beforeNS.substring(from: replaced.upperBound)
    let prefixLen = (prefix as NSString).length
    let afterNS = after as NSString

    for variant in forms(replacement) {
      if literal(prefix + variant + suffix, after) {
        return prefixLen + (variant as NSString).length
      }
    }

    guard afterNS.length >= prefixLen, literal(afterNS.substring(to: prefixLen), prefix) else {
      return locate(replacement, in: after, preferring: prefixLen)
    }

    let rest = afterNS.substring(from: prefixLen) as NSString
    for variant in forms(replacement) {
      let length = (variant as NSString).length
      if rest.length >= length, literal(rest.substring(to: length), variant) {
        return prefixLen + length
      }
    }
    return locate(replacement, in: after, preferring: prefixLen)
  }

  private static func locate(_ replacement: String, in after: String, preferring location: Int) -> Int? {
    let afterNS = after as NSString
    let haystack = NSRange(location: 0, length: afterNS.length)
    var best: NSRange?
    for variant in forms(replacement) {
      var search = haystack
      while true {
        let found = afterNS.range(of: variant, options: [], range: search)
        guard found.location != NSNotFound else {
          break
        }
        if found.location == location {
          return found.location + found.length
        }
        if best == nil || abs(found.location - location) < abs(best!.location - location) {
          best = found
        }
        let next = found.location + max(found.length, 1)
        guard next < afterNS.length else {
          break
        }
        search = NSRange(location: next, length: afterNS.length - next)
      }
    }
    guard let best else {
      return nil
    }
    return best.location + best.length
  }

  private static func literal(_ left: String, _ right: String) -> Bool {
    (left as NSString).isEqual(to: right)
  }

  private static func forms(_ text: String) -> [String] {
    var seen = Set<String>()
    return [text, text.precomposedStringWithCanonicalMapping, text.decomposedStringWithCanonicalMapping]
      .filter { seen.insert($0).inserted }
  }
}
