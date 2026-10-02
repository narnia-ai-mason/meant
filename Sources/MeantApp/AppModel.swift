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
    var range: Range<Int>?
    var original: String
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
    space.onSpace = { [weak self] typed in
      self?.handleSpace(typed: typed)
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

  private func handleSpace(typed: String) {
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
      let target = resolve(
        snapshot: snapshot,
        typed: typed,
        typedOnASCIILayout: space.typedFromASCIILayout,
        suggest: { detector.inspect($0) }
      )
    else {
      return
    }
    let captured = Pending(
      snapshot: snapshot,
      range: target.range,
      original: target.original,
      suggestion: target.suggestion
    )
    pending = captured
    hud.show(
      original: target.suggestion.original,
      replacement: target.suggestion.replacement,
      anchor: snapshot.caretScreenRect,
      onConfirm: { [weak self] in
        self?.pending = nil
        self?.apply(captured)
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
      let target = resolve(
        snapshot: snapshot,
        typed: space.currentWord,
        typedOnASCIILayout: space.typedFromASCIILayout,
        suggest: { Flip.force($0) }
      )
    else {
      return
    }
    apply(
      Pending(
        snapshot: snapshot,
        range: target.range,
        original: target.original,
        suggestion: target.suggestion
      )
    )
  }

  private func apply(_ pending: Pending) {
    let live = Editor.read() ?? pending.snapshot
    let original = pending.original
    let rangeToReplace: Range<Int>?
    if let range = pending.range, Editor.substring(live.text, range) == original {
      rangeToReplace = range
    } else if let token = CaretToken.resolve(
      text: live.text,
      caretUTF16: live.selectedUTF16.upperBound,
      skipTrailingWhitespace: true
    ), token.token == pending.suggestion.original || Editor.substring(live.text, token.utf16) == original
    {
      rangeToReplace = CaretToken.extendingThroughTrailingSpaces(
        token: token.utf16,
        caretUTF16: live.selectedUTF16.upperBound,
        text: live.text
      )
    } else if let found = CaretToken.locate(
      original,
      preferring: live.selectedUTF16.upperBound,
      in: live.text
    ) {
      rangeToReplace = CaretToken.extendingThroughTrailingSpaces(
        token: found,
        caretUTF16: live.selectedUTF16.upperBound,
        text: live.text
      )
    } else {
      rangeToReplace = pending.range
    }
    guard
      Editor.replace(
        in: live,
        utf16: rangeToReplace,
        original: original,
        with: pending.suggestion.replacement
      )
    else {
      return
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    InputSource.select(pending.suggestion.direction)
  }

  private func resolve(
    snapshot: Editor.Snapshot,
    typed: String,
    typedOnASCIILayout: Bool,
    suggest: (String) -> Suggestion?
  ) -> (suggestion: Suggestion, original: String, range: Range<Int>?)? {
    if let token = CaretToken.resolve(
      text: snapshot.text,
      caretUTF16: snapshot.selectedUTF16.upperBound,
      skipTrailingWhitespace: true
    ), let suggestion = suggest(token.token) {
      let range = CaretToken.extendingThroughTrailingSpaces(
        token: token.utf16,
        caretUTF16: snapshot.selectedUTF16.upperBound,
        text: snapshot.text
      )
      return (suggestion, Editor.substring(snapshot.text, range) ?? token.token, range)
    }
    guard
      let fallback = fallbackToken(typed, asciiLayout: typedOnASCIILayout),
      let suggestion = suggest(fallback)
    else {
      return nil
    }
    let original = fallback
    if let found = CaretToken.locate(
      original,
      preferring: snapshot.selectedUTF16.upperBound,
      in: snapshot.text
    ) {
      let range = CaretToken.extendingThroughTrailingSpaces(
        token: found,
        caretUTF16: snapshot.selectedUTF16.upperBound,
        text: snapshot.text
      )
      return (suggestion, Editor.substring(snapshot.text, range) ?? original, range)
    }
    return (suggestion, original, nil)
  }

  private func fallbackToken(_ typed: String, asciiLayout: Bool) -> String? {
    guard
      asciiLayout,
      !typed.isEmpty,
      typed.allSatisfy(\.isASCII),
      typed.allSatisfy(\.isLetter)
    else {
      return nil
    }
    return typed
  }
}
