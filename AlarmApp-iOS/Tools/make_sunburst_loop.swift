// 햇살 버스트 루프 영상 생성기
// usage: swift make_sunburst_loop.swift <input.jpg> <output.mp4> [previewDir]
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: <input.jpg> <output.mp4> [previewDir]"); exit(1) }
let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let previewDir = args.count > 3 ? URL(fileURLWithPath: args[3]) : nil

let W = 1080, H = 1440
let fps: Int32 = 30
let seconds = 6
let frameCount = Int(fps) * seconds

guard let src = CGImageSourceCreateWithURL(inURL as CFURL, nil),
      let baseImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("image load failed") }

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let sun = CGPoint(x: 0.52 * Double(W), y: 0.53 * Double(H)) // top-left origin

// deterministic pseudo-random
var seed: UInt64 = 20261111
func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }

struct Sparkle { var x, y0, speed, size, twinkle, phase: Double }
let sparkles: [Sparkle] = (0..<34).map { _ in
    Sparkle(x: rnd(), y0: rnd(), speed: Double(1 + Int(rnd() * 2)), // integer cycles per loop → seamless
            size: 3 + rnd() * 7, twinkle: Double(1 + Int(rnd() * 3)), phase: rnd() * 2 * .pi)
}

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }

func radial(_ ctx: CGContext, center: CGPoint, radius: Double, inner: CGColor, outer: CGColor) {
    let g = CGGradient(colorsSpace: cs, colors: [inner, outer] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func drawFrame(_ ctx: CGContext, t: Double) {
    let phase = 2 * Double.pi * t
    // flip to top-left origin
    ctx.saveGState()
    ctx.translateBy(x: 0, y: Double(H)); ctx.scaleBy(x: 1, y: -1)

    // 1) base image: breathing zoom + gentle drift (anchored at sun)
    let scale = 1.05 + 0.025 * sin(phase)
    let dy = 8 * sin(phase)
    let dw = Double(W) * scale, dh = Double(H) * scale
    let rect = CGRect(x: sun.x - dw * (sun.x / Double(W)), y: sun.y - dh * (sun.y / Double(H)) + dy, width: dw, height: dh)
    ctx.saveGState()
    ctx.translateBy(x: 0, y: rect.midY * 2); ctx.scaleBy(x: 1, y: -1) // draw image upright
    ctx.draw(baseImage, in: rect)
    ctx.restoreGState()

    // 2) rotating rays (12 rays, rotate one ray-period per loop → seamless)
    let rays = 12
    let rot = t * (2 * Double.pi / Double(rays))
    let len = Double(H)
    let path = CGMutablePath()
    for i in 0..<rays {
        let a = rot + Double(i) * 2 * .pi / Double(rays)
        let half = 0.075
        path.move(to: sun)
        path.addLine(to: CGPoint(x: sun.x + len * cos(a - half), y: sun.y + len * sin(a - half)))
        path.addLine(to: CGPoint(x: sun.x + len * cos(a + half), y: sun.y + len * sin(a + half)))
        path.closeSubpath()
    }
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.setBlendMode(.screen)
    let rayAlpha = 0.22 + 0.06 * sin(phase * 2)
    radial(ctx, center: sun, radius: 0.85 * Double(H), inner: color(1, 0.97, 0.85, rayAlpha), outer: color(1, 0.9, 0.7, 0))
    ctx.restoreGState()

    // 3) sun glow pulse
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    let r = 0.30 * Double(W) * (1 + 0.08 * sin(phase * 2))
    radial(ctx, center: sun, radius: r, inner: color(1, 0.98, 0.88, 0.55), outer: color(1, 0.85, 0.5, 0))
    ctx.restoreGState()

    // 4) rising sparkles
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    for s in sparkles {
        var y = s.y0 - s.speed * t
        y -= floor(y)
        let px = s.x * Double(W) + 10 * sin(phase * s.twinkle + s.phase)
        let py = y * Double(H)
        let edge = min(1, min(y, 1 - y) * 8) // fade near top/bottom wrap
        let a = (0.45 + 0.45 * sin(phase * s.twinkle + s.phase)) * edge
        radial(ctx, center: CGPoint(x: px, y: py), radius: s.size * 2.2, inner: color(1, 1, 0.95, a), outer: color(1, 0.95, 0.8, 0))
    }
    ctx.restoreGState()

    ctx.restoreGState()
}

func makeContext(_ data: UnsafeMutableRawPointer?, bytesPerRow: Int) -> CGContext {
    CGContext(data: data, width: W, height: H, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}

// --- writer
try? FileManager.default.removeItem(at: outURL)
let writer = try! AVAssetWriter(outputURL: outURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: W, AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 6_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey: Int(fps),
    ],
    AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let previewFrames: Set<Int> = [0, frameCount / 4, frameCount / 2, frameCount * 3 / 4]
for i in 0..<frameCount {
    while !input.isReadyForMoreMediaData { usleep(2000) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    let buf = pb!
    CVPixelBufferLockBaseAddress(buf, [])
    let ctx = makeContext(CVPixelBufferGetBaseAddress(buf), bytesPerRow: CVPixelBufferGetBytesPerRow(buf))
    let t = Double(i) / Double(frameCount)
    drawFrame(ctx, t: t)
    if let dir = previewDir, previewFrames.contains(i), let img = ctx.makeImage() {
        let u = dir.appendingPathComponent(String(format: "frame_%03d.png", i))
        let dst = CGImageDestinationCreateWithURL(u as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
    }
    CVPixelBufferUnlockBaseAddress(buf, [])
    adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
}
input.markAsFinished()
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
if writer.status != .completed { print("failed: \(String(describing: writer.error))"); exit(1) }
print("ok: \(outURL.path) (\(frameCount) frames)")
