import Foundation

@MainActor
final class IgnoreStore: ObservableObject {
  static let shared = IgnoreStore()

  @Published private(set) var words: [String]

  private let key = "ignoredTokens"

  private init() {
    let stored = UserDefaults.standard.stringArray(forKey: key) ?? []
    words = Self.normalized(stored)
  }

  func add<S: Sequence>(_ tokens: S) where S.Element == String {
    var seen = Set(words.map { $0.lowercased() })
    var next = words
    for token in Self.normalized(tokens) {
      let folded = token.lowercased()
      guard seen.insert(folded).inserted else {
        continue
      }
      next.append(token)
    }
    persist(next)
  }

  func remove(_ token: String) {
    let folded = token.lowercased()
    persist(words.filter { $0.lowercased() != folded })
  }

  private func persist(_ next: [String]) {
    words = next
    UserDefaults.standard.set(next, forKey: key)
  }

  private static func normalized<S: Sequence>(_ tokens: S) -> [String] where S.Element == String {
    tokens
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}
