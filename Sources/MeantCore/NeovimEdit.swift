import Foundation

public enum NeovimMode {
  /// Insert and replace, where a suggestion replaces the word that was just typed.
  public static func isTyping(_ mode: String) -> Bool {
    guard let first = mode.first else { return false }
    return first == "i" || first == "R"
  }

  /// Normal, visual, select, and operator-pending. Those keystrokes are commands.
  /// Command-line mode is not included, so a search can stay in Korean.
  public static func guardsHangul(_ mode: String) -> Bool {
    guard let scalar = mode.unicodeScalars.first else { return false }
    if scalar.value == 19 || scalar.value == 22 { return true }
    switch Character(scalar) {
    case "n", "v", "V", "s", "S":
      return true
    default:
      return false
    }
  }
}

public struct NeovimEdit: Equatable, Sendable {
  /// Byte columns on the current line, end exclusive, matching `nvim_buf_set_text`.
  public var startByte: Int
  public var endByte: Int
  public var text: String

  public init(startByte: Int, endByte: Int, text: String) {
    self.startByte = startByte
    self.endByte = endByte
    self.text = text
  }
}

public enum NeovimVisibility {
  /// True only when this nvim's buffer is what the terminal is showing.
  /// Another program in the same app, such as Claude Code, does not match.
  public static func isOnScreen(lines: [String], filename: String, screen: String, title: String) -> Bool {
    let samples = lines
      .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)) }
      .filter { $0.count >= 6 }
    if !screen.isEmpty, samples.contains(where: { screen.contains($0) }) {
      return true
    }
    let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.count >= 4 && !title.isEmpty && title.localizedCaseInsensitiveContains(name)
  }
}

public enum NeovimEditPlan {
  /// The cursor is the byte column nvim reports. `typed` is the word meant recognized,
  /// without relying on the terminal's accessibility caret.
  public static func plan(
    line: String,
    cursorByte: Int,
    typed: String,
    replacement: String,
    trigger: String?
  ) -> NeovimEdit? {
    let tail = trigger ?? ""
    var word = typed
    if !tail.isEmpty, word.hasSuffix(tail) {
      word.removeLast(tail.count)
    }
    guard !word.isEmpty else { return nil }
    let bytes = Array(line.utf8)
    let cursor = min(max(cursorByte, 0), bytes.count)
    guard
      let head = String(bytes: bytes[..<cursor], encoding: .utf8),
      head.utf8.count == cursor
    else { return nil }
    let insert = replacement + tail
    if let matched = suffixByteCount(word: word, tail: tail, in: head) {
      return NeovimEdit(startByte: cursor - matched, endByte: cursor, text: insert)
    }
    if !tail.isEmpty, let matched = suffixByteCount(word: word, tail: "", in: head) {
      return NeovimEdit(startByte: cursor - matched, endByte: cursor, text: insert)
    }
    guard word.contains(where: { !$0.isASCII }) else { return nil }
    let stemBytes: Int
    let stem: String
    if !tail.isEmpty, let triggerBytes = matchedSuffixByteCount(tail, in: head) {
      stemBytes = cursor - triggerBytes
      guard let stemText = String(bytes: bytes[..<stemBytes], encoding: .utf8) else { return nil }
      stem = stemText
    } else {
      stemBytes = cursor
      stem = head
    }
    guard
      let partial = longestProperPrefix(of: word, suffixing: stem),
      let partialBytes = matchedSuffixByteCount(partial, in: stem),
      partialBytes > 0, partialBytes <= stemBytes
    else { return nil }
    return NeovimEdit(startByte: stemBytes - partialBytes, endByte: cursor, text: insert)
  }

  private static func suffixByteCount(word: String, tail: String, in text: String) -> Int? {
    let tails = tail.isEmpty ? [""] : forms(tail)
    for wordForm in forms(word) {
      for tailForm in tails {
        let candidate = wordForm + tailForm
        if text.hasSuffix(candidate) {
          return candidate.utf8.count
        }
      }
    }
    return nil
  }

  private static func matchedSuffixByteCount(_ suffix: String, in text: String) -> Int? {
    for form in forms(suffix) where text.hasSuffix(form) {
      return form.utf8.count
    }
    return nil
  }

  private static func longestProperPrefix(of word: String, suffixing stem: String) -> String? {
    let characters = Array(word)
    guard characters.count > 1 else { return nil }
    for length in stride(from: characters.count - 1, through: 1, by: -1) {
      let prefix = String(characters[..<length])
      if let form = forms(prefix).first(where: { stem.hasSuffix($0) }) {
        return form
      }
    }
    return nil
  }

  private static func forms(_ text: String) -> [String] {
    var seen = Set<String>()
    return [text, text.precomposedStringWithCanonicalMapping, text.decomposedStringWithCanonicalMapping]
      .filter { seen.insert($0).inserted }
  }
}
