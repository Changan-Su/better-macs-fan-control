import AppKit
import CoreGraphics
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    let background = CGColor(red: 0.08, green: 0.49, blue: 0.41, alpha: 1)
    context.setFillColor(background)
    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 12, y: 12, width: 1000, height: 1000), cornerWidth: 220,
            cornerHeight: 220, transform: nil))
    context.fillPath()
    let center = CGPoint(x: 512, y: 512)
    for index in 0..<9 {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(index) * 2 * .pi / 9)
        context.setFillColor(CGColor(gray: 1, alpha: 0.95))
        context.move(to: CGPoint(x: -40, y: 80))
        context.addCurve(
            to: CGPoint(x: -115, y: 330), control1: CGPoint(x: -180, y: 175),
            control2: CGPoint(x: -220, y: 290))
        context.addCurve(
            to: CGPoint(x: 90, y: 95), control1: CGPoint(x: 75, y: 400),
            control2: CGPoint(x: 175, y: 200))
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillEllipse(in: CGRect(x: 430, y: 430, width: 164, height: 164))
    context.setFillColor(background)
    context.fillEllipse(in: CGRect(x: 485, y: 485, width: 54, height: 54))
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    let png = bitmap.representation(using: .png, properties: [:])!
    for base in [16, 32, 128, 256, 512] {
        if size == base {
            try png.write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
        }
        if size == base * 2 {
            try png.write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
        }
    }
}
