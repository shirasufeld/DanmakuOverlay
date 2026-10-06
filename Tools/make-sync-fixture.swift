// Generates a sync-verification fixture: a video with a burnt-in timecode and a danmaku XML whose
// top danmaku read the same timecode at the moment they appear.
//
// Usage: swift Tools/make-sync-fixture.swift <output-dir> [seconds=180]
// Produces <output-dir>/sync.mp4 and <output-dir>/sync.xml (same basename, so it auto-loads).
import AppKit
import Foundation

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "Tools/fixtures")
let seconds = args.count > 2 ? Int(args[2]) ?? 180 : 180
let (width, height, fps) = (960, 540, 20)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// Danmaku: one top danmaku per second with its own timestamp, plus scrolling filler.
var xml = #"<?xml version="1.0" encoding="UTF-8"?><i><chatid>0</chatid>"#
for s in 0..<seconds {
    xml += #"<d p="\#(s).000,5,25,16776960,0,0,sync,\#(s + 1)">▼ \#(String(format: "%02d:%02d", s / 60, s % 60))</d>"#
    xml += #"<d p="\#(s).500,1,25,16777215,0,0,sync,\#(100_000 + s)">roll \#(s).5 →</d>"#
}
xml += "</i>"
try xml.write(to: outDir.appending(path: "sync.xml"), atomically: true, encoding: .utf8)

let ffmpeg = Process()
ffmpeg.executableURL = URL(fileURLWithPath: "/usr/bin/env")
ffmpeg.arguments = [
    "ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "bgra", "-s", "\(width)x\(height)",
    "-r", "\(fps)", "-i", "-", "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
    outDir.appending(path: "sync.mp4").path,
]
let pipe = Pipe()
ffmpeg.standardInput = pipe
try ffmpeg.run()

let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
let font = NSFont.monospacedDigitSystemFont(ofSize: 96, weight: .bold)
for frame in 0..<(seconds * fps) {
    let t = Double(frame) / Double(fps)
    ctx.setFillColor(CGColor(red: 0.08, green: 0.1, blue: 0.16, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // A bar sweeping once per second makes sub-second offsets visible.
    let phase = t - floor(t)
    ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: Double(width) * phase, height: 24))
    let text = String(format: "%02d:%02d.%02d", Int(t) / 60, Int(t) % 60, Int((t - floor(t)) * 100))
    let attributed = NSAttributedString(
        string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: (Double(width) - bounds.width) / 2, y: Double(height) / 2 - 40)
    CTLineDraw(line, ctx)
    let data = Data(bytes: ctx.data!, count: width * height * 4)
    try pipe.fileHandleForWriting.write(contentsOf: data)
}
try pipe.fileHandleForWriting.close()
ffmpeg.waitUntilExit()
print("Wrote \(outDir.appending(path: "sync.mp4").path) and sync.xml (\(seconds) s)")
