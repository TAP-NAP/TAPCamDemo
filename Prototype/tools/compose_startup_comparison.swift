import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("usage: compose_startup_comparison.swift <approved.png> <candidate.png> <output.png>\n", stderr)
    exit(2)
}

let approvedURL = URL(fileURLWithPath: CommandLine.arguments[1])
let candidateURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

guard let approved = NSImage(contentsOf: approvedURL),
      let candidate = NSImage(contentsOf: candidateURL) else {
    fputs("unable to load comparison inputs\n", stderr)
    exit(1)
}

let inset: CGFloat = 24
let gap: CGFloat = 24
let labelHeight: CGFloat = 46
let imageSize = NSSize(width: 393, height: 852)
let canvasSize = NSSize(
    width: inset * 2 + imageSize.width * 2 + gap,
    height: inset * 2 + labelHeight + imageSize.height
)

let output = NSImage(size: canvasSize)
output.lockFocus()
NSColor(calibratedWhite: 0.045, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1),
    .paragraphStyle: paragraph
]

let approvedRect = NSRect(x: inset, y: inset, width: imageSize.width, height: imageSize.height)
let candidateRect = NSRect(x: inset + imageSize.width + gap, y: inset, width: imageSize.width, height: imageSize.height)
let labelY = inset + imageSize.height + 12

("Approved TAP-0008-r2 source" as NSString).draw(
    in: NSRect(x: approvedRect.minX, y: labelY, width: imageSize.width, height: 24),
    withAttributes: attributes
)
("TAP-0087-r1 candidate" as NSString).draw(
    in: NSRect(x: candidateRect.minX, y: labelY, width: imageSize.width, height: 24),
    withAttributes: attributes
)

approved.draw(in: approvedRect, from: .zero, operation: .sourceOver, fraction: 1)
candidate.draw(in: candidateRect, from: .zero, operation: .sourceOver, fraction: 1)
output.unlockFocus()

guard let tiff = output.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("unable to encode comparison output\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
