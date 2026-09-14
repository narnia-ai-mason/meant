import MeantCore
import XCTest

final class ReplacementCaretTests: XCTestCase {
  func testCaretFollowsALongerReplacementAtTheStart() {
    let before = "뭉"
    let after = "and"
    let end = ReplacementCaret.endUTF16(
      before: before,
      replaced: 0..<1,
      replacement: "and",
      after: after
    )
    XCTAssertEqual(end, 3)
  }

  func testCaretFollowsAReplacementInTheMiddleOfASentence() {
    let before = "hello 뭉"
    let after = "hello and"
    let end = ReplacementCaret.endUTF16(
      before: before,
      replaced: 6..<7,
      replacement: "and",
      after: after
    )
    XCTAssertEqual(end, 9)
  }

  func testCaretFollowsHangulAfterAnEnglishTypo() {
    let before = "dkssudgktpdy "
    let after = "안녕하세요 "
    let end = ReplacementCaret.endUTF16(
      before: before,
      replaced: 0..<12,
      replacement: "안녕하세요",
      after: after
    )
    XCTAssertEqual(end, 5)
  }

  func testCaretUsesTheFieldsNormalization() {
    let before = "dkssudgktpdy"
    let replacement = "안녕하세요"
    let nfd = replacement.decomposedStringWithCanonicalMapping
    let end = ReplacementCaret.endUTF16(
      before: before,
      replaced: 0..<12,
      replacement: replacement,
      after: nfd
    )
    XCTAssertEqual(end, (nfd as NSString).length)
    XCTAssertNotEqual(end, (replacement as NSString).length)
  }
}
