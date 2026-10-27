// makeicon.swift — 生成 动态壁纸 的 app 图标（1024x1024 PNG）
import Cocoa
import CoreGraphics

let size: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("ctx") }

let s = size

// ── 背景：圆角矩形（macOS 图标风格，留边距） ──
let inset: CGFloat = s * 0.055
let rect = CGRect(x: inset, y: inset, width: s - inset*2, height: s - inset*2)
let radius = rect.width * 0.225
let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// 渐变底色（深空蓝紫 → 暮橙）
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 0.13, green: 0.10, blue: 0.30, alpha: 1),
        CGColor(red: 0.35, green: 0.18, blue: 0.48, alpha: 1),
        CGColor(red: 0.85, green: 0.42, blue: 0.38, alpha: 1),
        CGColor(red: 0.98, green: 0.72, blue: 0.42, alpha: 1)
    ] as CFArray,
    locations: [0.0, 0.38, 0.72, 1.0]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: rect.minX, y: rect.maxY),
    end: CGPoint(x: rect.maxX, y: rect.minY),
    options: []
)
ctx.restoreGState()

// ── 太阳 ──
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let sunCenter = CGPoint(x: s*0.66, y: s*0.60)
let sunR = s*0.085
let sunGrad = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 1.0, green: 0.96, blue: 0.80, alpha: 1.0),
        CGColor(red: 1.0, green: 0.80, blue: 0.45, alpha: 0.55),
        CGColor(red: 1.0, green: 0.70, blue: 0.35, alpha: 0.0)
    ] as CFArray,
    locations: [0.0, 0.45, 1.0]
)!
ctx.drawRadialGradient(
    sunGrad,
    startCenter: sunCenter, startRadius: 0,
    endCenter: sunCenter, endRadius: sunR*3.2,
    options: []
)
ctx.setFillColor(CGColor(red: 1.0, green: 0.97, blue: 0.86, alpha: 1.0))
ctx.fillEllipse(in: CGRect(x: sunCenter.x-sunR, y: sunCenter.y-sunR, width: sunR*2, height: sunR*2))
ctx.restoreGState()

// ── 远山（三层，由远及近） ──
func mountain(baseY: CGFloat, peaks: [(CGFloat, CGFloat)], color: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: rect.minX, y: baseY))
    for (x, h) in peaks {
        p.addLine(to: CGPoint(x: x, y: baseY + h))
    }
    p.addLine(to: CGPoint(x: rect.maxX, y: baseY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
    p.closeSubpath()
    ctx.addPath(p)
    ctx.setFillColor(color)
    ctx.fillPath()
}

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

// 远山
mountain(baseY: s*0.44, peaks: [
    (s*0.10, s*0.13), (s*0.26, s*0.22), (s*0.40, s*0.11),
    (s*0.55, s*0.19), (s*0.72, s*0.10), (s*0.90, s*0.16)
], color: CGColor(red: 0.24, green: 0.16, blue: 0.40, alpha: 0.85))

// 中山
mountain(baseY: s*0.33, peaks: [
    (s*0.05, s*0.10), (s*0.22, s*0.19), (s*0.38, s*0.08),
    (s*0.52, s*0.16), (s*0.68, s*0.07), (s*0.84, s*0.14), (s*0.98, s*0.06)
], color: CGColor(red: 0.15, green: 0.09, blue: 0.28, alpha: 0.95))

// 近山
mountain(baseY: s*0.22, peaks: [
    (s*0.08, s*0.07), (s*0.25, s*0.13), (s*0.44, s*0.05),
    (s*0.60, s*0.12), (s*0.78, s*0.05), (s*0.94, s*0.10)
], color: CGColor(red: 0.07, green: 0.04, blue: 0.14, alpha: 1.0))

// ── 胶片条（表示"视频"） ──
let stripH = s*0.155
let stripY = rect.minY + s*0.055
let stripRect = CGRect(x: rect.minX + s*0.085, y: stripY, width: rect.width - s*0.17, height: stripH)
ctx.setFillColor(CGColor(red: 0.04, green: 0.03, blue: 0.09, alpha: 0.92))
ctx.addPath(CGPath(roundedRect: stripRect, cornerWidth: stripH*0.22, cornerHeight: stripH*0.22, transform: nil))
ctx.fillPath()

// 齿孔（中间给播放三角留出空位）
let holeW = stripH * 0.22
let holeH = stripH * 0.26
let holeGap = stripH * 0.42
let centerZone = stripH * 0.95   // 三角占用的水平范围（半宽）
ctx.setFillColor(CGColor(red: 0.98, green: 0.95, blue: 0.88, alpha: 0.95))
var hx = stripRect.minX + holeW*0.7
while hx < stripRect.maxX - holeW*0.7 {
    let holeCenterX = hx + holeW/2
    if abs(holeCenterX - stripRect.midX) > centerZone {
        for hy in [stripRect.maxY - holeH*1.35, stripRect.minY + holeH*0.35] {
            ctx.addPath(CGPath(
                roundedRect: CGRect(x: hx, y: hy, width: holeW, height: holeH),
                cornerWidth: holeW*0.28, cornerHeight: holeW*0.28, transform: nil
            ))
        }
    }
    hx += holeW + holeGap
}
ctx.fillPath()

// 播放三角
let triCx = rect.midX
let triCy = stripRect.midY
let triR = stripH * 0.30
let tri = CGMutablePath()
tri.move(to: CGPoint(x: triCx - triR*0.72, y: triCy + triR))
tri.addLine(to: CGPoint(x: triCx + triR*0.95, y: triCy))
tri.addLine(to: CGPoint(x: triCx - triR*0.72, y: triCy - triR))
tri.closeSubpath()
ctx.setFillColor(CGColor(red: 1.0, green: 0.93, blue: 0.75, alpha: 1.0))
ctx.addPath(tri)
ctx.fillPath()

ctx.restoreGState()

// ── 顶部高光 ──
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let gloss = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.20),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
    ] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    gloss,
    start: CGPoint(x: rect.midX, y: rect.maxY),
    end: CGPoint(x: rect.midX, y: rect.midY + s*0.05),
    options: []
)
ctx.restoreGState()

// ── 描边 ──
ctx.addPath(bgPath)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.13))
ctx.setLineWidth(s*0.006)
ctx.strokePath()

// ── 输出 PNG ──
guard let img = ctx.makeImage() else { fatalError("img") }
let outURL = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png")
let rep = NSBitmapImageRep(cgImage: img)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: outURL)
print("wrote \(outURL.path)")
