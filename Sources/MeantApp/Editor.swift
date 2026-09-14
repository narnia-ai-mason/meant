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

  static func substring(_ text: String, _ utf16: Range<Int>) -> String? {
    let ns = text as NSString
    guard utf16.lowerBound >= 0, utf16.upperBound <= ns.length else {
      return nil
    }
    return ns.substring(with: NSRange(location: utf16.lowerBound, length: utf16.count))
  }

  static func replace(in snapshot: Snapshot, utf16: Range<Int>, with replacement: String) -> Bool {
    let element = snapshot.element
    var before = readText(from: element)
    guard var range = clamped(utf16, in: before), var original = substring(before, range) else {
      return false
    }
    if original.contains(where: isHangulLetter) {
      let committed = commitHangul(in: element, original: original, range: range)
      before = readText(from: element)
      if let committed, let text = substring(before, committed) {
        range = committed
        original = text
      } else if let found = locate(original, preferring: range, in: before) {
        range = found
      }
    }
    guard selectExactly(element, range: range, expected: original) else {
      return false
    }
    var pid: pid_t = 0
    let target = AXUIElementGetPid(element, &pid) == .success ? pid : nil
    postKey(CGKeyCode(kVK_Delete), pid: target)
    settle(0.08)
    let inserted = replacement + trailingSpaces(original)
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
  if let found = locate(original, preferring: range, in: readText(from: element)) {
    return found
  }
  InputSource.select(.koreanToEnglish)
  settle()
  return locate(original, preferring: range, in: readText(from: element))
}

@MainActor
private func locate(_ original: String, preferring range: Range<Int>, in text: String) -> Range<Int>? {
  if Editor.substring(text, range) == original {
    return range
  }
  let ns = text as NSString
  let needle = original as NSString
  guard needle.length > 0, ns.length >= needle.length else {
    return nil
  }
  var search = NSRange(location: 0, length: ns.length)
  var best: NSRange?
  while true {
    let found = ns.range(of: original, options: [], range: search)
    guard found.location != NSNotFound else {
      break
    }
    if found.location == range.lowerBound {
      return found.location..<(found.location + found.length)
    }
    if best == nil || abs(found.location - range.lowerBound) < abs(best!.location - range.lowerBound) {
      best = found
    }
    let next = found.location + max(found.length, 1)
    guard next < ns.length else {
      break
    }
    search = NSRange(location: next, length: ns.length - next)
  }
  guard let best else {
    return nil
  }
  return best.location..<(best.location + best.length)
}

private func isHangulLetter(_ character: Character) -> Bool {
  character.unicodeScalars.contains { scalar in
    (0x1100...0x11FF).contains(scalar.value)
      || (0x3130...0x318F).contains(scalar.value)
      || (0xAC00...0xD7A3).contains(scalar.value)
  }
}

private func selectExactly(_ element: AXUIElement, range: Range<Int>, expected: String) -> Bool {
  guard setSelectedRange(element, range) else {
    return false
  }
  settle()
  guard selectedUTF16Range(element) == range else {
    return false
  }
  if let selected = copyString(element, kAXSelectedTextAttribute), selected != expected {
    return false
  }
  return true
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
  return [
    needle,
    needle.precomposedStringWithCanonicalMapping,
    needle.decomposedStringWithCanonicalMapping,
  ].contains { ns.range(of: $0).location != NSNotFound }
}

private func paste(_ text: String) -> Bool {
  let pasteboard = NSPasteboard.general
  let previous = pasteboard.string(forType: .string)
  pasteboard.clearContents()
  pasteboard.setString(text, forType: .string)
  postCommandV()
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
  flags: CGEventFlags = []
) {
  let source = CGEventSource(stateID: .privateState)
  func post(_ down: Bool) {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
      return
    }
    event.flags = flags
    event.setIntegerValueField(.eventSourceUserData, value: MeantEvent.signature)
    if let pid {
      event.postToPid(pid)
    } else {
      event.post(tap: .cghidEventTap)
    }
  }
  post(true)
  post(false)
}

private func readText(from element: AXUIElement) -> String {
  if let value = copyString(element, kAXValueAttribute) {
    return value
  }
  let selectedRange = selectedUTF16Range(element)
  var current = copyElement(element, kAXParentAttribute)
  for _ in 0..<5 {
    guard let node = current else {
      break
    }
    if let value = copyString(node, kAXValueAttribute), !value.isEmpty {
      if let selectedRange, selectedRange.upperBound <= (value as NSString).length {
        return value
      }
      if selectedRange == nil {
        return value
      }
    }
    current = copyElement(node, kAXParentAttribute)
  }
  return copyString(element, kAXSelectedTextAttribute) ?? ""
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
