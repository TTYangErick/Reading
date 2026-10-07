// Rebuild code-native Reading icons on macOS: swift scripts/generate_app_icons.swift
// Coordinates are shared by CoreGraphics PNGs and Android vector drawables.
import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fm = FileManager.default
struct Shape {
    let path: CGMutablePath
    let data: String
}
func page(_ right: Bool) -> Shape {
    let path = CGMutablePath()
    if right {
        path.move(to: CGPoint(x: 56, y: 36))
        path.addCurve(to: CGPoint(x: 82, y: 33), control1: CGPoint(x: 64, y: 31), control2: CGPoint(x: 73, y: 29))
        path.addLine(to: CGPoint(x: 82, y: 72))
        path.addCurve(to: CGPoint(x: 56, y: 76), control1: CGPoint(x: 73, y: 68), control2: CGPoint(x: 64, y: 70))
        path.closeSubpath()
        return Shape(path: path, data: "M56,36 C64,31 73,29 82,33 L82,72 C73,68 64,70 56,76 Z")
    }
    path.move(to: CGPoint(x: 26, y: 33))
    path.addCurve(to: CGPoint(x: 52, y: 36), control1: CGPoint(x: 35, y: 29), control2: CGPoint(x: 44, y: 31))
    path.addLine(to: CGPoint(x: 52, y: 76))
    path.addCurve(to: CGPoint(x: 26, y: 72), control1: CGPoint(x: 44, y: 70), control2: CGPoint(x: 35, y: 68))
    path.closeSubpath()
    return Shape(path: path, data: "M26,33 C35,29 44,31 52,36 L52,76 C44,70 35,68 26,72 Z")
}
let pages = [page(false), page(true)]
let bookmark = CGMutablePath()
bookmark.move(to: CGPoint(x: 68, y: 32))
bookmark.addLine(to: CGPoint(x: 74, y: 32))
bookmark.addLine(to: CGPoint(x: 74, y: 52))
bookmark.addLine(to: CGPoint(x: 71, y: 49))
bookmark.addLine(to: CGPoint(x: 68, y: 52))
bookmark.closeSubpath()
let mark = Shape(path: bookmark, data: "M68,32 L74,32 L74,52 L71,49 L68,52 Z")
func color(_ hex: String) -> CGColor {
    let value = UInt32(hex, radix: 16)!
    return CGColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                   green: CGFloat((value >> 8) & 255) / 255,
                   blue: CGFloat(value & 255) / 255, alpha: 1)
}
func write(_ text: String, _ path: String) throws {
    let url = root.appendingPathComponent(path)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}
func png(_ size: Int, _ path: String, launch: Bool = false) throws {
    let alpha = launch ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue)!
    if !launch {
        context.setFillColor(color("835C3E")); context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    context.translateBy(x: 0, y: CGFloat(size)); context.scaleBy(x: CGFloat(size) / 108, y: -CGFloat(size) / 108)
    context.setFillColor(color(launch ? "835C3E" : "FBFAF8"))
    for shape in pages { context.addPath(shape.path); context.fillPath() }
    context.setFillColor(color("C49A6C")); context.addPath(mark.path); context.fillPath()
    let data = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    try data.write(to: root.appendingPathComponent(path))
}
let icons = "app/ios/Runner/Assets.xcassets/AppIcon.appiconset/"
let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(icons + "Contents.json"))) as! [String: Any]
var written = Set<String>()
for entry in catalog["images"] as! [[String: String]] {
    guard let file = entry["filename"], written.insert(file).inserted else { continue }
    let points = Double(entry["size"]!.split(separator: "x")[0])!
    let scale = Double(entry["scale"]!.dropLast())!
    try png(Int(points * scale), icons + file)
}
for (density, size) in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)] {
    try png(size, "app/android/app/src/main/res/mipmap-\(density)/ic_launcher.png")
}
for scale in 1...3 {
    try png(168 * scale, "app/ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage\(scale == 1 ? "" : "@\(scale)x").png", launch: true)
}
func vector(_ foreground: String, monochrome: Bool = false) -> String {
    let paths = pages.map { "    <path android:fillColor=\"\(foreground)\" android:pathData=\"\($0.data)\" />" }.joined(separator: "\n")
    let accent = monochrome ? "" : "\n    <path android:fillColor=\"#C49A6C\" android:pathData=\"\(mark.data)\" />"
    return """
    <?xml version="1.0" encoding="utf-8"?>
    <vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
    \(paths)\(accent)
    </vector>

    """
}
let res = "app/android/app/src/main/res/"
try write(vector("#FBFAF8"), res + "drawable/reading_icon_foreground.xml")
try write(vector("#FFFFFF", monochrome: true), res + "drawable/reading_icon_monochrome.xml")
try write(vector("#835C3E"), res + "drawable/reading_splash.xml")
for version in [26,33] {
    let mono = version == 33 ? "\n    <monochrome android:drawable=\"@drawable/reading_icon_monochrome\" />" : ""
    try write("""
    <?xml version="1.0" encoding="utf-8"?>
    <adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
        <background android:drawable="@color/reading_brand" />
        <foreground android:drawable="@drawable/reading_icon_foreground" />\(mono)
    </adaptive-icon>

    """, res + "mipmap-anydpi-v\(version)/ic_launcher.xml")
}
print("Generated Reading app icons and launch images from shared vector geometry.")
