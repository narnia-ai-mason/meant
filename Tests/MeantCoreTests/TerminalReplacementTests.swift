import MeantCore
import XCTest

final class TerminalReplacementTests: XCTestCase {
  func testSpaceTriggerIsDeletedWithTheWordAndTypedAgain() {
    let plan = TerminalReplacement.keystrokes(replacement: "안녕", trigger: " ")
    XCTAssertTrue(plan.deleteTrigger)
    XCTAssertTrue(plan.killWord)
    XCTAssertEqual(plan.insert, "안녕 ")
  }

  func testHangulUsesTheSameWordKill() {
    let plan = TerminalReplacement.keystrokes(replacement: "clear", trigger: " ")
    XCTAssertTrue(plan.deleteTrigger)
    XCTAssertTrue(plan.killWord)
    XCTAssertEqual(plan.insert, "clear ")
  }

  func testHotkeyKillsTheWordWithoutInventingASpace() {
    let plan = TerminalReplacement.keystrokes(replacement: "안녕", trigger: nil)
    XCTAssertFalse(plan.deleteTrigger)
    XCTAssertTrue(plan.killWord)
    XCTAssertEqual(plan.insert, "안녕")
  }

  func testPunctuationIsRemovedAndPutBack() {
    let plan = TerminalReplacement.keystrokes(replacement: "안녕", trigger: ".")
    XCTAssertTrue(plan.deleteTrigger)
    XCTAssertTrue(plan.killWord)
    XCTAssertEqual(plan.insert, "안녕.")
  }
}

final class TerminalAppsTests: XCTestCase {
  func testRecognizesStandaloneTerminals() {
    XCTAssertTrue(TerminalApps.matches("com.apple.Terminal"))
    XCTAssertTrue(TerminalApps.matches("io.appmakes.otty"))
    XCTAssertTrue(TerminalApps.matches("com.googlecode.iterm2"))
    XCTAssertTrue(TerminalApps.matches("com.mitchellh.ghostty"))
    XCTAssertTrue(TerminalApps.matches("net.kovidgoyal.kitty"))
  }

  func testLeavesEditorsAlone() {
    XCTAssertFalse(TerminalApps.matches("com.apple.dt.Xcode"))
    XCTAssertFalse(TerminalApps.matches("com.microsoft.VSCode"))
    XCTAssertFalse(TerminalApps.matches("com.todesktop.230313mzl4w4u92"))
    XCTAssertFalse(TerminalApps.matches(nil))
    XCTAssertFalse(TerminalApps.matches(""))
  }
}
