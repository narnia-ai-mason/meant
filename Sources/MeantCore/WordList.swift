import Foundation

public struct WordList: Sendable {
  private let words: Set<String>

  public init<S: Sequence>(_ words: S) where S.Element == String {
    self.words = Set(words.map { $0.lowercased() }.filter { !$0.isEmpty })
  }

  public static let commonEnglish = WordList(resource: "english")

  public func contains(_ word: String) -> Bool {
    let folded = word.lowercased()
    if words.contains(folded) {
      return true
    }
    return stemmed(folded).contains { words.contains($0) }
  }

  private func stemmed(_ word: String) -> [String] {
    var stems: [String] = []
    for suffix in ["es", "ed", "er", "ly", "s"] {
      guard word.hasSuffix(suffix) else { continue }
      let stem = String(word.dropLast(suffix.count))
      if stem.count >= 3 {
        stems.append(stem)
      }
    }
    if word.hasSuffix("ing") {
      let stem = String(word.dropLast(3))
      if stem.count >= 3 {
        stems.append(stem)
        stems.append(stem + "e")
        if let last = stem.last, stem.dropLast().last == last {
          let undoubled = String(stem.dropLast())
          if undoubled.count >= 3 {
            stems.append(undoubled)
          }
        }
      }
    }
    return stems
  }
}

extension WordList {
  fileprivate init(resource name: String) {
    let fileName = "\(name).txt"
    let candidates = [
      Bundle.module.url(forResource: name, withExtension: "txt"),
      Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Resources"),
      Bundle.main.resourceURL?
        .appendingPathComponent("Meant_MeantCore.bundle")
        .appendingPathComponent(fileName),
      Bundle.main.bundleURL
        .appendingPathComponent("Meant_MeantCore.bundle")
        .appendingPathComponent(fileName),
    ]
    let url = candidates.compactMap { $0 }.first {
      FileManager.default.isReadableFile(atPath: $0.path)
    }
    let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    self.init(text.split(whereSeparator: \.isNewline).map(String.init))
  }
}
