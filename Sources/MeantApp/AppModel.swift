import Foundation
import MeantCore

@MainActor
final class AppModel {
  let hud = HUDController()
  let space = SpaceMonitor()
  private(set) var detector = Detector.standard

  private var pending: Pending?

  private struct Pending {
    var snapshot: Editor.Snapshot
    var range: Range<Int>
    var suggestion: Suggestion
  }

  func start() {
    hud.onCancel = { [weak self] in
      self?.pending = nil
    }
    hud.onVisibilityChange = { [weak self] visible in
      self?.space.setHUDVisible(visible)
    }
    space.isHUDVisible = { [weak self] in
      self?.hud.isVisible ?? false
    }
    space.onSpace = { [weak self] in
      self?.handleSpace()
    }
    space.onOtherKey = { [weak self] in
      self?.hud.hide()
    }
    space.onHUDCommit = { [weak self] in
      self?.hud.handle(.commit)
    }
    space.onHUDCancel = { [weak self] in
      self?.hud.hide()
    }
    space.onHUDIgnore = { [weak self] in
      self?.hud.handle(.ignore)
    }
    space.start()
    HotKeyMonitor.shared.onFlip = { [weak self] in
      self?.handleHotkey()
    }
    HotKeyMonitor.shared.register(SettingsStore.shared.hotkey)
    reloadDetector()
  }

  func reloadDetector() {
    detector = Detector.standard.ignoring(IgnoreStore.shared.words)
  }

  func ignore(_ suggestion: Suggestion) {
    IgnoreStore.shared.add(suggestion.ignoreKeys)
    reloadDetector()
  }

  func restartInputTap() {
    space.start()
  }

  private func handleSpace() {
    if hud.isVisible {
      hud.hide()
      return
    }
    guard Editor.isTrusted else {
      return
    }
    guard let snapshot = Editor.read() else {
      return
    }
    guard
      let token = CaretToken.resolve(
        text: snapshot.text,
        caretUTF16: snapshot.selectedUTF16.upperBound,
        skipTrailingWhitespace: true
      )
    else {
      return
    }
    guard let suggestion = detector.inspect(token.token) else {
      return
    }
    let range = CaretToken.extendingThroughTrailingSpaces(
      token: token.utf16,
      caretUTF16: snapshot.selectedUTF16.upperBound,
      text: snapshot.text
    )
    let captured = Pending(snapshot: snapshot, range: range, suggestion: suggestion)
    pending = captured
    hud.show(
      original: suggestion.original,
      replacement: suggestion.replacement,
      anchor: snapshot.caretScreenRect,
      onConfirm: { [weak self] in
        self?.pending = nil
        self?.apply(captured.suggestion, to: captured.snapshot, range: captured.range)
      },
      onIgnore: { [weak self] in
        self?.ignore(captured.suggestion)
      }
    )
  }

  func handleHotkey() {
    hud.hide()
    guard Editor.ensureTrusted() else {
      return
    }
    guard let snapshot = Editor.read() else {
      return
    }
    guard
      let token = CaretToken.resolve(
        text: snapshot.text,
        caretUTF16: snapshot.selectedUTF16.upperBound,
        skipTrailingWhitespace: true
      )
    else {
      return
    }
    guard let suggestion = Flip.force(token.token) else {
      return
    }
    apply(suggestion, to: snapshot, range: token.utf16)
  }

  private func apply(_ suggestion: Suggestion, to snapshot: Editor.Snapshot, range: Range<Int>) {
    let live = Editor.read() ?? snapshot
    let rangeToReplace: Range<Int>
    if Editor.substring(live.text, range) == Editor.substring(snapshot.text, range) {
      rangeToReplace = range
    } else if let token = CaretToken.resolve(
      text: live.text,
      caretUTF16: live.selectedUTF16.upperBound,
      skipTrailingWhitespace: true
    ) {
      rangeToReplace = CaretToken.extendingThroughTrailingSpaces(
        token: token.utf16,
        caretUTF16: live.selectedUTF16.upperBound,
        text: live.text
      )
    } else {
      rangeToReplace = range
    }
    guard Editor.replace(in: live, utf16: rangeToReplace, with: suggestion.replacement) else {
      return
    }
    InputSource.select(suggestion.direction)
  }
}
