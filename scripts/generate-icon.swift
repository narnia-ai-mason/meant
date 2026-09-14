#!/usr/bin/swift
import AppKit

let canvas = 1024
let size = NSSize(width: canvas, height: canvas)
let blue = NSColor(calibratedRed: 47 / 255, green: 124 / 255, blue: 246 / 255, alpha: 1)

guard let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: canvas,
  pixelsHigh: canvas,
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  fatalError("Unable to create bitmap")
}
rep.size = size

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
  fatalError("Unable to create graphics context")
}
NSGraphicsContext.current = context
context.cgContext.setShouldAntialias(true)
context.cgContext.setAllowsAntialiasing(true)

NSColor.white.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

func addArrow(_ path: NSBezierPath, y: CGFloat, pointingRight: Bool) {
  let left: CGFloat = 232
  let right: CGFloat = 792
  let head: CGFloat = 148
  let start = pointingRight ? CGPoint(x: left, y: y) : CGPoint(x: right, y: y)
  let tip = pointingRight ? CGPoint(x: right, y: y) : CGPoint(x: left, y: y)
  path.move(to: start)
  path.line(to: tip)
  let inward: CGFloat = pointingRight ? -head : head
  path.move(to: CGPoint(x: tip.x + inward, y: y + head))
  path.line(to: tip)
  path.line(to: CGPoint(x: tip.x + inward, y: y - head))
}

func arrowPath() -> NSBezierPath {
  let path = NSBezierPath()
  addArrow(path, y: 512 + 118, pointingRight: true)
  addArrow(path, y: 512 - 118, pointingRight: false)
  path.lineWidth = 68
  path.lineCapStyle = .round
  path.lineJoinStyle = .round
  return path
}

let path = arrowPath()
context.saveGraphicsState()
context.cgContext.setShadow(
  offset: CGSize(width: 0, height: -6),
  blur: 14,
  color: NSColor.black.withAlphaComponent(0.08).cgColor
)
blue.setStroke()
path.stroke()
context.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
  fatalError("Unable to encode PNG")
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: output)
print("\(output.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
