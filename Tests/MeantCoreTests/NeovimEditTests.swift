import MeantCore
import XCTest

final class NeovimModeTests: XCTestCase {
  func testInsertAndReplaceAcceptCorrections() {
    XCTAssertTrue(NeovimMode.isTyping("i"))
    XCTAssertTrue(NeovimMode.isTyping("ic"))
    XCTAssertTrue(NeovimMode.isTyping("R"))
    XCTAssertFalse(NeovimMode.isTyping("n"))
    XCTAssertFalse(NeovimMode.isTyping("c"))
  }

  func testCommandModesGuardHangul() {
    XCTAssertTrue(NeovimMode.guardsHangul("n"))
    XCTAssertTrue(NeovimMode.guardsHangul("no"))
    XCTAssertTrue(NeovimMode.guardsHangul("niI"))
    XCTAssertTrue(NeovimMode.guardsHangul("v"))
    XCTAssertTrue(NeovimMode.guardsHangul("V"))
    XCTAssertTrue(NeovimMode.guardsHangul("\u{16}"))
    XCTAssertTrue(NeovimMode.guardsHangul("s"))
    XCTAssertFalse(NeovimMode.guardsHangul("i"))
    XCTAssertFalse(NeovimMode.guardsHangul("c"))
    XCTAssertFalse(NeovimMode.guardsHangul("t"))
  }
}

final class NeovimEditPlanTests: XCTestCase {
  func testSpaceTriggerReplacesTheWordAndKeepsTheSpace() {
    let line = "echo dkssud "
    let edit = NeovimEditPlan.plan(
      line: line, cursorByte: line.utf8.count, typed: "dkssud", replacement: "안녕", trigger: " "
    )
    XCTAssertEqual(edit?.text, "안녕 ")
    XCTAssertEqual(edit.map { slice(line, $0) }, "echo 안녕 ")
  }

  func testHangulJamoUsesTheSameReplacement() {
    let line = "ㅊㅣㄷㅁㄱ "
    let edit = NeovimEditPlan.plan(
      line: line, cursorByte: line.utf8.count, typed: "ㅊㅣㄷㅁㄱ", replacement: "clear", trigger: " "
    )
    XCTAssertEqual(edit?.text, "clear ")
    XCTAssertEqual(edit.map { slice(line, $0) }, "clear ")
  }

  func testCommittedJamoPrefixIsStillReplaced() {
    let line = "echo ㅊ "
    let edit = NeovimEditPlan.plan(
      line: line, cursorByte: line.utf8.count, typed: "ㅊㅣㄷㅁㄱ", replacement: "clear", trigger: " "
    )
    XCTAssertEqual(edit.map { slice(line, $0) }, "echo clear ")
  }

  func testHotkeyDoesNotInventASpace() {
    let line = "echo dkssud"
    let edit = NeovimEditPlan.plan(
      line: line, cursorByte: line.utf8.count, typed: "dkssud", replacement: "안녕", trigger: nil
    )
    XCTAssertEqual(edit.map { slice(line, $0) }, "echo 안녕")
  }

  func testCursorInTheMiddleLeavesTheRestOfTheLine() {
    let line = "echo dkssud more"
    let cursor = line.utf8.distance(from: line.startIndex, to: line.range(of: " more")!.lowerBound)
    let edit = NeovimEditPlan.plan(
      line: line, cursorByte: cursor, typed: "dkssud", replacement: "안녕", trigger: nil
    )
    XCTAssertEqual(edit.map { slice(line, $0) }, "echo 안녕 more")
  }

  func testAsciiFragmentIsNotEnough() {
    let line = "echo d "
    let edit = NeovimEditPlan.plan(
      line: line, cursorByte: line.utf8.count, typed: "dkssud", replacement: "안녕", trigger: " "
    )
    XCTAssertNil(edit)
  }

  private func slice(_ line: String, _ edit: NeovimEdit) -> String {
    var bytes = Array(line.utf8)
    bytes.replaceSubrange(edit.startByte..<edit.endByte, with: Array(edit.text.utf8))
    return String(decoding: bytes, as: UTF8.self)
  }
}
