// 알람 시계가 종을 울리며 좌우로 크게 흔들리는 2D 일러스트 루프 영상 생성기 (전체 화면 배경용)
// usage: swift make_shaking_clock.swift <output.mp4> [previewDir]
// 유틸·인코딩부는 make_cat_push.swift와 같은 구조(Tools는 앱 타깃 밖이라 모듈 공유 불가, 복사해 씀).
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: <output.mp4> [previewDir]"); exit(1) }
let outURL = URL(fileURLWithPath: args[1])
let previewDir = args.count > 2 ? URL(fileURLWithPath: args[2]) : nil

// MARK: - 설정
let W = 1080.0, H = 1920.0
let fps: Int32 = 30
let duration = 7.0
let frameCount = Int(Double(fps) * duration)

let pivot = CGPoint(x: 540, y: 1590)     // 시계 발 바닥 중앙(여기를 축으로 흔들림)
let clockC = CGPoint(x: 540, y: 1230)    // 시계 중심
let bodyR = 290.0, faceR = 245.0
let swingDeg = 16.0                      // 좌우 최대 기울기
let swingCycles = 21.0                   // 7초 동안 21번 왕복 = 3Hz (정수여야 루프가 이어짐)
let hammerCycles = 42.0                  // 망치(종 사이)는 2배 빠르게

// MARK: - 유틸
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func hex(_ v: UInt32, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255, a])!
}
func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, v)) }
func smooth(_ t: Double) -> Double { let c = clamp(t); return c * c * (3 - 2 * c) }

func ellipse(_ ctx: CGContext, _ c: CGPoint, _ rx: Double, _ ry: Double, _ color: CGColor, rot: Double = 0) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: rot)
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
    ctx.restoreGState()
}
func radial(_ ctx: CGContext, _ c: CGPoint, _ r: Double, _ inner: CGColor, _ outer: CGColor) {
    let g = CGGradient(colorsSpace: cs, colors: [inner, outer] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}
func line(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, _ w: Double, _ color: CGColor) {
    ctx.setStrokeColor(color); ctx.setLineWidth(w); ctx.setLineCap(.round)
    ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
}

// MARK: - 장면 상태
/// 흔들림 세기: 0에서 시작해 부드럽게 커졌다가 끝에서 다시 0으로 (루프 이음새에서 정지 상태)
func envelope(_ t: Double) -> Double { smooth(t / 1.2) * (1 - smooth((t - 5.8) / 1.0)) }
func swing(_ t: Double) -> Double { swingDeg * .pi / 180 * envelope(t) * sin(2 * .pi * swingCycles * t / duration) }

// MARK: - 그리기
let coral = hex(0xFF5A5F), coralDark = hex(0xE8454A), cream = hex(0xFFF8F0), ink = hex(0x1A1A1A)

func drawBackground(_ ctx: CGContext, t: Double) {
    let g = CGGradient(colorsSpace: cs, colors: [hex(0x2FB585), hex(0x7FDDB8), hex(0xDFF7EC)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])
    var s: UInt64 = 23
    func r() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    for _ in 0..<10 {   // 떠다니는 보케 (정수 주기로 루프)
        let bx = r() * W, by = r() * H * 0.75, br = 30 + r() * 70, k = Double(1 + Int(r() * 2)), ph = r() * 2 * .pi
        let c = CGPoint(x: bx + 22 * sin(2 * .pi * k * t / duration + ph), y: by + 16 * cos(2 * .pi * k * t / duration + ph))
        radial(ctx, c, br, hex(0xFFFFFF, 0.22), hex(0xFFFFFF, 0))
    }
    ctx.setFillColor(hex(0xBDEBD6)); ctx.fill(CGRect(x: 0, y: pivot.y + 10, width: W, height: H - pivot.y))   // 바닥
}

func drawShadow(_ ctx: CGContext, t: Double) {
    let a = swing(t)
    let dx = -sin(a) * 90       // 시계가 기울면 그림자는 반대로 살짝 밀림
    ellipse(ctx, CGPoint(x: pivot.x + dx, y: pivot.y + 26), 270 - abs(sin(a)) * 40, 40, hex(0x000000, 0.16))
}

func drawBell(_ ctx: CGContext, side: Double, t: Double) {
    let e = envelope(t)
    let center = CGPoint(x: clockC.x + side * 188, y: clockC.y - 228)
    let tilt = side * 40 * .pi / 180
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y); ctx.rotate(by: tilt)
    // 돔
    ctx.setFillColor(coralDark)
    ctx.addArc(center: .zero, radius: 128, startAngle: .pi, endAngle: 0, clockwise: false)
    ctx.closePath(); ctx.fillPath()
    ctx.setFillColor(hex(0xFFFFFF, 0.18))
    ctx.fillEllipse(in: CGRect(x: -80, y: -105, width: 54, height: 28))
    ctx.restoreGState()
    // 소리 호(작은 진동선): 바깥쪽으로 3겹, 밝기는 천천히 맥동(번쩍임 없음)
    for i in 0..<3 {
        let pulse = 0.5 + 0.5 * sin(2 * .pi * swingCycles * t / duration * 2 - Double(i) * 0.9)
        let alpha = e * (0.35 + 0.35 * pulse) * (1 - Double(i) * 0.22)
        let rad = 165 + Double(i) * 42
        let mid = (side > 0 ? -.pi / 2 + 0.55 : -.pi / 2 - 0.55)
        ctx.setStrokeColor(hex(0xFFFFFF, alpha)); ctx.setLineWidth(14); ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: rad, startAngle: mid - 0.38, endAngle: mid + 0.38, clockwise: false)
        ctx.strokePath()
    }
}

func drawClock(_ ctx: CGContext, t: Double) {
    let e = envelope(t)
    let a = swing(t)
    ctx.saveGState()
    ctx.translateBy(x: pivot.x, y: pivot.y); ctx.rotate(by: a); ctx.translateBy(x: -pivot.x, y: -pivot.y)

    // 다리
    for s in [-1.0, 1.0] { line(ctx, CGPoint(x: clockC.x + s * 170, y: clockC.y + 250), CGPoint(x: clockC.x + s * 235, y: clockC.y + 360), 46, coralDark) }
    // 종 + 망치(종 사이를 빠르게 왕복)
    for s in [-1.0, 1.0] { drawBell(ctx, side: s, t: t) }
    let hx = 95 * e * sin(2 * .pi * hammerCycles * t / duration)
    line(ctx, CGPoint(x: clockC.x, y: clockC.y - 300), CGPoint(x: clockC.x + hx * 0.6, y: clockC.y - 395), 22, coralDark)
    ellipse(ctx, CGPoint(x: clockC.x + hx, y: clockC.y - 410), 34, 34, coralDark)
    // 본체
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 26, color: hex(0x000000, 0.22))
    ellipse(ctx, clockC, bodyR, bodyR, coral)
    ctx.restoreGState()
    ellipse(ctx, clockC, faceR, faceR, cream)
    // 눈금
    for i in 0..<12 {
        let ang = Double(i) * .pi / 6, big = i % 3 == 0
        let r1 = faceR - (big ? 62 : 46), r2 = faceR - 22
        line(ctx, CGPoint(x: clockC.x + sin(ang) * r1, y: clockC.y - cos(ang) * r1),
             CGPoint(x: clockC.x + sin(ang) * r2, y: clockC.y - cos(ang) * r2), big ? 20 : 11, ink)
    }
    // 바늘: 분침 6바퀴, 시침 반바퀴 (정수 회전이라 루프가 이어짐)
    let minute = 2 * .pi * 6 * t / duration, hour = minute / 12
    line(ctx, clockC, CGPoint(x: clockC.x + sin(hour) * 105, y: clockC.y - cos(hour) * 105), 26, ink)
    line(ctx, clockC, CGPoint(x: clockC.x + sin(minute) * 160, y: clockC.y - cos(minute) * 160), 18, ink)
    ellipse(ctx, clockC, 22, 22, coral)
    ctx.restoreGState()
}

func drawFrame(_ ctx: CGContext, t: Double) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)   // 좌상단 원점
    drawBackground(ctx, t: t)
    drawShadow(ctx, t: t)
    drawClock(ctx, t: t)
    ctx.restoreGState()
}

// MARK: - 인코딩
try? FileManager.default.removeItem(at: outURL)
let writer = try! AVAssetWriter(outputURL: outURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: Int(W), AVVideoHeightKey: Int(H),
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 8_000_000,
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
    kCVPixelBufferWidthKey as String: Int(W), kCVPixelBufferHeightKey as String: Int(H),
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let previewTimes: [Double] = [0.0, 0.6, 1.5, 2.9, 4.2, 6.2, 6.9]
let previewFrames = Set(previewTimes.map { Int($0 * Double(fps)) })
for i in 0..<frameCount {
    while !input.isReadyForMoreMediaData { usleep(2000) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    let buf = pb!
    CVPixelBufferLockBaseAddress(buf, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: Int(W), height: Int(H), bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    drawFrame(ctx, t: Double(i) / Double(fps))
    if let dir = previewDir, previewFrames.contains(i), let img = ctx.makeImage() {
        let u = dir.appendingPathComponent(String(format: "clock_%03d.png", i))
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
print("ok: \(outURL.path) (\(frameCount) frames, \(Int(W))x\(Int(H)))")
