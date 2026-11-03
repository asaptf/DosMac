#if os(macOS)
import Foundation
import CoreGraphics
import Vision

/// Read-only observation of graphical guest dialogs. It never chooses a button or accepts a prompt.
enum GuestScreenText {
    static func recognize(_ frame: VMFrame) async throws -> String {
        try await Task.detached(priority: .utility) {
            guard let provider = CGDataProvider(data: frame.pixels as CFData),
                  let image = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: frame.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue).union(.byteOrder32Big), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw VMError.invalid("The guest frame could not be read.") }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            // VGA bitmap fonts are often only 8–10 pixels high. Enlarge without blurring their strokes.
            var readable = image
            if frame.width <= 1024,
               let context = CGContext(data: nil, width: frame.width * 2, height: frame.height * 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                context.interpolationQuality = .none
                context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(frame.width * 2), height: CGFloat(frame.height * 2)))
                if let enlarged = context.makeImage() { readable = enlarged }
            }
            try VNImageRequestHandler(cgImage: readable).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}
#endif
