import MeantCore
import XCTest

final class WordEndTests: XCTestCase {
  func testSentenceAndClauseMarksEndAWord() {
    for mark in [".", ",", "?", "!", ":", ";", "…", "~", "。", "，", "？", "！"] {
      XCTAssertTrue(WordEnd.isDelimiter(mark), mark)
    }
  }

  func testBracketsAndQuotesEndAWord() {
    for mark in ["(", ")", "[", "]", "{", "}", "\"", "'", "“", "”", "‘", "’", "「", "」", "『", "』"] {
      XCTAssertTrue(WordEnd.isDelimiter(mark), mark)
    }
  }

  func testLettersSpacesAndMidWordMarksDoNotEndAWord() {
    for mark in ["a", "안", " ", "-", "_", "/", "@", "#", "*", "·"] {
      XCTAssertFalse(WordEnd.isDelimiter(mark), mark)
    }
    XCTAssertFalse(WordEnd.isDelimiter(""))
    XCTAssertFalse(WordEnd.isDelimiter("..."))
  }
}
