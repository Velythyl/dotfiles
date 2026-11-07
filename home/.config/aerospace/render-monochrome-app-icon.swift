import AppKit

guard CommandLine.arguments.count == 4 || (CommandLine.arguments.count == 5 && CommandLine.arguments[4] == "--preserve-alpha") else {
    fputs("Usage: render-monochrome-app-icon <app-bundle-or-image> <active.png> <inactive.png> [--preserve-alpha]\n", stderr)
    exit(2)
}

let sourcePath = CommandLine.arguments[1]
let activeOutput = URL(fileURLWithPath: CommandLine.arguments[2])
let inactiveOutput = URL(fileURLWithPath: CommandLine.arguments[3])
let preserveSourceAlpha = CommandLine.arguments.count == 5
let size = 64

struct Pixel {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    func distance(to other: Pixel) -> CGFloat {
        let redDelta = red - other.red
        let greenDelta = green - other.green
        let blueDelta = blue - other.blue
        return sqrt(redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta)
    }
}

guard let source = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not allocate source bitmap\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let graphicsContext = NSGraphicsContext(bitmapImageRep: source) else {
    fputs("Could not create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = graphicsContext
graphicsContext.imageInterpolation = .high
let sourceURL = URL(fileURLWithPath: sourcePath)
let imageExtensions: Set<String> = ["svg", "png", "jpg", "jpeg", "gif", "tiff", "heic"]
let sourceImage: NSImage
if imageExtensions.contains(sourceURL.pathExtension.lowercased()) {
    guard let image = NSImage(contentsOfFile: sourcePath) else {
        fputs("Could not load icon image: \(sourcePath)\n", stderr)
        exit(1)
    }
    sourceImage = image
} else {
    sourceImage = NSWorkspace.shared.icon(forFile: sourcePath)
}
sourceImage.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: NSRect(origin: .zero, size: sourceImage.size),
    operation: .copy,
    fraction: 1.0
)
NSGraphicsContext.restoreGraphicsState()

func sourcePixel(x: Int, y: Int) -> Pixel {
    let color = source.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) ?? .clear
    return Pixel(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: color.alphaComponent)
}

var pixels = (0..<(size * size)).map { index in
    sourcePixel(x: index % size, y: index / size)
}

var boundaryIndices: [Int] = []
var backgroundSampleIndices: [Int] = []
for coordinate in 0..<size {
    boundaryIndices.append(coordinate)
    boundaryIndices.append((size - 1) * size + coordinate)
    boundaryIndices.append(coordinate * size)
    boundaryIndices.append(coordinate * size + size - 1)
}
for y in 0..<size {
    for x in 0..<size where x < 8 || y < 8 || x >= size - 8 || y >= size - 8 {
        backgroundSampleIndices.append(y * size + x)
    }
}
let opaqueBoundary = backgroundSampleIndices.map { pixels[$0] }.filter { $0.alpha > 0.15 }
let background: Pixel
if opaqueBoundary.isEmpty {
    background = Pixel(red: 0, green: 0, blue: 0, alpha: 0)
} else {
    var redTotal: CGFloat = 0
    var greenTotal: CGFloat = 0
    var blueTotal: CGFloat = 0
    for pixel in opaqueBoundary {
        redTotal += pixel.red
        greenTotal += pixel.green
        blueTotal += pixel.blue
    }
    let pixelCount = CGFloat(opaqueBoundary.count)
    background = Pixel(
        red: redTotal / pixelCount,
        green: greenTotal / pixelCount,
        blue: blueTotal / pixelCount,
        alpha: 1
    )
}

// Remove only background connected to the image boundary. This preserves a
// similarly colored interior logo while discarding a rounded app-icon plate.
var removed = Array(repeating: false, count: size * size)
var queue: [Int] = []
let backgroundThreshold: CGFloat = 0.22

func isNearWhiteBackground(_ pixel: Pixel) -> Bool {
    let maximum = max(pixel.red, max(pixel.green, pixel.blue))
    let minimum = min(pixel.red, min(pixel.green, pixel.blue))
    return minimum > 0.82 && (maximum - minimum) < 0.14
}

func isRemovableBackground(_ pixel: Pixel) -> Bool {
    pixel.alpha < 0.15 ||
        pixel.distance(to: background) < backgroundThreshold ||
        isNearWhiteBackground(pixel)
}

if !preserveSourceAlpha {
    for index in boundaryIndices where !removed[index] {
        let pixel = pixels[index]
        if isRemovableBackground(pixel) {
            removed[index] = true
            queue.append(index)
        }
    }

    var queueIndex = 0
    while queueIndex < queue.count {
        let index = queue[queueIndex]
        queueIndex += 1
        let x = index % size
        let y = index / size
        let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]

        for (neighborX, neighborY) in neighbors where neighborX >= 0 && neighborX < size && neighborY >= 0 && neighborY < size {
            let neighborIndex = neighborY * size + neighborX
            guard !removed[neighborIndex] else { continue }
            let pixel = pixels[neighborIndex]
            if isRemovableBackground(pixel) {
                removed[neighborIndex] = true
                queue.append(neighborIndex)
            }
        }
    }
}

var strengths = Array(repeating: CGFloat(0), count: size * size)
for y in 1..<(size - 1) {
    for x in 1..<(size - 1) {
        let index = y * size + x
        guard !removed[index] && pixels[index].alpha > 0.15 else { continue }
        if preserveSourceAlpha {
            strengths[index] = 1.0
            continue
        }
        var strongestEdge: CGFloat = 0
        for neighborY in (y - 1)...(y + 1) {
            for neighborX in (x - 1)...(x + 1) where neighborX != x || neighborY != y {
                let neighborIndex = neighborY * size + neighborX
                let neighbor = removed[neighborIndex] ? background : pixels[neighborIndex]
                strongestEdge = max(strongestEdge, pixels[index].distance(to: neighbor))
            }
        }
        // Retain enough interior fill to survive at 18px, while emphasizing the
        // boundary detail so logos do not turn into solid app-icon tiles.
        strengths[index] = max(0.32, min(1.0, strongestEdge * 3.2))
    }
}

func writeIcon(alphaMultiplier: CGFloat, to outputURL: URL) throws {
    guard let output = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "AeroSpaceIconRenderer", code: 1)
    }

    for y in 0..<size {
        for x in 0..<size {
            let index = y * size + x
            let alpha = pixels[index].alpha * strengths[index] * alphaMultiplier
            output.setColor(NSColor(deviceRed: 0.9216, green: 0.8588, blue: 0.6980, alpha: alpha), atX: x, y: y)
        }
    }

    guard let pngData = output.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AeroSpaceIconRenderer", code: 2)
    }
    try pngData.write(to: outputURL)
}

do {
    try writeIcon(alphaMultiplier: 1.0, to: activeOutput)
    try writeIcon(alphaMultiplier: 0.47, to: inactiveOutput)
} catch {
    fputs("Could not write monochrome app icon: \(error)\n", stderr)
    exit(1)
}
