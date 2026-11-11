// 강아지가 폰 화면을 두드려 깨뜨리는 2D 일러스트 루프 영상 생성기 (전체 화면 배경용)
// usage: swift make_puppy_crack.swift <output.mp4> [previewDir]
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
let crackTopLimit = 0.33 * H      // 이 위(날짜·시각 영역)로는 금이 가지 않음
let crackBottomLimit = 0.90 * H   // CTA 버튼 영역 아래로도 제한
let fadeStart = 6.6               // 이 시점부터 금이 사라지며 루프 처음으로 복귀

let drumStart = 0.45              // 마구 두드리기 시작
let drumEnd = 6.2                 // 마구 두드리기 끝
let pressHold = 0.045             // 발이 유리에 붙어 있는 시간

struct Tap { let time: Double; let point: CGPoint; let left: Bool; let major: Bool }

// MARK: - 유틸
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func hex(_ v: UInt32, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255, a])!
}
func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, v)) }
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func lerpP(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint { CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t)) }
func easeIn(_ t: Double) -> Double { t * t * t }
func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

var seed: UInt64 = 20261111
func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
func rnd(_ a: Double, _ b: Double) -> Double { a + (b - a) * rnd() }

// 양발 번갈아 빠르게 두드리기 (초당 약 7~8회). 5번에 1번은 큰 금.
let taps: [Tap] = {
    // 같은 자리를 반복해서 두드림: 발마다 4곳의 단골 지점
    let spotsL = (0..<4).map { _ in CGPoint(x: rnd(250, 480), y: rnd(840, 1300)) }
    let spotsR = (0..<4).map { _ in CGPoint(x: rnd(600, 830), y: rnd(840, 1300)) }
    var list: [Tap] = []
    var t = drumStart, i = 0
    while t < drumEnd {
        let left = i % 2 == 0
        let spots = left ? spotsL : spotsR
        let base = spots[min(spots.count - 1, Int(rnd() * Double(spots.count)))]
        let p = CGPoint(x: base.x + rnd(-22, 22), y: base.y + rnd(-22, 22))
        list.append(Tap(time: t, point: p, left: left, major: i % 6 == 3))
        t += rnd(0.115, 0.15); i += 1
    }
    return list
}()

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

// MARK: - 금(crack) 미리 생성
struct Crack {
    var lines: [[CGPoint]] = []   // 방사형 + 가지
    var rings: [[CGPoint]] = []   // 동심원 조각
    var shards: [[CGPoint]] = []  // 중앙 유리 파편
}

func insideCrackZone(_ p: CGPoint) -> Bool { p.y > crackTopLimit && p.y < crackBottomLimit }

func makeCrack(at c: CGPoint, major: Bool, order: Int) -> Crack {
    var crack = Crack()
    let spokes = major ? 6 + Int(rnd() * 3) : 3 + Int(rnd() * 3)
    let maxLen = major ? 190 + Double(order) * 25 : rnd(50, 100)
    var spokePoints: [[CGPoint]] = []
    for s in 0..<spokes {
        var a = Double(s) / Double(spokes) * 2 * .pi + rnd(-0.2, 0.2)
        let len = maxLen * rnd(0.5, 1.0)
        let topLimit = crackTopLimit + rnd(0, 160)   // 경계가 일직선으로 잘리지 않게
        var p = c, pts = [c], travelled = 0.0
        while travelled < len {
            let step = rnd(50, 110)
            a += rnd(-0.07, 0.07)
            let n = CGPoint(x: p.x + step * cos(a), y: p.y + step * sin(a))
            if !insideCrackZone(n) || n.y < topLimit { break }
            pts.append(n); p = n; travelled += step
            // 가지
            if travelled > 90 && rnd() < 0.1 {
                var ba = a + (rnd() < 0.5 ? -1 : 1) * rnd(0.4, 0.8)
                var bp = n, branch = [n]
                for _ in 0..<Int(rnd(2, 4)) {
                    ba += rnd(-0.08, 0.08)
                    let bs = rnd(35, 70)
                    let nb = CGPoint(x: bp.x + bs * cos(ba), y: bp.y + bs * sin(ba))
                    if !insideCrackZone(nb) { break }
                    branch.append(nb); bp = nb
                }
                if branch.count > 1 { crack.lines.append(branch) }
            }
        }
        crack.lines.append(pts)
        spokePoints.append(pts)
    }
    // 동심원: 인접한 방사선의 k번째 점을 이어줌
    for k in [1, 2] {
        for s in 0..<spokes {
            let a = spokePoints[s], b = spokePoints[(s + 1) % spokes]
            guard a.count > k, b.count > k, rnd() < 0.75 else { continue }
            let mid = CGPoint(x: (a[k].x + b[k].x) / 2 + rnd(-5, 5), y: (a[k].y + b[k].y) / 2 + rnd(-5, 5))
            crack.rings.append([a[k], mid, b[k]])
        }
    }
    // 중앙 파편
    for _ in 0..<(major ? 6 : 2) {
        let a0 = rnd(0, 2 * .pi), r0 = rnd(8, 40)
        let base = CGPoint(x: c.x + r0 * cos(a0), y: c.y + r0 * sin(a0))
        var poly: [CGPoint] = []
        for v in 0..<3 {
            let av = a0 + Double(v) * 2.1 + rnd(-0.4, 0.4), rv = rnd(10, 26)
            poly.append(CGPoint(x: base.x + rv * cos(av), y: base.y + rv * sin(av)))
        }
        crack.shards.append(poly)
    }
    return crack
}
let cracks: [Crack] = {
    var order = 0
    return taps.map { tap in
        defer { if tap.major { order += 1 } }
        if !tap.major && rnd() < 0.55 { return Crack() }   // 작은 타격은 가끔만 금을 남김
        return makeCrack(at: tap.point, major: tap.major, order: order)
    }
}()
func isDrumming(_ t: Double) -> Bool { t > drumStart - 0.25 && t < drumEnd + 0.25 }

// 폴리라인을 진행도(0~1)만큼만 그림
func partialPath(_ pts: [CGPoint], _ g: Double) -> CGPath {
    let path = CGMutablePath()
    guard pts.count > 1 else { return path }
    var total = 0.0
    for i in 1..<pts.count { total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
    var remain = total * g
    path.move(to: pts[0])
    for i in 1..<pts.count {
        let seg = hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
        if remain >= seg { path.addLine(to: pts[i]); remain -= seg }
        else { path.addLine(to: lerpP(pts[i - 1], pts[i], remain / seg)); break }
    }
    return path
}

// MARK: - 장면 상태
func impactPulse(_ t: Double) -> Double {   // 최근 충격의 세기 (1 → 0)
    var v = 0.0
    for tap in taps where t >= tap.time { v = max(v, exp(-(t - tap.time) * 7)) }
    return v
}
func shake(_ t: Double) -> CGPoint {
    var x = 0.0, y = 0.0
    for tap in taps where t >= tap.time {
        let u = t - tap.time, amp = (tap.major ? 14 : 7) * exp(-u * 22)
        x += amp * sin(u * 95); y += amp * cos(u * 77)
    }
    return CGPoint(x: x, y: y)
}

let restL = CGPoint(x: 300, y: 1690), restR = CGPoint(x: 780, y: 1690)
let shoulderL = CGPoint(x: 330, y: 1900), shoulderR = CGPoint(x: 750, y: 1900)

// 앞발 위치·크기·눌림 여부
func paw(left: Bool, t: Double, bob: Double) -> (pos: CGPoint, scale: Double, pressed: Bool) {
    let rest = CGPoint(x: (left ? restL : restR).x, y: (left ? restL : restR).y + bob)
    let mine = taps.filter { $0.left == left }
    guard let first = mine.first, let last = mine.last else { return (rest, 0.9, false) }
    let hoverScale = 1.05, pressScale = 1.3
    func hover(_ tap: Tap) -> CGPoint { CGPoint(x: tap.point.x, y: tap.point.y + 80) }  // 유리에서 살짝 떨어진 위치
    // 시작: 몸 쪽에서 들어 올림
    if t < first.time {
        let raise = clamp((t - (first.time - 0.4)) / 0.3)
        if t < first.time - 0.1 { return (lerpP(rest, hover(first), easeOut(raise)), lerp(0.9, hoverScale, raise), false) }
        let p = easeIn((t - (first.time - 0.1)) / 0.1)
        return (lerpP(hover(first), first.point, p), lerp(hoverScale, pressScale, p), false)
    }
    // 끝: 몸 쪽으로 내림
    if t >= last.time {
        let u = t - last.time
        if u < pressHold { return (last.point, pressScale, true) }
        let p = easeOut(clamp((u - pressHold) / 0.4))
        return (lerpP(last.point, rest, p), lerp(pressScale, 0.9, p), false)
    }
    // 두드리는 중: 직전 타격 지점 → 다음 타격 위 호버 → 다음 타격
    let ni = mine.firstIndex { $0.time > t }!
    let prev = mine[ni - 1], next = mine[ni]
    let u = t - prev.time, d = next.time - prev.time
    if u < pressHold { return (prev.point, pressScale, true) }
    let back = pressHold + (d - pressHold) * 0.55
    if u < back {
        let p = easeOut((u - pressHold) / (back - pressHold))
        return (lerpP(prev.point, hover(next), p), lerp(pressScale, hoverScale, p), false)
    }
    let p = easeIn((u - back) / (d - back))
    return (lerpP(hover(next), next.point, p), lerp(hoverScale, pressScale, p), false)
}

// MARK: - 그리기
let tan = hex(0xE9A05B), tanDark = hex(0xC97E3D), cream = hex(0xFFF1DC), ear = hex(0xB8733A)
let ink = hex(0x2B1A10), pink = hex(0xFF9AA8), tongue = hex(0xFF7A8A), blush = hex(0xFF8A80, 0.45)

func drawBackground(_ ctx: CGContext, t: Double) {
    let g = CGGradient(colorsSpace: cs, colors: [hex(0xFF8A5B), hex(0xFFB300), hex(0xFFC107), hex(0xFFE8D6)] as CFArray,
                       locations: [0, 0.35, 0.55, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [])
    radial(ctx, CGPoint(x: 540, y: 1000), 620, hex(0xFFF6C8, 0.75), hex(0xFFF6C8, 0))
    // 떠다니는 보케 (루프 길이에 맞춘 정수 주기)
    var s: UInt64 = 7
    func r() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    for _ in 0..<12 {
        let bx = r() * W, by = r() * H, br = 30 + r() * 70, k = Double(1 + Int(r() * 2)), ph = r() * 2 * .pi
        let c = CGPoint(x: bx + 25 * sin(2 * .pi * k * t / duration + ph), y: by + 18 * cos(2 * .pi * k * t / duration + ph))
        radial(ctx, c, br, hex(0xFFFFFF, 0.22), hex(0xFFFFFF, 0))
    }
}

func drawDog(_ ctx: CGContext, t: Double) {
    let bob = 10 * sin(2 * .pi * 10 * t / duration)   // 0.7초 주기
    let pulse = impactPulse(t)
    let drumming = isDrumming(t)
    let hy = 1290 + bob + 10 * pulse
    let hx = 540.0

    // 몸통
    ellipse(ctx, CGPoint(x: 540, y: 1990 + bob * 0.5), 540, 330, tan)
    ellipse(ctx, CGPoint(x: 540, y: 1930 + bob * 0.5), 260, 200, cream)

    // 귀 (충격 때 펄럭)
    let flap = 0.16 * pulse
    ellipse(ctx, CGPoint(x: hx - 300, y: hy - 120), 105, 200, ear, rot: 0.45 + flap)
    ellipse(ctx, CGPoint(x: hx + 300, y: hy - 120), 105, 200, ear, rot: -0.45 - flap)

    // 머리
    ellipse(ctx, CGPoint(x: hx, y: hy), 360, 320, tan)
    ellipse(ctx, CGPoint(x: hx, y: hy + 115), 200, 145, cream)                   // 주둥이
    ellipse(ctx, CGPoint(x: hx - 215, y: hy + 85), 58, 36, blush)
    ellipse(ctx, CGPoint(x: hx + 215, y: hy + 85), 58, 36, blush)

    // 눈: 두드리는 동안 > < 로 찡그림
    ctx.setStrokeColor(ink); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    for side in [-1.0, 1.0] {
        let ex = hx + side * 130, ey = hy - 40
        if drumming {
            ctx.setLineWidth(14)
            ctx.move(to: CGPoint(x: ex - side * 34, y: ey - 26))
            ctx.addLine(to: CGPoint(x: ex + side * 22, y: ey))
            ctx.addLine(to: CGPoint(x: ex - side * 34, y: ey + 26))
            ctx.strokePath()
        } else {
            ellipse(ctx, CGPoint(x: ex, y: ey), 40, 48, ink)
            ellipse(ctx, CGPoint(x: ex + 13, y: ey - 17), 14, 14, hex(0xFFFFFF))
            ellipse(ctx, CGPoint(x: ex - 12, y: ey + 16), 6, 6, hex(0xFFFFFF, 0.8))
        }
    }

    // 두드리는 동안 입을 크게 벌림
    if drumming {
        let open = 1 + 0.12 * sin(2 * .pi * 40 * t / duration)
        ellipse(ctx, CGPoint(x: hx, y: hy + 175), 78, 70 * open, hex(0x5A2418))
        ellipse(ctx, CGPoint(x: hx, y: hy + 215 * 1.0 + 8 * (open - 1) * 10), 50, 30, tongue)
    }
    // 혀 → 입 → 코
    let tongueLen = 55 + 10 * sin(2 * .pi * 20 * t / duration)
    if !drumming {
        ellipse(ctx, CGPoint(x: hx, y: hy + 150 + tongueLen * 0.5), 44, tongueLen, tongue)
        ctx.setStrokeColor(hex(0xE85C6E)); ctx.setLineWidth(5)
        ctx.move(to: CGPoint(x: hx, y: hy + 160)); ctx.addLine(to: CGPoint(x: hx, y: hy + 150 + tongueLen * 1.1)); ctx.strokePath()
    }
    ctx.setStrokeColor(ink); ctx.setLineWidth(10)
    ctx.move(to: CGPoint(x: hx - 80, y: hy + 135))
    ctx.addQuadCurve(to: CGPoint(x: hx, y: hy + 110), control: CGPoint(x: hx - 40, y: hy + 175))
    ctx.addQuadCurve(to: CGPoint(x: hx + 80, y: hy + 135), control: CGPoint(x: hx + 40, y: hy + 175))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: hx, y: hy + 80)); ctx.addLine(to: CGPoint(x: hx, y: hy + 112)); ctx.strokePath()
    ellipse(ctx, CGPoint(x: hx, y: hy + 62), 54, 38, ink)
    ellipse(ctx, CGPoint(x: hx - 16, y: hy + 50), 16, 9, hex(0xFFFFFF, 0.7))

    // 앞발 (화면 쪽으로 가까이 오므로 머리 위에 그림)
    for left in [true, false] {
        let p = paw(left: left, t: t, bob: bob)
        let shoulder = left ? shoulderL : shoulderR
        ctx.setStrokeColor(tan); ctx.setLineWidth(105 * p.scale); ctx.setLineCap(.round)
        ctx.move(to: shoulder); ctx.addLine(to: p.pos); ctx.strokePath()
        let s = p.scale * (p.pressed ? 1.06 : 1)
        ellipse(ctx, p.pos, 112 * s, 106 * s, tanDark)
        ellipse(ctx, p.pos, 104 * s, 98 * s, cream)
        ellipse(ctx, CGPoint(x: p.pos.x, y: p.pos.y + 28 * s), 46 * s, 38 * s, pink)
        for (dx, dy) in [(-58.0, -30.0), (-22.0, -62.0), (22.0, -62.0), (58.0, -30.0)] {
            ellipse(ctx, CGPoint(x: p.pos.x + dx * s, y: p.pos.y + dy * s), 21 * s, 23 * s, pink)
        }
    }
}

func drawCracks(_ ctx: CGContext, t: Double) {
    let alpha = t > fadeStart ? clamp(1 - (t - fadeStart) / (duration - fadeStart)) : 1
    guard alpha > 0 else { return }
    for (i, tap) in taps.enumerated() where t >= tap.time {
        let u = t - tap.time
        let g = easeOut(clamp(u / 0.2))
        let c = cracks[i]

        // 충격 지점의 뿌연 유리 + 짧게 퍼지는 링 (전체 화면 번쩍임 없음)
        radial(ctx, tap.point, 130, hex(0xFFFFFF, 0.22 * alpha), hex(0xFFFFFF, 0))
        if u < 0.25 {
            let rr = 30 + u * (tap.major ? 650 : 320)
            ctx.setStrokeColor(hex(0xFFFFFF, 0.5 * (1 - u / 0.25) * alpha)); ctx.setLineWidth(6)
            ctx.strokeEllipse(in: CGRect(x: tap.point.x - rr, y: tap.point.y - rr, width: rr * 2, height: rr * 2))
        }

        let all = c.lines + (g > 0.5 ? c.rings : [])
        let gg = { (pts: [CGPoint]) -> Double in c.rings.contains(where: { $0 == pts }) ? clamp((g - 0.5) * 2) : g }
        // 그림자 → 글레어 → 흰 선
        for pts in all {
            let path = partialPath(pts, gg(pts))
            ctx.saveGState(); ctx.translateBy(x: 2, y: 2)
            ctx.addPath(path); ctx.setStrokeColor(hex(0x3C1E0A, 0.35 * alpha)); ctx.setLineWidth(4); ctx.strokePath()
            ctx.restoreGState()
            ctx.addPath(path); ctx.setStrokeColor(hex(0xFFFFFF, 0.14 * alpha)); ctx.setLineWidth(7); ctx.strokePath()
            ctx.addPath(path); ctx.setStrokeColor(hex(0xFFFFFF, 0.92 * alpha)); ctx.setLineWidth(2.0); ctx.strokePath()
        }
        for poly in c.shards where g > 0.3 {
            ctx.beginPath(); ctx.addLines(between: poly); ctx.closePath()
            ctx.setFillColor(hex(0xFFFFFF, 0.35 * alpha)); ctx.setStrokeColor(hex(0xFFFFFF, 0.85 * alpha)); ctx.setLineWidth(1.5)
            ctx.drawPath(using: .fillStroke)
        }
    }
}

func drawFrame(_ ctx: CGContext, t: Double) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)   // 좌상단 원점
    let sh = shake(t)
    ctx.translateBy(x: sh.x, y: sh.y)
    ctx.translateBy(x: W / 2, y: H / 2); ctx.scaleBy(x: 1.03, y: 1.03); ctx.translateBy(x: -W / 2, y: -H / 2) // 흔들림 때 가장자리 안 보이게
    drawBackground(ctx, t: t)
    drawDog(ctx, t: t)
    drawCracks(ctx, t: t)
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

let previewTimes: [Double] = [0.3, 1.0, 1.05, 3.0, 6.0, 6.5]
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
        let u = dir.appendingPathComponent(String(format: "puppy_%03d.png", i))
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
