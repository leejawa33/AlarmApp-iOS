// 앱 아이콘(1024x1024, 불투명 PNG) 생성: swift Tools/make_app_icon.swift
// 출력: AlarmApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, a])!
}
let S = CGFloat(size)
let c = CGPoint(x: S / 2, y: S / 2 - 20)

// 배경: sun → sun-deep 대각선 그라디언트
let grad = CGGradient(colorsSpace: cs, colors: [color(0xFFD54F), color(0xFFB300)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

// 햇살(은은한 방사형 줄무늬)
ctx.saveGState()
ctx.translateBy(x: c.x, y: c.y)
ctx.setFillColor(color(0xFFFFFF, 0.12))
for i in 0..<12 {
    ctx.saveGState()
    ctx.rotate(by: CGFloat(i) * .pi / 6)
    ctx.move(to: .zero)
    ctx.addLine(to: CGPoint(x: -90, y: 900))
    ctx.addLine(to: CGPoint(x: 90, y: 900))
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()
}
ctx.restoreGState()

// 종(코랄) 두 개
let r: CGFloat = 255
// 종: 반원 돔을 시계 위쪽에서 ±35° 기울여 배치 + 꼭지 손잡이
for dir in [-1.0, 1.0] {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: -CGFloat(dir) * 35 * .pi / 180)
    let base = r + 20, br: CGFloat = 125
    ctx.setFillColor(color(0xE8454A))
    ctx.addArc(center: CGPoint(x: 0, y: base), radius: br, startAngle: .pi, endAngle: 0, clockwise: true)
    ctx.closePath()
    ctx.fillPath()
    ctx.fillEllipse(in: CGRect(x: -26, y: base + br - 6, width: 52, height: 52))
    ctx.restoreGState()
}
// 가운데 망치
ctx.setStrokeColor(color(0xE8454A)); ctx.setLineWidth(34); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: c.x, y: c.y + r + 20)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + r + 95)); ctx.strokePath()
// 다리
ctx.setStrokeColor(color(0xE8454A)); ctx.setLineWidth(46); ctx.setLineCap(.round)
for dir in [-1.0, 1.0] {
    ctx.move(to: CGPoint(x: c.x + CGFloat(dir) * 180, y: c.y - 270))
    ctx.addLine(to: CGPoint(x: c.x + CGFloat(dir) * 235, y: c.y - 350))
    ctx.strokePath()
}

// 시계 본체: 그림자 + 흰 원 + 코랄 테두리
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 40, color: color(0x000000, 0.25))
ctx.setFillColor(color(0xFF5A5F))
ctx.fillEllipse(in: CGRect(x: c.x - r - 40, y: c.y - r - 40, width: (r + 40) * 2, height: (r + 40) * 2))
ctx.restoreGState()
ctx.setFillColor(color(0xFFF8F0))
ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))

// 눈금 12개
ctx.setStrokeColor(color(0x1A1A1A)); ctx.setLineCap(.round)
for i in 0..<12 {
    let a = CGFloat(i) * .pi / 6
    let big = i % 3 == 0
    ctx.setLineWidth(big ? 22 : 12)
    let r1 = r - (big ? 70 : 55), r2 = r - 30
    ctx.move(to: CGPoint(x: c.x + sin(a) * r1, y: c.y + cos(a) * r1))
    ctx.addLine(to: CGPoint(x: c.x + sin(a) * r2, y: c.y + cos(a) * r2))
    ctx.strokePath()
}
// 바늘 (10시 10분 느낌 → 웃는 모양)
ctx.setLineWidth(30)
ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x - 95, y: c.y + 95)); ctx.strokePath()
ctx.setLineWidth(22)
ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x + 120, y: c.y + 105)); ctx.strokePath()
ctx.setFillColor(color(0xFF5A5F))
ctx.fillEllipse(in: CGRect(x: c.x - 24, y: c.y - 24, width: 48, height: 48))

let out = URL(fileURLWithPath: "AlarmApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
print("wrote \(out.path)")
