import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("Uso: make-icon.swift <immagine sorgente> <cartella .iconset>\n".utf8))
    exit(1)
}
let sourceURL = URL(fileURLWithPath: arguments[1])
let iconsetURL = URL(fileURLWithPath: arguments[2])

guard let artwork = NSImage(contentsOf: sourceURL), let artworkRepresentation = artwork.representations.first else {
    FileHandle.standardError.write(Data("Immagine non leggibile: \(sourceURL.path)\n".utf8))
    exit(1)
}
artwork.size = NSSize(width: artworkRepresentation.pixelsWide, height: artworkRepresentation.pixelsHigh)

func opaqueBounds(of image: NSImage) -> NSRect {
    let fullBounds = NSRect(origin: .zero, size: image.size)
    let width = Int(image.size.width)
    let height = Int(image.size.height)
    guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let context = CGContext(
              data: nil,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: width * 4,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return fullBounds
    }
    context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data else {
        return fullBounds
    }
    let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    let alphaThreshold: UInt8 = 8
    var minimumColumn = width
    var maximumColumn = -1
    var minimumRow = height
    var maximumRow = -1
    for row in 0..<height {
        for column in 0..<width where bytes[(row * width + column) * 4 + 3] > alphaThreshold {
            minimumColumn = min(minimumColumn, column)
            maximumColumn = max(maximumColumn, column)
            minimumRow = min(minimumRow, row)
            maximumRow = max(maximumRow, row)
        }
    }
    guard maximumColumn >= minimumColumn, maximumRow >= minimumRow else {
        return fullBounds
    }
    return NSRect(
        x: minimumColumn,
        y: height - 1 - maximumRow,
        width: maximumColumn - minimumColumn + 1,
        height: maximumRow - minimumRow + 1
    )
}

let artworkBounds = opaqueBounds(of: artwork)

func renderIcon(pixelSize: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        return nil
    }
    let scale = CGFloat(pixelSize) / 1024
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let plateRectangle = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let plate = NSBezierPath(roundedRect: plateRectangle, xRadius: 185 * scale, yRadius: 185 * scale)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 12 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -6 * scale)
    shadow.set()
    NSColor.white.setFill()
    plate.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(
        starting: NSColor(red: 1.0, green: 0.99, blue: 0.97, alpha: 1),
        ending: NSColor(red: 0.96, green: 0.91, blue: 0.84, alpha: 1)
    )
    gradient?.draw(in: plate, angle: -90)

    let artworkBoxSide = 680 * scale
    let fitScale = min(artworkBoxSide / artworkBounds.width, artworkBoxSide / artworkBounds.height)
    let drawnSize = NSSize(width: artworkBounds.width * fitScale, height: artworkBounds.height * fitScale)
    let drawnRectangle = NSRect(
        x: plateRectangle.midX - drawnSize.width / 2,
        y: plateRectangle.midY - drawnSize.height / 2,
        width: drawnSize.width,
        height: drawnSize.height
    )
    plate.addClip()
    artwork.draw(in: drawnRectangle, from: artworkBounds, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
for pointSize in [16, 32, 128, 256, 512] {
    for scaleFactor in [1, 2] {
        let suffix = scaleFactor == 2 ? "@2x" : ""
        let fileURL = iconsetURL.appending(path: "icon_\(pointSize)x\(pointSize)\(suffix).png")
        guard let data = renderIcon(pixelSize: pointSize * scaleFactor) else {
            FileHandle.standardError.write(Data("Impossibile disegnare l'icona a \(pointSize) punti\n".utf8))
            exit(1)
        }
        try data.write(to: fileURL)
    }
}
