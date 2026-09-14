enum Stroke: Equatable {
  case consonant(Int)
  case vowel(Int)
}

enum Dubeolsik {
  static func stroke(for character: Character) -> Stroke? {
    strokes[character]
  }

  static func keys(choseong: Int) -> String {
    choseongKeys[choseong]
  }

  static func keys(jungseong: Int) -> String {
    jungseongKeys[jungseong]
  }

  static func keys(jongseong: Int) -> String {
    jongseongKeys[jongseong]
  }

  static func compatibilityJamoKeys(_ character: Character) -> String? {
    compatibilityKeys[character]
  }

  static func compatibilityChoseong(_ index: Int) -> Character {
    compatibilityChoseongs[index]
  }

  static func compatibilityJungseong(_ index: Int) -> Character {
    compatibilityJungseongs[index]
  }

  static func jongseong(fromChoseong index: Int) -> Int? {
    choseongToJongseong[index]
  }

  static func choseong(fromJongseong index: Int) -> Int? {
    jongseongToChoseong[index]
  }

  static func compoundJungseong(_ current: Int, _ incoming: Int) -> Int? {
    compoundJung[current * 21 + incoming]
  }

  static func compoundJongseong(_ current: Int, incomingChoseong: Int) -> Int? {
    compoundJong[current * 19 + incomingChoseong]
  }

  static func splitJongseong(_ index: Int) -> (rest: Int, trailingChoseong: Int)? {
    splitJong[index]
  }
}

private let strokes: [Character: Stroke] = [
  "q": .consonant(7), "Q": .consonant(8),
  "w": .consonant(12), "W": .consonant(13),
  "e": .consonant(3), "E": .consonant(4),
  "r": .consonant(0), "R": .consonant(1),
  "t": .consonant(9), "T": .consonant(10),
  "y": .vowel(12), "Y": .vowel(12),
  "u": .vowel(6), "U": .vowel(6),
  "i": .vowel(2), "I": .vowel(2),
  "o": .vowel(1), "O": .vowel(3),
  "p": .vowel(5), "P": .vowel(7),
  "a": .consonant(6), "A": .consonant(6),
  "s": .consonant(2), "S": .consonant(2),
  "d": .consonant(11), "D": .consonant(11),
  "f": .consonant(5), "F": .consonant(5),
  "g": .consonant(18), "G": .consonant(18),
  "h": .vowel(8), "H": .vowel(8),
  "j": .vowel(4), "J": .vowel(4),
  "k": .vowel(0), "K": .vowel(0),
  "l": .vowel(20), "L": .vowel(20),
  "z": .consonant(15), "Z": .consonant(15),
  "x": .consonant(16), "X": .consonant(16),
  "c": .consonant(14), "C": .consonant(14),
  "v": .consonant(17), "V": .consonant(17),
  "b": .vowel(17), "B": .vowel(17),
  "n": .vowel(13), "N": .vowel(13),
  "m": .vowel(18), "M": .vowel(18),
]

private let choseongKeys = [
  "r", "R", "s", "e", "E", "f", "a", "q", "Q", "t", "T", "d", "w", "W", "c", "z", "x", "v", "g",
]

private let jungseongKeys = [
  "k", "o", "i", "O", "j", "p", "u", "P", "h", "hk", "ho", "hl", "y",
  "n", "nj", "np", "nl", "b", "m", "ml", "l",
]

private let jongseongKeys = [
  "", "r", "R", "rt", "s", "sw", "sg", "e", "f", "fr", "fa", "fq", "ft", "fx", "fv", "fg",
  "a", "q", "qt", "t", "T", "d", "w", "c", "z", "x", "v", "g",
]

private let compatibilityChoseongs: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
private let compatibilityJungseongs: [Character] = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")

private let compatibilityKeys: [Character: String] = {
  var keys: [Character: String] = [
    "ㄳ": "rt", "ㄵ": "sw", "ㄶ": "sg",
    "ㄺ": "fr", "ㄻ": "fa", "ㄼ": "fq", "ㄽ": "ft", "ㄾ": "fx", "ㄿ": "fv", "ㅀ": "fg",
    "ㅄ": "qt",
  ]
  for (index, character) in compatibilityChoseongs.enumerated() {
    keys[character] = choseongKeys[index]
  }
  for (index, character) in compatibilityJungseongs.enumerated() {
    keys[character] = jungseongKeys[index]
  }
  return keys
}()

private let choseongToJongseong: [Int?] = [
  1, 2, 4, 7, nil, 8, 16, 17, nil, 19, 20, 21, 22, nil, 23, 24, 25, 26, 27,
]

private let jongseongToChoseong: [Int: Int] = [
  1: 0, 2: 1, 4: 2, 7: 3, 8: 5, 16: 6, 17: 7, 19: 9, 20: 10, 21: 11,
  22: 12, 23: 14, 24: 15, 25: 16, 26: 17, 27: 18,
]

private let compoundJung: [Int: Int] = [
  8 * 21 + 0: 9,
  8 * 21 + 1: 10,
  8 * 21 + 20: 11,
  13 * 21 + 4: 14,
  13 * 21 + 5: 15,
  13 * 21 + 20: 16,
  18 * 21 + 20: 19,
]

private let compoundJong: [Int: Int] = [
  1 * 19 + 9: 3,
  4 * 19 + 12: 5,
  4 * 19 + 18: 6,
  8 * 19 + 0: 9,
  8 * 19 + 6: 10,
  8 * 19 + 7: 11,
  8 * 19 + 9: 12,
  8 * 19 + 16: 13,
  8 * 19 + 17: 14,
  8 * 19 + 18: 15,
  17 * 19 + 9: 18,
]

private let splitJong: [Int: (Int, Int)] = [
  3: (1, 9),
  5: (4, 12),
  6: (4, 18),
  9: (8, 0),
  10: (8, 6),
  11: (8, 7),
  12: (8, 9),
  13: (8, 16),
  14: (8, 17),
  15: (8, 18),
  18: (17, 9),
]
