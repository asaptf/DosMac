#!/usr/bin/env swift
// Original vector artwork; Apache-2.0. Run from the repository root on macOS.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Sources/DosMacApp/Resources/Assets.xcassets")
let destination = assets.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let mint = CGColor(red: 0.64, green: 0.92, blue: 0.69, alpha: 1)
func render(size: Int, mac: Bool, filename: String) throws {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: colorSpace, bitmapInfo: mac ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    let bounds = mac ? CGRect(x: 52, y: 52, width: 920, height: 920) : CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let background = CGPath(roundedRect: bounds, cornerWidth: mac ? 205 : 0, cornerHeight: mac ? 205 : 0, transform: nil)
    context.saveGState()
    if mac { context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.3)) }
    context.addPath(background); context.setFillColor(CGColor(red: 0.07, green: 0.12, blue: 0.10, alpha: 1)); context.fillPath()
    context.restoreGState()
    context.saveGState(); context.addPath(background); context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [CGColor(red: 0.20, green: 0.35, blue: 0.27, alpha: 1),CGColor(red: 0.045, green: 0.09, blue: 0.07, alpha: 1)] as CFArray, locations: [0,1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 120, y: 950), end: CGPoint(x: 800, y: 90), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
    let terminal = CGPath(roundedRect: CGRect(x: 215, y: 285, width: 594, height: 464), cornerWidth: 55, cornerHeight: 55, transform: nil)
    context.setFillColor(CGColor(red: 0.055, green: 0.10, blue: 0.08, alpha: 1))
    context.addPath(terminal); context.fillPath()
    context.setStrokeColor(mint); context.setLineWidth(24); context.addPath(terminal); context.strokePath()
    context.setLineWidth(15); context.move(to: CGPoint(x: 230, y: 648)); context.addLine(to: CGPoint(x: 794, y: 648)); context.strokePath()
    for x in [270,310,350] { context.setFillColor(mint); context.fillEllipse(in: CGRect(x: x, y: 686, width: 15, height: 15)) }
    context.setLineCap(.round); context.setLineJoin(.round); context.setLineWidth(34)
    context.move(to: CGPoint(x: 319, y: 547)); context.addLine(to: CGPoint(x: 409, y: 470)); context.addLine(to: CGPoint(x: 319, y: 393)); context.strokePath()
    context.move(to: CGPoint(x: 495, y: 390)); context.addLine(to: CGPoint(x: 671, y: 390)); context.strokePath()
    let image = context.makeImage()!
    let output = CGImageDestinationCreateWithURL(destination.appendingPathComponent(filename) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
}
var entries: [[String:String]] = []
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let file = "mac-\(size)@\(scale)x.png"
        try render(size: size*scale, mac: true, filename: file)
        entries.append(["idiom":"mac","size":"\(size)x\(size)","scale":"\(scale)x","filename":file])
    }
}
try render(size: 1024, mac: false, filename: "ios-1024.png")
entries.append(["idiom":"universal","platform":"ios","size":"1024x1024","filename":"ios-1024.png"])
let info: [String:Any] = ["images":entries,"info":["author":"DosMac","version":1]]
try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted,.sortedKeys]).write(to: destination.appendingPathComponent("Contents.json"))
try Data("{\"info\":{\"author\":\"DosMac\",\"version\":1}}\n".utf8).write(to: assets.appendingPathComponent("Contents.json"))
print("Rendered macOS and iOS AppIcon assets.")
