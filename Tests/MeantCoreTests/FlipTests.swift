import MeantCore
import XCTest

final class FlipTests: XCTestCase {
  func testForceFlipsCollisionWordsWithoutADictionary() {
    let suggestion = Flip.force("무")
    XCTAssertEqual(suggestion?.replacement, "an")
    XCTAssertEqual(suggestion?.direction, .koreanToEnglish)

    XCTAssertEqual(Flip.force("and")?.replacement, "뭉")
    XCTAssertEqual(Flip.force("dkssud.")?.replacement, "안녕.")
  }

  func testCaretReadsTheEojeolBeforeATrailingSpace() {
    let line = "hello dkssudgktpdy "
    let found = CaretToken.resolve(
      text: line,
      caretUTF16: (line as NSString).length,
      skipTrailingWhitespace: true
    )
    XCTAssertEqual(found?.token, "dkssudgktpdy")
  }

  func testCaretReadsTheWordUnderTheCaret() {
    let line = "hello 무"
    let found = CaretToken.resolve(
      text: line,
      caretUTF16: (line as NSString).length,
      skipTrailingWhitespace: false
    )
    XCTAssertEqual(found?.token, "무")
  }

  func testSelectionAfterSpaceIncludesTheTrailingSpace() {
    let line = "dkssudgktpdy "
    let token = CaretToken.resolve(
      text: line,
      caretUTF16: (line as NSString).length,
      skipTrailingWhitespace: true
    )
    let selected = CaretToken.extendingThroughTrailingSpaces(
      token: token!.utf16,
      caretUTF16: (line as NSString).length,
      text: line
    )
    XCTAssertEqual(token?.token, "dkssudgktpdy")
    XCTAssertEqual(selected, 0..<13)
  }

  func testCaretSkipsALeadingNewlineWhenCaretIsAfterTheWord() {
    let line = "\n뭉"
    let found = CaretToken.resolve(
      text: line,
      caretUTF16: (line as NSString).length,
      skipTrailingWhitespace: true
    )
    XCTAssertEqual(found?.token, "뭉")
    XCTAssertEqual(found?.utf16, 1..<2)
  }
}
