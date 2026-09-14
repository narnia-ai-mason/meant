import MeantCore
import XCTest

final class ConverterTests: XCTestCase {
  func testEnglishKeysComposeHangul() {
    XCTAssertEqual(Converter.enToKo("dkssud"), "안녕")
    XCTAssertEqual(Converter.enToKo("dkssudgktpdy"), "안녕하세요")
    XCTAssertEqual(Converter.enToKo("gksrmf"), "한글")
    XCTAssertEqual(Converter.enToKo("transformer"), "ㅅㄱ문래귿ㄱ")
    XCTAssertEqual(Converter.enToKo("hello"), "ㅗ디ㅣㅐ")
    XCTAssertEqual(Converter.enToKo("HELLO"), "ㅗ띠ㅣㅒ")
    XCTAssertEqual(Converter.enToKo("Mason"), "ㅡㅁ내ㅜ")
  }

  func testHangulDecomposesToEnglishKeys() {
    XCTAssertEqual(Converter.koToEn("안녕"), "dkssud")
    XCTAssertEqual(Converter.koToEn("안녕하세요"), "dkssudgktpdy")
    XCTAssertEqual(Converter.koToEn("한글"), "gksrmf")
    XCTAssertEqual(Converter.koToEn("ㅅㄱ문래귿ㄱ"), "transformer")
    XCTAssertEqual(Converter.koToEn("ㅗ디ㅣㅐ"), "hello")
    XCTAssertEqual(Converter.koToEn("ㅡㅁ내ㅜ"), "mason")
  }

  func testShiftedKeysStayDistinct() {
    XCTAssertEqual(Converter.enToKo("qk"), "바")
    XCTAssertEqual(Converter.enToKo("Qk"), "빠")
    XCTAssertEqual(Converter.enToKo("dk"), "아")
    XCTAssertEqual(Converter.enToKo("Dk"), "아")
    XCTAssertEqual(Converter.koToEn("빠"), "Qk")
    XCTAssertEqual(Converter.koToEn("바"), "qk")
  }

  func testCompoundVowelAndFinalSplitLikeAnIME() {
    XCTAssertEqual(Converter.enToKo("hk"), "ㅘ")
    XCTAssertEqual(Converter.enToKo("dhk"), "와")
    XCTAssertEqual(Converter.enToKo("ekfrl"), "달기")
    XCTAssertEqual(Converter.enToKo("rkqtdjqtsms ekfrrkfql"), "값없는 닭갈비")
    XCTAssertEqual(Converter.koToEn("값없는 닭갈비"), "rkqtdjqtsms ekfrrkfql")
    XCTAssertEqual(Converter.koToEn("와"), "dhk")
  }

  func testPunctuationAndSpacesPassThrough() {
    XCTAssertEqual(Converter.enToKo("dkssudgktpdy."), "안녕하세요.")
    XCTAssertEqual(Converter.enToKo("dkssudgktpdy Masondlqslek."), "안녕하세요 ㅡㅁ내ㅜ입니다.")
    XCTAssertEqual(Converter.koToEn("안녕하세요."), "dkssudgktpdy.")
    XCTAssertEqual(Converter.enToKo(""), "")
    XCTAssertEqual(Converter.koToEn("123"), "123")
  }

  func testRoundTripKeepsComposedHangul() {
    let hangul = "안녕하세요 값없는 닭갈비"
    XCTAssertEqual(Converter.enToKo(Converter.koToEn(hangul)), hangul)
  }

  func testRoundTripFoldsLatinCase() {
    XCTAssertEqual(Converter.koToEn(Converter.enToKo("hello")), "hello")
    XCTAssertEqual(Converter.koToEn(Converter.enToKo("Hello")), "hello")
    XCTAssertEqual(Converter.koToEn(Converter.enToKo("HELLO")), "hEllO")
    XCTAssertEqual(Converter.koToEn(Converter.enToKo("Mason")), "mason")
  }
}
