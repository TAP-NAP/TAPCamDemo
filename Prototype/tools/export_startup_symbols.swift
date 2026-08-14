import AppKit
import Foundation

let symbols: [(asset: String, systemName: String)] = [
    ("viewfinder-settings", "gearshape"),
    ("viewfinder-flash-off", "bolt.slash"),
    ("viewfinder-live-photo", "livephoto"),
    ("viewfinder-switch-camera", "arrow.triangle.2.circlepath.camera"),
    ("viewfinder-library", "photo.on.rectangle"),
    ("navigation-back", "chevron.left")
]

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

let canvasSize = NSSize(width: 96, height: 96)
let configuration = NSImage.SymbolConfiguration(pointSize: 38, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))

for symbol in symbols {
    guard let source = NSImage(
        systemSymbolName: symbol.systemName,
        accessibilityDescription: nil
    )?.withSymbolConfiguration(configuration) else {
        fputs("Missing SF Symbol: \(symbol.systemName)\n", stderr)
        exit(1)
    }

    let output = NSImage(size: canvasSize)
    output.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let sourceSize = source.size
    let scale = min(58 / sourceSize.width, 58 / sourceSize.height)
    let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let drawRect = NSRect(
        x: (canvasSize.width - drawSize.width) / 2,
        y: (canvasSize.height - drawSize.height) / 2,
        width: drawSize.width,
        height: drawSize.height
    )
    source.draw(in: drawRect)
    output.unlockFocus()

    guard let tiff = output.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Unable to render SF Symbol: \(symbol.systemName)\n", stderr)
        exit(1)
    }

    try png.write(to: outputDirectory.appendingPathComponent("\(symbol.asset).png"))
}
