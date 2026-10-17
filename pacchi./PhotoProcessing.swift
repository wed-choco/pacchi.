import Foundation
import CoreImage
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

enum RetroPhotoFilter: String, Codable, CaseIterable, Sendable {
    case original, heisei, softPink
    var label: String {
        switch self { case .original: "Original"; case .heisei: "Heisei"; case .softPink: "Soft Pink" }
    }
    func next(_ delta: Int) -> RetroPhotoFilter {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + delta % all.count + all.count) % all.count]
    }
}

struct AlbumPhoto: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var capturedAt: Date
    var originalReference: String
    var processedReference: String
    var filter: RetroPhotoFilter
    var favorite: Bool
    var dateStamp: Bool
    var timeZoneIdentifier: String
}

// Immutable images may cross the serial capture/render queue and the main actor.
struct CapturedPhoto: @unchecked Sendable {
    let original: CGImage
    let processed: CGImage
    let originalJPEG: Data
    let processedJPEG: Data
    let capturedAt: Date
    let filter: RetroPhotoFilter
    let dateStamp: Bool
    let timeZoneIdentifier: String
}

nonisolated enum PhotoProcessing {
    static func dateText(_ date: Date, timeZone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: timeZone) ?? .current
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
    static func normalized(_ data: Data, maximum: Int = 2048) throws -> CGImage {
        guard data.count <= 25_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximum
              ] as CFDictionary) else { throw PhotoError.processing }
        return image
    }
    static func render(_ source: CIImage, filter: RetroPhotoFilter, stamp: Bool,
                       date: Date, timeZone: String, context: CIContext) throws -> CGImage {
        var image = source
        let extent = source.extent
        switch filter {
        case .original: break
        case .heisei:
            image = image.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(1, max(extent.width, extent.height) / 280)])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.72, kCIInputContrastKey: 0.86, kCIInputBrightnessKey: 0.035])
                .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1.02, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0.96, w: 0), "inputBiasVector": CIVector(x: 0.025, y: 0.012, z: 0, w: 0)])
        case .softPink:
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.8, kCIInputContrastKey: 0.93, kCIInputBrightnessKey: 0.02])
                .applyingFilter("CIColorMatrix", parameters: ["inputBiasVector": CIVector(x: 0.045, y: 0.008, z: 0.025, w: 0)])
        }
        guard let result = context.createCGImage(image.cropped(to: extent), from: extent) else { throw PhotoError.processing }
        return stamp ? try stamped(result, date: date, timeZone: timeZone) : result
    }
    static func jpeg(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw PhotoError.processing }
        // Pixels only: no EXIF/GPS or camera metadata is copied.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoError.processing }
        return data as Data
    }
    static func process(_ original: CGImage, filter: RetroPhotoFilter, stamp: Bool, date: Date, timeZone: String) throws -> (CGImage, Data) {
        let context = CIContext(options: [.cacheIntermediates: false])
        let processed = try render(CIImage(cgImage: original), filter: filter, stamp: stamp, date: date, timeZone: timeZone, context: context)
        return (processed, try jpeg(processed))
    }
    private static func stamped(_ image: CGImage, date: Date, timeZone: String) throws -> CGImage {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PhotoError.processing }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let size = max(8, width * 0.035)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Menlo-Bold" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 0.79, blue: 0.51, alpha: 1)
        ]
        let text = NSAttributedString(string: dateText(date, timeZone: timeZone), attributes: attributes)
        let line = CTLineCreateWithAttributedString(text)
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let padding = width * 0.035
        context.setShadow(offset: CGSize(width: 1, height: -1), blur: 1, color: CGColor(gray: 0, alpha: 0.8))
        context.textPosition = CGPoint(x: max(padding, width - textWidth - padding), y: padding)
        CTLineDraw(line, context)
        guard let result = context.makeImage() else { throw PhotoError.processing }
        return result
    }
}

nonisolated enum PhotoError: LocalizedError {
    case processing, unavailable, save
    var errorDescription: String? {
        switch self {
        case .processing: "写真を処理できません。撮り直すか、もう一度お試しください。"
        case .unavailable: "カメラを利用できません。iPhone実機でお試しください。"
        case .save: "写真を保存できませんでした。空き容量と端末のロック状態を確認してください。"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

struct RenderedAlbumImage: @unchecked Sendable { let image: CGImage; let jpeg: Data }
actor PhotoRenderWorker {
    func render(url: URL, filter: RetroPhotoFilter, stamp: Bool, date: Date, timeZone: String) throws -> RenderedAlbumImage {
        try Task.checkCancellation()
        let original = try PhotoProcessing.normalized(Data(contentsOf: url))
        let (image, jpeg) = try PhotoProcessing.process(original, filter: filter, stamp: stamp, date: date, timeZone: timeZone)
        try Task.checkCancellation()
        return RenderedAlbumImage(image: image, jpeg: jpeg)
    }
}
