#!/usr/bin/env swift
import AppKit

let output =
  CommandLine.arguments.dropFirst().first
  ?? "EngApp/Assets.xcassets/AppIcon.appiconset/EngIcon.png"
let size = NSSize(width: 1_024, height: 1_024)
let image = NSImage(size: size)

image.lockFocus()

let bounds = NSRect(origin: .zero, size: size)
let background = NSBezierPath(rect: bounds)
let gradient = NSGradient(colors: [
  NSColor(calibratedRed: 0.025, green: 0.045, blue: 0.11, alpha: 1),
  NSColor(calibratedRed: 0.22, green: 0.10, blue: 0.43, alpha: 1),
])!
gradient.draw(in: background, angle: -48)

for (diameter, alpha, lineWidth) in [
  (720.0, 0.10, 5.0),
  (570.0, 0.16, 8.0),
  (430.0, 0.22, 11.0),
] {
  let circle = NSBezierPath(
    ovalIn: NSRect(
      x: (1_024 - diameter) / 2,
      y: (1_024 - diameter) / 2,
      width: diameter,
      height: diameter
    ))
  circle.lineWidth = lineWidth
  NSColor(calibratedRed: 0.35, green: 0.84, blue: 1.0, alpha: alpha).setStroke()
  circle.stroke()
}

let glow = NSShadow()
glow.shadowColor = NSColor(calibratedRed: 0.38, green: 0.83, blue: 1, alpha: 0.58)
glow.shadowBlurRadius = 42
glow.shadowOffset = .zero
NSGraphicsContext.current?.saveGraphicsState()
glow.set()

let mark = NSBezierPath()
mark.move(to: NSPoint(x: 335, y: 690))
mark.line(to: NSPoint(x: 535, y: 512))
mark.line(to: NSPoint(x: 335, y: 334))
mark.lineWidth = 58
mark.lineCapStyle = .round
mark.lineJoinStyle = .round
NSColor.white.setStroke()
mark.stroke()

let cursor = NSBezierPath()
cursor.move(to: NSPoint(x: 555, y: 344))
cursor.line(to: NSPoint(x: 722, y: 344))
cursor.lineWidth = 58
cursor.lineCapStyle = .round
NSColor(calibratedRed: 0.43, green: 0.93, blue: 0.84, alpha: 1).setStroke()
cursor.stroke()
NSGraphicsContext.current?.restoreGraphicsState()
image.unlockFocus()

guard
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1_024,
  pixelsHigh: 1_024,
  bitsPerSample: 8,
  samplesPerPixel: 3,
  hasAlpha: false,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )
else {
  fatalError("Could not allocate app icon bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: bounds)
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
  fatalError("Could not encode app icon PNG")
}
try data.write(to: URL(fileURLWithPath: output), options: .atomic)
print("Generated \(output)")
