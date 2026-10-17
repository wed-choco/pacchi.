import Foundation
import Observation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

@MainActor @Observable
final class MemoryStore {
    private(set) var archive = PhoneArchive()
    private(set) var loadError: String?
    private let thumbnails = NSCache<NSString, CGImage>()
    private let directory: URL
    private let file: URL
    init(directory: URL? = nil) {
        let base = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("Pacchi", isDirectory: true)
        self.directory = base
        self.file = base.appendingPathComponent("memories-v1.json")
        thumbnails.totalCostLimit = 8 * 1024 * 1024
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let originalData = try Data(contentsOf: file)
                var decoded = try JSONDecoder().decode(PhoneArchive.self, from: originalData)
                guard (1...2).contains(decoded.version),
                      decoded.moments.allSatisfy({ MemoryStore.prompts.indices.contains($0.promptId) }),
                      decoded.momentDraft.map({ MemoryStore.prompts.indices.contains($0.promptId) }) ?? true else { throw MemoryError.unreadable }
                if decoded.version == 1 {
                    let backup = base.appendingPathComponent("memories-before-album.json")
                    if !FileManager.default.fileExists(atPath: backup.path) {
                        #if os(iOS)
                        try originalData.write(to: backup, options: [.atomic, .completeFileProtection])
                        #else
                        try originalData.write(to: backup, options: .atomic)
                        #endif
                    }
                    decoded.version = 2
                }
                archive = decoded
            }
        } catch { loadError = "保存データを読めません。元ファイルは保持しています。" }
    }
    func update(_ change: (inout PhoneArchive) throws -> Void) throws {
        guard loadError == nil else { throw MemoryError.unreadable }
        var next = archive
        try change(&next)
        next.version = 2
        let data = try JSONEncoder().encode(next)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        archive = next
    }
    func imageURL(_ reference: String?) -> URL? {
        guard let reference, reference.hasSuffix(".jpg"), !reference.contains("/"), !reference.contains("..") else { return nil }
        return directory.appendingPathComponent(reference)
    }
    func image(_ reference: String?, maximum: Int = 1024) -> CGImage? {
        guard let url = imageURL(reference) else { return nil }
        let key = "\(url.lastPathComponent)-\(maximum)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(32, maximum)
              ] as CFDictionary) else { return nil }
        thumbnails.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
    func importPhoto(_ data: Data) throws -> String {
        guard data.count <= 25_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { throw MemoryError.invalidImage }
        return try writeImage(image)
    }
    func shareablePhoto(_ reference: String) throws -> Data {
        guard let url = imageURL(reference), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 480
              ] as CFDictionary) else { throw MemoryError.invalidImage }
        let data = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw MemoryError.invalidImage }
        CGImageDestinationAddImage(target, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(target), data.length <= 200_000 else { throw MemoryError.invalidImage }
        return data as Data
    }
    func crop(_ reference: String, zoom: Double, x: Double, y: Double) throws -> String {
        guard let image = image(reference) else { throw MemoryError.invalidImage }
        let side = Double(min(image.width, image.height)) / max(1, min(3, zoom))
        let rect = CGRect(x: max(0, min(1, x)) * (Double(image.width) - side),
                          y: max(0, min(1, y)) * (Double(image.height) - side), width: side, height: side).integral
        guard let cropped = image.cropping(to: rect) else { throw MemoryError.invalidImage }
        return try writeImage(cropped)
    }
    private func writeImage(_ image: CGImage) throws -> String {
        let reference = UUID().uuidString + ".jpg"
        let data = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw MemoryError.invalidImage }
        // Re-encode pixels only: strip source location and EXIF metadata.
        CGImageDestinationAddImage(target, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(target) else { throw MemoryError.invalidImage }
        #if os(iOS)
        try (data as Data).write(to: directory.appendingPathComponent(reference), options: [.atomic, .completeFileProtection])
        #else
        try (data as Data).write(to: directory.appendingPathComponent(reference), options: .atomic)
        #endif
        return reference
    }
    func removeUnusedPhoto(_ reference: String?) {
        guard let reference, !archive.stickers.contains(where: { $0.imageReference == reference }),
              !archive.moments.contains(where: { $0.imageReference == reference }), archive.momentDraft?.imageReference != reference,
              !archive.photos.contains(where: { $0.originalReference == reference || $0.processedReference == reference }), let url = imageURL(reference) else { return }
        thumbnails.removeAllObjects()
        try? FileManager.default.removeItem(at: url)
    }
    private func writeJPEGData(_ data: Data) throws -> String {
        let reference = UUID().uuidString + ".jpg"
        #if os(iOS)
        try data.write(to: directory.appendingPathComponent(reference), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: directory.appendingPathComponent(reference), options: .atomic)
        #endif
        return reference
    }
    @discardableResult func saveCapture(_ capture: CapturedPhoto) throws -> String {
        guard loadError == nil else { throw MemoryError.unreadable }
        let original = try writeJPEGData(capture.originalJPEG)
        var processed: String?
        do {
            let output = try writeJPEGData(capture.processedJPEG); processed = output
            let photo = AlbumPhoto(id: UUID().uuidString, capturedAt: capture.capturedAt, originalReference: original,
                processedReference: output, filter: capture.filter, favorite: false, dateStamp: capture.dateStamp,
                timeZoneIdentifier: capture.timeZoneIdentifier)
            try update { $0.photos.insert(photo, at: 0) }
            return photo.id
        } catch { removeUnusedPhoto(original); removeUnusedPhoto(processed); throw error }
    }
    func updatePhoto(_ id: String, filter: RetroPhotoFilter, stamp: Bool, jpeg: Data) throws {
        guard let existing = archive.photos.first(where: { $0.id == id }) else { throw MemoryError.missing }
        let reference = try writeJPEGData(jpeg)
        do {
            try update { state in
                guard let index = state.photos.firstIndex(where: { $0.id == id }) else { throw MemoryError.missing }
                state.photos[index].processedReference = reference
                state.photos[index].filter = filter; state.photos[index].dateStamp = stamp
            }
            removeUnusedPhoto(existing.processedReference)
        } catch { removeUnusedPhoto(reference); throw error }
    }
    func favoritePhoto(_ id: String) throws {
        try update { state in
            guard let index = state.photos.firstIndex(where: { $0.id == id }) else { throw MemoryError.missing }
            state.photos[index].favorite.toggle()
        }
    }
    func deletePhoto(_ id: String) throws {
        guard let photo = archive.photos.first(where: { $0.id == id }) else { throw MemoryError.missing }
        try update { $0.photos.removeAll { $0.id == id } }
        removeUnusedPhoto(photo.originalReference); removeUnusedPhoto(photo.processedReference)
    }
    func copyPhotoForSticker(_ photo: AlbumPhoto) throws -> String {
        guard let source = imageURL(photo.processedReference) else { throw MemoryError.invalidImage }
        return try writeJPEGData(Data(contentsOf: source))
    }
    func addHandmade(shape: StickerShape, caption: String, photo: String?, memory: String?) throws -> String {
        let id = UUID().uuidString
        let memoryId = memory.map { _ in UUID().uuidString }
        try update { state in
            if let memory, let memoryId { state.memories.append(PrivateMemory(id: memoryId, text: memory, createdAt: Date())) }
            state.stickers.append(MemorySticker(id: id, title: caption.isEmpty ? "MY LITTLE MEMORY" : String(caption.prefix(24)), type: .handmade, imageReference: photo, linkedMemoryId: memoryId, createdAt: Date(), shape: shape))
        }
        return id
    }
    func editSticker(_ id: String, _ change: (inout MemorySticker) -> Void) throws {
        try update { state in
            guard let index = state.stickers.firstIndex(where: { $0.id == id }) else { throw MemoryError.missing }
            change(&state.stickers[index])
            state.stickers[index].position.x = max(0, min(1, state.stickers[index].position.x))
            state.stickers[index].position.y = max(0, min(1, state.stickers[index].position.y))
            state.stickers[index].scale = max(0.6, min(1.7, state.stickers[index].scale))
        }
    }
    func deleteSticker(_ id: String) throws {
        let sticker = archive.stickers.first { $0.id == id }
        try update { state in
            if sticker?.ownerId != nil { state.deletedStickerIDs = (state.deletedStickerIDs ?? []) + [id] }
            state.stickers.removeAll { $0.id == id }
            state.profile.publicStickerIds.removeAll { $0 == id }
            if let memory = sticker?.linkedMemoryId { state.memories.removeAll { $0.id == memory } }
        }
        removeUnusedPhoto(sticker?.imageReference)
    }
    func mergeVerifiedStickers(_ stickers: [MemorySticker], ownerId: String) throws {
        try update { state in
            for var sticker in stickers where sticker.ownerId == ownerId {
                guard !state.stickers.contains(where: { $0.id == sticker.id }), !(state.deletedStickerIDs ?? []).contains(sticker.id) else { continue }
                // Remote content cannot inject local file references or unapproved images.
                sticker.imageReference = nil
                sticker.linkedMemoryId = nil
                sticker.placed = false
                state.stickers.append(sticker)
            }
        }
    }
    static let prompts = ["今日を色であらわすと？", "ちょっと笑顔になったことは？", "今日の空を残してみよう", "今日を思い出す曲は？", "小さなありがとうをひとつ"]
    static func dayID(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func promptIndex(_ date: Date = Date(), calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let value = (c.year ?? 0) * 372 + (c.month ?? 0) * 31 + (c.day ?? 0)
        return value % prompts.count
    }
}

enum MemoryError: LocalizedError {
    case unreadable, invalidImage, missing, backendRequired, invalidResponse
    case service(String)
    var errorDescription: String? {
        switch self {
        case .service(let message): message
        case .unreadable: "保存データを読めません。上書きせず保持しました。"
        case .invalidImage: "この写真は読み込めません（25MBまで）。"
        case .missing: "思い出が見つかりません。"
        case .backendRequired: "友達との接続にはFirebaseの設定とログインが必要です。"
        case .invalidResponse: "接続を確認できません。もう一度お試しください。"
        }
    }
}
