import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import MeantCore

enum MeantEvent {
  static let signature: Int64 = 0x4D45414E
}

@MainActor
enum Editor {
  struct Snapshot {
    var element: AXUIElement
    var text: String
    var selectedUTF16: Range<Int>
    var caretScreenRect: CGRect?
  }

  static func ensureTrusted() -> Bool {
    AXIsProcessTrustedWithOptions(
      ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    )
  }

  static var isTrusted: Bool {
    AXIsProcessTrusted()
  }

  static func read() -> Snapshot? {
    guard let app = NSWorkspace.shared.frontmostApplication,
      app.bundleIdentifier != Bundle.main.bundleIdentifier
    else {
      return nil
    }
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    guard let element = copyElement(appElement, kAXFocusedUIElementAttribute) else {
      return nil
    }
    if role(of: element) == "AXSecureTextField" {
      return nil
    }
    let text = readText(from: element)
    let selected = selectedUTF16Range(element) ?? utf16Cursor(in: text)
    return Snapshot(
      element: element,
      text: text,
      selectedUTF16: selected,
      caretScreenRect: bounds(element, utf16: selected) ?? fieldFrame(element)
    )
  }

  nonisolated static func substring(_ text: String, _ utf16: Range<Int>) -> String? {
    let ns = text as NSString
    guard utf16.lowerBound >= 0, utf16.upperBound <= ns.length else {
      return nil
    }
    return ns.substring(with: NSRange(location: utf16.lowerBound, length: utf16.count))
  }

  static func replace(
    in snapshot: Snapshot,
    utf16: Range<Int>?,
    original: String,
    with replacement: String,
    trigger: String? = nil
  ) -> Bool {
    let element = snapshot.element
    if isTerminal(element) {
      return replaceInTerminal(replacement: replacement, trigger: trigger)
    }
    var before = readText(from: element)
    var range = utf16.flatMap { clamped($0, in: before) }
    var expected = original
    if let currentRange = range, let text = substring(before, currentRange), sameForms(text, original) {
      expected = text
    } else if let found = CaretToken.locate(
      original,
      preferring: range?.lowerBound ?? snapshot.selectedUTF16.upperBound,
      in: before
    ) {
      range = found
      expected = original
    } else {
      range = nil
    }
    if expected.contains(where: isHangulLetter), let currentRange = range {
      let committed = commitHangul(in: element, original: expected, range: currentRange)
      before = readText(from: element)
      if let committed, let text = substring(before, committed) {
        range = committed
        expected = text
      } else if let found = CaretToken.locate(expected, preferring: currentRange.lowerBound, in: before) {
        range = found
      }
    }
    guard selectReplacement(in: element, range: range, expected: expected) else {
      return false
    }
    var pid: pid_t = 0
    let target = AXUIElementGetPid(element, &pid) == .success ? pid : nil
    postKey(CGKeyCode(kVK_Delete), pid: target)
    settle(0.08)
    let inserted = replacement + trailingSpaces(expected)
    if isCollapsed(element), insertSelectedText(element, inserted) {
      return true
    }
    return paste(inserted)
  }
}

@MainActor
private func commitHangul(in element: AXUIElement, original: String, range: Range<Int>) -> Range<Int>? {
  var pid: pid_t = 0
  let target = AXUIElementGetPid(element, &pid) == .success ? pid : nil
  postKey(CGKeyCode(kVK_RightArrow), pid: target)
  settle()
  return CaretToken.locate(original, preferring: range.lowerBound, in: readText(from: element))
}

private func isHangulLetter(_ character: Character) -> Bool {
  character.unicodeScalars.contains { scalar in
    (0x1100...0x11FF).contains(scalar.value)
      || (0x3130...0x318F).contains(scalar.value)
      || (0xAC00...0xD7A3).contains(scalar.value)
  }
}

private func selectReplacement(in element: AXUIElement, range: Range<Int>?, expected: String) -> Bool {
  if selectBackward(in: element, expected: expected) {
    return true
  }
  collapseSelection(in: element)
  guard let range else {
    return false
  }
  return selectExactly(element, range: range, expected: expected)
}

private func selectBackward(in element: AXUIElement, expected: String) -> Bool {
  let count = expected.count
  guard count > 0 else {
    return false
  }
  var pid: pid_t = 0
  let target = AXUIElementGetPid(element, &pid) == .success ? pid : nil
  for _ in 0..<count {
    postKey(CGKeyCode(kVK_LeftArrow), pid: target, flags: .maskShift, hid: true)
    settle(0.008)
  }
  settle()
  return selectionMatches(element, expected: expected)
}

private func collapseSelection(in element: AXUIElement) {
  guard let selected = selectedUTF16Range(element), selected.count > 0 else {
    return
  }
  _ = setSelectedRange(element, selected.upperBound..<selected.upperBound)
  settle()
}

private func selectExactly(_ element: AXUIElement, range: Range<Int>, expected: String) -> Bool {
  guard setSelectedRange(element, range) else {
    return false
  }
  settle()
  guard selectedUTF16Range(element) == range else {
    return false
  }
  return selectionMatches(element, expected: expected)
}

private func selectionMatches(_ element: AXUIElement, expected: String) -> Bool {
  if let selected = copyString(element, kAXSelectedTextAttribute), !selected.isEmpty {
    return sameForms(selected, expected)
  }
  guard let range = selectedUTF16Range(element), range.count > 0 else {
    return false
  }
  if let text = Editor.substring(readText(from: element), range) {
    return sameForms(text, expected)
  }
  return range.count == (expected as NSString).length
}

private func trailingSpaces(_ text: String) -> String {
  let ns = text as NSString
  var start = ns.length
  while start > 0 {
    let unit = ns.substring(with: NSRange(location: start - 1, length: 1))
    if unit == " " || unit == "\t" {
      start -= 1
    } else {
      break
    }
  }
  return ns.substring(from: start)
}

private func clamped(_ utf16: Range<Int>, in text: String) -> Range<Int>? {
  let length = (text as NSString).length
  guard utf16.lowerBound >= 0, utf16.upperBound <= length, utf16.lowerBound < utf16.upperBound else {
    return nil
  }
  return utf16
}

private func isTerminal(_ element: AXUIElement) -> Bool {
  var pid: pid_t = 0
  guard AXUIElementGetPid(element, &pid) == .success else {
    return false
  }
  return TerminalApps.matches(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
}

private func replaceInTerminal(replacement: String, trigger: String?) -> Bool {
  let plan = TerminalReplacement.keystrokes(replacement: replacement, trigger: trigger)
  // Let the confirming key finish before editing, or the first edit is swallowed.
  settle(0.06)
  if plan.deleteTrigger {
    postKey(CGKeyCode(kVK_Delete), pid: nil, hid: true)
    settle(0.03)
  }
  if plan.killWord {
    postKey(CGKeyCode(kVK_ANSI_W), pid: nil, flags: .maskControl, hid: true)
    settle(0.05)
  }
  guard !plan.insert.isEmpty else {
    return plan.deleteTrigger || plan.killWord
  }
  return paste(plan.insert)
}

private func settle(_ seconds: TimeInterval = 0.03) {
  RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

private func isCollapsed(_ element: AXUIElement) -> Bool {
  guard let selected = selectedUTF16Range(element) else {
    return true
  }
  return selected.count == 0
}

private func insertSelectedText(_ element: AXUIElement, _ text: String) -> Bool {
  let before = readText(from: element)
  guard setSelectedText(element, text) else {
    return false
  }
  settle()
  let after = readText(from: element)
  return after != before && containsLiteral(after, text)
}

private func setSelectedText(_ element: AXUIElement, _ text: String) -> Bool {
  AXUIElementSetAttributeValue(
    element,
    kAXSelectedTextAttribute as CFString,
    text as CFTypeRef
  ) == .success
}

private func containsLiteral(_ haystack: String, _ needle: String) -> Bool {
  let ns = haystack as NSString
  return forms(needle).contains { ns.range(of: $0).location != NSNotFound }
}

private func sameForms(_ left: String, _ right: String) -> Bool {
  forms(left).contains { candidate in
    forms(right).contains { $0 == candidate }
  }
}

private func forms(_ text: String) -> [String] {
  var seen = Set<String>()
  return [text, text.precomposedStringWithCanonicalMapping, text.decomposedStringWithCanonicalMapping]
    .filter { seen.insert($0).inserted }
}

private func paste(_ text: String) -> Bool {
  let pasteboard = NSPasteboard.general
  let previous = pasteboard.string(forType: .string)
  pasteboard.clearContents()
  pasteboard.setString(text, forType: .string)
  postCommandV()
  settle(0.12)
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
    pasteboard.clearContents()
    if let previous {
      pasteboard.setString(previous, forType: .string)
    }
  }
  return true
}

private func postCommandV() {
  let source = CGEventSource(stateID: .hidSystemState)
  for down in [true, false] {
    guard
      let event = CGEvent(
        keyboardEventSource: source,
        virtualKey: CGKeyCode(kVK_ANSI_V),
        keyDown: down
      )
    else {
      continue
    }
    event.flags = .maskCommand
    event.setIntegerValueField(.eventSourceUserData, value: MeantEvent.signature)
    event.post(tap: .cghidEventTap)
  }
}

private func postKey(
  _ key: CGKeyCode,
  pid: pid_t?,
  flags: CGEventFlags = [],
  hid: Bool = false
) {
  let source = CGEventSource(stateID: hid ? .hidSystemState : .privateState)
  func post(_ down: Bool) {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
      return
    }
    event.flags = flags
    event.setIntegerValueField(.eventSourceUserData, value: MeantEvent.signature)
    if hid {
      event.post(tap: .cghidEventTap)
    } else if let pid {
      event.postToPid(pid)
    } else {
      event.post(tap: .cghidEventTap)
    }
  }
  post(true)
  post(false)
}

private func readText(from element: AXUIElement) -> String {
  if let value = copyString(element, kAXValueAttribute), !value.isEmpty {
    return value
  }
  if let children = joinedChildren(element), !children.isEmpty {
    return children
  }
  let selectedRange = selectedUTF16Range(element)
  var current = copyElement(element, kAXParentAttribute)
  for _ in 0..<5 {
    guard let node = current else {
      break
    }
    if let value = copyString(node, kAXValueAttribute), !value.isEmpty {
      if isPlausibleParentText(value, selected: selectedRange) {
        return value
      }
    }
    current = copyElement(node, kAXParentAttribute)
  }
  return copyString(element, kAXSelectedTextAttribute) ?? ""
}

private func joinedChildren(_ element: AXUIElement) -> String? {
  var value: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
    let children = value as? [AXUIElement],
    !children.isEmpty
  else {
    return nil
  }
  var parts: [String] = []
  parts.reserveCapacity(min(children.count, 40))
  for child in children.prefix(40) {
    if let text = copyString(child, kAXValueAttribute), !text.isEmpty {
      parts.append(text)
    } else {
      parts.append("\u{FFFC}")
    }
  }
  let joined = parts.joined()
  return joined.contains(where: { $0 != "\u{FFFC}" }) ? joined : nil
}

private func isPlausibleParentText(_ value: String, selected: Range<Int>?) -> Bool {
  let length = (value as NSString).length
  guard let selected else {
    return length > 0 && length < 400
  }
  guard selected.upperBound <= length else {
    return false
  }
  return length - selected.upperBound <= 2
}

private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
    return nil
  }
  return (value as! AXUIElement)
}

private func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
    return nil
  }
  return value as? String
}

private func role(of element: AXUIElement) -> String? {
  copyString(element, kAXRoleAttribute)
}

private func selectedUTF16Range(_ element: AXUIElement) -> Range<Int>? {
  var value: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
      == .success,
    let axValue = value,
    CFGetTypeID(axValue) == AXValueGetTypeID()
  else {
    return nil
  }
  var range = CFRange()
  guard AXValueGetValue(axValue as! AXValue, .cfRange, &range), range.location >= 0 else {
    return nil
  }
  return range.location..<(range.location + max(range.length, 0))
}

private func utf16Cursor(in text: String) -> Range<Int> {
  let end = text.utf16.count
  return end..<end
}

private func setSelectedRange(_ element: AXUIElement, _ range: Range<Int>) -> Bool {
  var cfRange = CFRange(location: range.lowerBound, length: range.count)
  guard let value = AXValueCreate(.cfRange, &cfRange) else {
    return false
  }
  return AXUIElementSetAttributeValue(
    element,
    kAXSelectedTextRangeAttribute as CFString,
    value
  ) == .success
}

private func bounds(_ element: AXUIElement, utf16 range: Range<Int>) -> CGRect? {
  var attempts = [CFRange(location: range.lowerBound, length: max(range.count, 1))]
  if range.lowerBound > 0 {
    attempts.append(CFRange(location: range.lowerBound - 1, length: 1))
  }
  for attempt in attempts {
    var cfRange = attempt
    guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
      continue
    }
    var value: CFTypeRef?
    let result = AXUIElementCopyParameterizedAttributeValue(
      element,
      kAXBoundsForRangeParameterizedAttribute as CFString,
      rangeValue,
      &value
    )
    guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
      continue
    }
    var rect = CGRect.zero
    guard AXValueGetValue(axValue as! AXValue, .cgRect, &rect), !rect.isNull, rect.height > 0 else {
      continue
    }
    return cocoaRect(fromAX: rect)
  }
  return nil
}

private func fieldFrame(_ element: AXUIElement) -> CGRect? {
  var origin = CGPoint.zero
  var size = CGSize.zero
  var position: CFTypeRef?
  var sizeValue: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
    let positionAX = position,
    AXValueGetValue(positionAX as! AXValue, .cgPoint, &origin),
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
    let sizeAX = sizeValue,
    AXValueGetValue(sizeAX as! AXValue, .cgSize, &size),
    size.width > 0,
    size.height > 0
  else {
    return nil
  }
  return cocoaRect(fromAX: CGRect(origin: origin, size: size))
}

private func cocoaRect(fromAX rect: CGRect) -> CGRect {
  let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
  return HUDPlacement.cocoaRect(fromAX: rect, primaryMaxY: primary?.frame.maxY ?? 0)
}
