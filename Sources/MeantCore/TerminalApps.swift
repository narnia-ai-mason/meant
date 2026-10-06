public enum TerminalApps {
  public static func matches(_ bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
      return false
    }
    let identifier = bundleIdentifier.lowercased()
    if bundleIdentifiers.contains(identifier) {
      return true
    }
    return identifier.split(separator: ".").contains { part in
      let name = String(part)
      return fragments.contains(name) || name.contains("iterm") || name.contains("terminal")
    }
  }

  private static let bundleIdentifiers: Set<String> = [
    "com.apple.terminal",
    "com.googlecode.iterm2",
    "com.googlecode.iterm2.beta",
    "dev.warp.warp-stable",
    "dev.warp.warp",
    "com.mitchellh.ghostty",
    "net.kovidgoyal.kitty",
    "org.alacritty",
    "io.alacritty",
    "com.github.wez.wezterm",
    "co.zeit.hyper",
    "org.tabby",
    "io.appmakes.otty",
    "com.raphaelamorim.rio",
  ]

  private static let fragments: Set<String> = [
    "terminal",
    "ghostty",
    "kitty",
    "alacritty",
    "wezterm",
    "warp",
    "warp-stable",
    "otty",
    "hyper",
    "tabby",
  ]
}
