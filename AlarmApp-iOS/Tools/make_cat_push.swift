// 고양이가 앞발로 폰을 책상 끝까지 밀어내는 2D 일러스트 루프 영상 생성기 (전체 화면 배경용)
// usage: swift make_cat_push.swift <output.mp4> [previewDir]
// 유틸·인코딩부는 make_puppy_crack.swift와 같은 구조(Tools는 앱 타깃 밖이라 모듈 공유 불가, 복사해 씀).
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

let deskTopY = 1330.0        // 책상 윗면 시작(뒤쪽 경계)
let deskEdgeY = 1500.0       // 책상 윗면 끝(앞쪽 경계)
let deskEndX = 860.0         // 책상 오른쪽 끝(이 너머로 폰이 삐져나감)
let phoneW = 340.0, phoneH = 120.0
let phoneStartX = 560.0      // 폰 중심 x 시작
let pushStep = 60.0          // 한 번 밀 때 이동량
let pushTimes: [Double] = [0.7, 1.5, 2.3, 3.1, 3.9]
let reachT = 0.18, shoveT = 0.25, retractT = 0.27
let teeterStart = 4.5        // 마지막 푸시 후 아슬아슬 구간
let phoneFadeOut = 6.3, phoneFadeIn = 6.6, phoneBack = 6.9   // 루프용 리셋(폰이 사라졌다 처음 자리에 나타남)

// MARK: - 유틸
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func hex(_ v: UInt32, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255, a])!
}
func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, v)) }
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func easeIn(_ t: Double) -> Double { t * t * t }
func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
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
func polygon(_ ctx: CGContext, _ pts: [CGPoint], _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.move(to: pts[0]); pts.dropFirst().forEach { ctx.addLine(to: $0) }
    ctx.closePath(); ctx.fillPath()
}
func line(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, _ w: Double, _ color: CGColor) {
    ctx.setStrokeColor(color); ctx.setLineWidth(w); ctx.setLineCap(.round)
    ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
}

// MARK: - 장면 상태
/// 폰 중심 x (푸시 때마다 pushStep씩 이동)
func phoneShift(_ t: Double) -> Double {
    var d = 0.0
    for tk in pushTimes { d += pushStep * smooth((t - tk - reachT) / shoveT) }
    return d
}
/// 아슬아슬 구간의 흔들림(감쇠 진동)
func wobble(_ t: Double) -> Double {
    let s = t - teeterStart
    guard s > 0 else { return 0 }
    return 4.5 * sin(2 * .pi * 2.6 * s) * exp(-1.1 * s) * 0.0174533
}
/// 책상 끝에 걸린 정도에 따른 기울기(rad, 오른쪽이 내려가는 방향이 +)
func phoneTilt(_ t: Double) -> Double {
    let cx = phoneStartX + phoneShift(t)
    return smooth((cx - 835) / 25) * 9 * 0.0174533 + wobble(t)
}
func phoneAlpha(_ t: Double) -> Double {
    if t < phoneFadeOut { return 1 }
    if t < phoneFadeIn { return 1 - smooth((t - phoneFadeOut) / 0.2) }   // 0.2초에 사라짐
    return smooth((t - phoneFadeIn) / (phoneBack - phoneFadeIn))
}
func phoneCenterX(_ t: Double) -> Double { t < phoneFadeIn ? phoneStartX + phoneShift(t) : phoneStartX }
func phoneTiltAt(_ t: Double) -> Double { t < phoneFadeIn ? phoneTilt(t) : 0 }

/// 앞발 끝 위치. 쉬는 위치 → 폰 왼쪽 끝 → 밀기 → 복귀
let pawRest = CGPoint(x: 400, y: 1440)
func pawTip(_ t: Double) -> CGPoint {
    let y = 1425.0
    for tk in pushTimes {
        let a = tk, b = tk + reachT, c = b + shoveT, d = c + retractT
        guard t >= a && t < d else { continue }
        let leftAt: (Double) -> Double = { phoneCenterX($0) - phoneW / 2 - 6 }
        if t < b { return CGPoint(x: lerp(pawRest.x, leftAt(tk), easeOut((t - a) / reachT)), y: lerp(pawRest.y, y, easeOut((t - a) / reachT))) }
        if t < c { return CGPoint(x: leftAt(t), y: y) }
        let u = easeIn((t - c) / retractT)
        return CGPoint(x: lerp(leftAt(c), pawRest.x, u), y: lerp(y, pawRest.y, u))
    }
    return pawRest
}
/// 아슬아슬 구간의 긴장도 (0→1→0): 눈이 커지고 동공이 좁아짐
func suspense(_ t: Double) -> Double { smooth((t - teeterStart) / 0.4) * (1 - smooth((t - 6.2) / 0.5)) }
func blink(_ t: Double) -> Double {   // 눈 깜빡임 (0=뜸, 1=감음)
    for bt in [2.05, 5.3] where t > bt && t < bt + 0.16 { return sin((t - bt) / 0.16 * .pi) }
    return 0
}

// MARK: - 그리기
let fur = hex(0x8F9BB3), furDark = hex(0x6F7C97), furLight = hex(0xE6EAF2), earIn = hex(0xFFB3BE), ink = hex(0x24202B)
let wood = hex(0xD9A066), woodLight = hex(0xE8B87F), woodDark = hex(0xA8703E)

func drawBackground(_ ctx: CGContext, t: Double) {
    let g = CGGradient(colorsSpace: cs, colors: [hex(0x4FA3E0), hex(0x8CCBF5), hex(0xD7EEFF)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])
    var s: UInt64 = 11
    func r() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    for _ in 0..<10 {   // 떠다니는 보케 (정수 주기로 루프)
        let bx = r() * W, by = r() * H * 0.75, br = 30 + r() * 70, k = Double(1 + Int(r() * 2)), ph = r() * 2 * .pi
        let c = CGPoint(x: bx + 22 * sin(2 * .pi * k * t / duration + ph), y: by + 16 * cos(2 * .pi * k * t / duration + ph))
        radial(ctx, c, br, hex(0xFFFFFF, 0.22), hex(0xFFFFFF, 0))
    }
}

func drawCat(_ ctx: CGContext, t: Double) {
    let bob = 5 * sin(2 * .pi * 7 * t / duration)
    let hx = 250.0, hy = 1130.0 + bob
    let sus = suspense(t), bl = blink(t)

    ellipse(ctx, CGPoint(x: 230, y: 1500 + bob * 0.5), 360, 280, fur)             // 몸통(책상 뒤)
    ellipse(ctx, CGPoint(x: 330, y: 1480 + bob * 0.5), 190, 200, furLight)         // 가슴

    let twitch = (t > 3.4 && t < 3.6) ? 0.12 * sin((t - 3.4) / 0.2 * .pi) : 0       // 귀 쫑긋
    for (sx, tw) in [(-1.0, 0.0), (1.0, twitch)] {
        let b = CGPoint(x: hx + sx * 100, y: hy - 70)
        let outer = [CGPoint(x: hx + sx * 175, y: hy - 10), CGPoint(x: hx + sx * 150 + tw * 90, y: hy - 235), CGPoint(x: hx + sx * 30, y: hy - 130)]
        polygon(ctx, outer, fur)
        let inner = [CGPoint(x: hx + sx * 150, y: hy - 40), CGPoint(x: hx + sx * 138 + tw * 70, y: hy - 175), CGPoint(x: hx + sx * 62, y: hy - 112)]
        polygon(ctx, inner, earIn)
        _ = b
    }
    ellipse(ctx, CGPoint(x: hx, y: hy), 205, 175, fur)                              // 머리
    ellipse(ctx, CGPoint(x: hx + 40, y: hy + 70), 120, 85, furLight)                // 주둥이
    for i in -1...1 { line(ctx, CGPoint(x: hx + Double(i) * 38, y: hy - 165), CGPoint(x: hx + Double(i) * 30, y: hy - 108), 14, furDark) }

    // 눈 (폰을 쳐다봄: 동공이 오른쪽 아래)
    for ex in [hx - 55, hx + 85] {
        let ey = hy - 18
        ellipse(ctx, CGPoint(x: ex, y: ey), 44, lerp(40, 54, sus), hex(0xFFF9E0))
        ellipse(ctx, CGPoint(x: ex + 16, y: ey + 8), lerp(15, 9, sus), lerp(32, 40, sus), ink)
        ellipse(ctx, CGPoint(x: ex + 21, y: ey - 4), 5, 5, hex(0xFFFFFF))
        // 게슴츠레한 눈꺼풀: 평소엔 위 35%를 덮고, 긴장하면 걷힘. 깜빡이면 전체를 덮음
        let lid = clamp(0.35 * (1 - sus) + bl)
        if lid > 0.01 {
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: ex - 46, y: ey - 56, width: 92, height: 112)); ctx.clip()
            ctx.setFillColor(fur)
            ctx.fill(CGRect(x: ex - 50, y: ey - 60, width: 100, height: 112 * lid + 4))
            ctx.restoreGState()
        }
    }
    polygon(ctx, [CGPoint(x: hx + 22, y: hy + 42), CGPoint(x: hx + 70, y: hy + 42), CGPoint(x: hx + 46, y: hy + 68)], hex(0xFF8FA0))   // 코
    ctx.setStrokeColor(ink); ctx.setLineWidth(5); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: hx + 46, y: hy + 68)); ctx.addLine(to: CGPoint(x: hx + 46, y: hy + 82))
    ctx.addQuadCurve(to: CGPoint(x: hx + 12, y: hy + 92), control: CGPoint(x: hx + 40, y: hy + 100))
    ctx.move(to: CGPoint(x: hx + 46, y: hy + 82))
    ctx.addQuadCurve(to: CGPoint(x: hx + 84, y: hy + 92), control: CGPoint(x: hx + 52, y: hy + 100))
    ctx.strokePath()
    for dy in [-8.0, 12.0, 32.0] {   // 수염
        line(ctx, CGPoint(x: hx + 120, y: hy + 70 + dy * 0.4), CGPoint(x: hx + 215, y: hy + 62 + dy), 4, hex(0xFFFFFF, 0.9))
        line(ctx, CGPoint(x: hx - 30, y: hy + 70 + dy * 0.4), CGPoint(x: hx - 125, y: hy + 62 + dy), 4, hex(0xFFFFFF, 0.9))
    }
}

func drawDesk(_ ctx: CGContext) {
    // 윗면
    let top = CGMutablePath()
    top.move(to: CGPoint(x: -50, y: deskTopY))
    top.addLine(to: CGPoint(x: deskEndX - 20, y: deskTopY))
    top.addLine(to: CGPoint(x: deskEndX + 40, y: deskEdgeY))
    top.addLine(to: CGPoint(x: -50, y: deskEdgeY))
    top.closeSubpath()
    let g = CGGradient(colorsSpace: cs, colors: [woodLight, wood] as CFArray, locations: [0, 1])!
    ctx.saveGState(); ctx.addPath(top); ctx.clip()
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: deskTopY), end: CGPoint(x: 0, y: deskEdgeY), options: [])
    ctx.restoreGState()
    // 앞면
    let front = CGMutablePath()
    front.move(to: CGPoint(x: -50, y: deskEdgeY))
    front.addLine(to: CGPoint(x: deskEndX + 40, y: deskEdgeY))
    front.addLine(to: CGPoint(x: deskEndX + 40, y: deskEdgeY + 90))
    front.addLine(to: CGPoint(x: -50, y: deskEdgeY + 90))
    front.closeSubpath()
    ctx.addPath(front); ctx.setFillColor(woodDark); ctx.fillPath()
    ctx.setFillColor(hex(0x000000, 0.12)); ctx.fill(CGRect(x: -50, y: deskEdgeY + 90, width: deskEndX + 90, height: 22))
}

func drawPhone(_ ctx: CGContext, t: Double) {
    let a = phoneAlpha(t)
    guard a > 0.01 else { return }
    let cx = phoneCenterX(t)
    ctx.saveGState()
    ctx.setAlpha(a)
    ctx.translateBy(x: deskEndX + 40, y: deskEdgeY)    // 회전 중심: 책상 앞쪽 모서리
    ctx.rotate(by: phoneTiltAt(t))
    let rect = CGRect(x: cx - (deskEndX + 40) - phoneW / 2, y: -phoneH - 4, width: phoneW, height: phoneH)
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 18, color: hex(0x000000, 0.3))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 24, cornerHeight: 24, transform: nil))
    ctx.setFillColor(hex(0x2B2F3A)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0)
    let screen = rect.insetBy(dx: 10, dy: 10)
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.setFillColor(hex(0x6EC1FF)); ctx.fillPath()
    // 화면 속 알람 아이콘(노란 원 + 바늘)
    let ic = CGPoint(x: screen.midX - 70, y: screen.midY)
    ellipse(ctx, ic, 30, 30, hex(0xFFC107))
    line(ctx, ic, CGPoint(x: ic.x, y: ic.y - 18), 6, hex(0x1A1A1A))
    line(ctx, ic, CGPoint(x: ic.x + 14, y: ic.y + 6), 6, hex(0x1A1A1A))
    for i in 0..<3 { line(ctx, CGPoint(x: screen.midX - 10, y: screen.midY - 22 + Double(i) * 22), CGPoint(x: screen.midX + 100 - Double(i) * 30, y: screen.midY - 22 + Double(i) * 22), 8, hex(0xFFFFFF, 0.85)) }
    ctx.restoreGState()
}

func drawPaw(_ ctx: CGContext, t: Double) {
    let tip = pawTip(t)
    let shoulder = CGPoint(x: 300, y: 1385)
    line(ctx, shoulder, CGPoint(x: tip.x - 30, y: tip.y), 120, fur)
    ellipse(ctx, tip, 66, 58, fur)
    ellipse(ctx, CGPoint(x: tip.x + 10, y: tip.y + 12), 40, 26, furLight)
    for dy in [-20.0, 0.0, 20.0] { line(ctx, CGPoint(x: tip.x + 42, y: tip.y + dy), CGPoint(x: tip.x + 62, y: tip.y + dy), 4, furDark) }
}

func drawFrame(_ ctx: CGContext, t: Double) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)   // 좌상단 원점
    drawBackground(ctx, t: t)
    drawCat(ctx, t: t)
    drawDesk(ctx)
    drawPhone(ctx, t: t)
    drawPaw(ctx, t: t)
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

let previewTimes: [Double] = [0.0, 1.0, 2.0, 3.5, 5.0, 6.0, 6.9]
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
        let u = dir.appendingPathComponent(String(format: "cat_%03d.png", i))
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
