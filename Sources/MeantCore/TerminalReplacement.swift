import Foundation

public enum TerminalReplacement {
  public struct Plan: Equatable {
    /// One Backspace for the space or punctuation that opened the suggestion.
    public var deleteTrigger: Bool
    /// Ctrl+W, the "delete previous word" binding shared by shells and TUIs.
    public var killWord: Bool
    public var insert: String
  }

  /// The cursor is at the end of the word that was just typed. Character counts
  /// are not used: a terminal's idea of width and caret position is not stable,
  /// and Backspace at the start of a line can leave the first character behind.
  public static func keystrokes(replacement: String, trigger: String?) -> Plan {
    let tail = trigger ?? ""
    return Plan(
      deleteTrigger: !tail.isEmpty,
      killWord: true,
      insert: replacement + tail
    )
  }
}
