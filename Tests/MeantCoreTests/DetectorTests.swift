import MeantCore
import XCTest

final class DetectorTests: XCTestCase {
  private let detector = Detector(
    english: WordList([
      "hello", "transformer", "mason", "this", "that", "and", "to", "for",
      "apple", "good", "test", "the", "you", "are", "memory",
    ]),
    ignored: ["narnia", "bdsk"]
  )

  func testSuggestsMistypedKoreanFromEnglishKeys() {
    let suggestion = detector.inspect("dkssudgktpdy")
    XCTAssertEqual(suggestion?.replacement, "안녕하세요")
    XCTAssertEqual(suggestion?.direction, .englishToKorean)

    let withStop = detector.inspect("dkssud.")
    XCTAssertEqual(withStop?.original, "dkssud.")
    XCTAssertEqual(withStop?.replacement, "안녕.")

    XCTAssertEqual(Converter.enToKo("EjTdmf"), "떴을")
    XCTAssertEqual(detector.inspect("EjTdmf")?.replacement, "떴을")
  }

  func testSuggestsMistypedEnglishFromHangulKeys() {
    let suggestion = detector.inspect("ㅅㄱ문래귿ㄱ")
    XCTAssertEqual(suggestion?.replacement, "transformer")
    XCTAssertEqual(suggestion?.direction, .koreanToEnglish)

    XCTAssertEqual(detector.inspect("ㅗ디ㅣㅐ")?.replacement, "hello")
    XCTAssertEqual(detector.inspect("메ㅔㅣㄷ")?.replacement, "apple")
    XCTAssertEqual(detector.inspect("ㅔㅑㅜㅜㅑㅜㅎ")?.replacement, "pinning")
  }

  func testSuggestsWhenSourceLooksWrongEvenIfDestinationIsUnknown() {
    XCTAssertEqual(detector.inspect("ㅋㅋㅋ")?.replacement, "zzz")
    XCTAssertEqual(detector.inspect("ㅎㅎ")?.replacement, "gg")
    XCTAssertEqual(detector.inspect("ㅠㅠ")?.replacement, "bb")
  }

  func testStaysQuietWhenNeitherSideLooksWrong() {
    XCTAssertNil(detector.inspect("hello"))
    XCTAssertNil(detector.inspect("transformer"))
    XCTAssertNil(detector.inspect("안녕하세요"))
    XCTAssertNil(detector.inspect("한글"))
    XCTAssertNil(detector.inspect("Mason"))
    XCTAssertNil(detector.inspect("and"))
    XCTAssertNil(detector.inspect("무"))
    XCTAssertNil(detector.inspect("this"))
    XCTAssertNil(detector.inspect("소얀"))
  }

  func testStaysQuietOnShortOrBrokenTokens() {
    XCTAssertNil(detector.inspect("dks"))
    XCTAssertNil(detector.inspect("good"))
    XCTAssertNil(detector.inspect("to"))
    XCTAssertNil(detector.inspect(""))
  }

  func testStaysQuietOnIgnoredAndCodeLikeTokens() {
    XCTAssertNil(detector.inspect("Narnia"))
    XCTAssertNil(detector.inspect("bdsk"))
    XCTAssertNil(detector.inspect("getValue"))
    XCTAssertNil(detector.inspect("snake_case"))
    XCTAssertNil(detector.inspect("v2"))
    XCTAssertNil(detector.inspect("HELLO"))
    XCTAssertNil(detector.inspect("user@narnia.dev"))
  }

  func testStaysQuietWhenFlippedHangulIsNotComposed() {
    XCTAssertEqual(Converter.enToKo("MLOps"), "ㅢㅒㅔㄴ")
    XCTAssertNil(detector.inspect("MLOps"))
    XCTAssertNil(detector.inspect("asdf"))
    XCTAssertNil(Detector.standard.inspect("MLOps"))
  }

  func testStandardEnglishListKnowsCommonWords() {
    let standard = Detector.standard
    XCTAssertNil(standard.inspect("hello"))
    XCTAssertNil(standard.inspect("transformer"))
    XCTAssertEqual(standard.inspect("dkssudgktpdy")?.replacement, "안녕하세요")
    XCTAssertEqual(standard.inspect("ㅅㄱ문래귿ㄱ")?.replacement, "transformer")
    XCTAssertEqual(standard.inspect("ㅔㅑㅜㅜㅑㅜㅎ")?.replacement, "pinning")
    XCTAssertNil(standard.ignoring(["dkssudgktpdy"]).inspect("dkssudgktpdy"))
  }
}
