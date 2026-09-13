// Redacts screenshots before they go into the repository.
//
//   swift scripts/redact-screenshot.swift in.png out.png [options]
//
// Coordinates are image pixels with the origin at the top-left corner.
//   --blur x,y,w,h     pixelate and blur a rectangle (repeatable)
//   --cut y0-y1        remove a horizontal band, e.g. a whole list row (repeatable)
//   --menubar h,keep   blur the top h pixels except the first `keep` pixels on the left
//
// Blurs are applied first, then cuts, so all coordinates refer to the original image.
import AppKit
import CoreImage

struct Options {
    var input = ""
    var output = ""
    var blurs: [CGRect] = []
    var cuts: [ClosedRange<Int>] = []
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func numbers(_ text: String, separator: Character) -> [Int] {
    text.split(separator: separator).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
}

var options = Options()
var arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else { fail("usage: redact-screenshot.swift in.png out.png [--blur x,y,w,h] [--cut y0-y1] [--menubar h,keep]") }
options.input = arguments.removeFirst()
options.output = arguments.removeFirst()

var menubar: (height: Int, keep: Int)?
while !arguments.isEmpty {
    let flag = arguments.removeFirst()
    guard let value = arguments.first else { fail("\(flag) needs a value") }
    arguments.removeFirst()
    switch flag {
    case "--blur":
        let v = numbers(value, separator: ",")
        guard v.count == 4 else { fail("--blur expects x,y,w,h") }
        options.blurs.append(CGRect(x: v[0], y: v[1], width: v[2], height: v[3]))
    case "--cut":
        let v = numbers(value, separator: "-")
        guard v.count == 2, v[0] < v[1] else { fail("--cut expects y0-y1") }
        options.cuts.append(v[0]...v[1] - 1)
    case "--menubar":
        let v = numbers(value, separator: ",")
        guard v.count == 2 else { fail("--menubar expects height,keep") }
        menubar = (v[0], v[1])
    default:
        fail("unknown option \(flag)")
    }
}

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: options.input) as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(options.input)") }
let width = original.width
let height = original.height
if let menubar {
    options.blurs.append(CGRect(x: menubar.keep, y: 0, width: width - menubar.keep, height: menubar.height))
}

// Blur: pixelate, then soften, so the content can't be reconstructed.
let context = CIContext()
var image = CIImage(cgImage: original)
for rect in options.blurs {
    let flipped = CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height)
    let redacted = image.cropped(to: flipped).clampedToExtent()
        .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: 10, kCIInputCenterKey: CIVector(x: flipped.minX, y: flipped.minY)])
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 6])
        .cropped(to: flipped)
    image = redacted.composited(over: image)
}
guard let blurred = context.createCGImage(image, from: CGRect(x: 0, y: 0, width: width, height: height)) else { fail("render failed") }

// Cut bands: copy the rows we keep, top to bottom.
let removed = Set(options.cuts.flatMap { Array($0) }.filter { $0 >= 0 && $0 < height })
let keptRows = (0..<height).filter { !removed.contains($0) }
guard let output = CGContext(
    data: nil, width: width, height: keptRows.count, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fail("cannot create output context") }

var start = 0
var destinationTop = 0
while start < keptRows.count {
    var end = start
    while end + 1 < keptRows.count && keptRows[end + 1] == keptRows[end] + 1 { end += 1 }
    let sourceTop = keptRows[start]
    let bandHeight = end - start + 1
    if let band = blurred.cropping(to: CGRect(x: 0, y: sourceTop, width: width, height: bandHeight)) {
        // CGContext's origin is bottom-left.
        let y = keptRows.count - destinationTop - bandHeight
        output.draw(band, in: CGRect(x: 0, y: y, width: width, height: bandHeight))
    }
    destinationTop += bandHeight
    start = end + 1
}

guard let result = output.makeImage(),
      let data = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) else { fail("encode failed") }
do {
    try data.write(to: URL(fileURLWithPath: options.output))
    print("✓ \(options.output) (\(width)×\(keptRows.count))")
} catch {
    fail("cannot write \(options.output): \(error.localizedDescription)")
}
